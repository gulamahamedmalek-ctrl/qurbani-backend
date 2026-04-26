"""
Bookings Router — Full CRUD for customer Hissah bookings.
Auto-generates sequential receipt numbers.
"""
import json
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func
from database import get_db
from models import Booking, FormSettingsRow
from schemas import BookingCreate, BookingResponse
from utils import success_response, error_response, get_or_404, safe_commit

router = APIRouter(prefix="/api/bookings", tags=["Bookings"])


def _generate_receipt_no(db: Session) -> str:
    """
    Auto-generate the next receipt number using the admin's configured prefix.
    Reusable logic isolated in one place — if the format ever changes, fix it here only.
    """
    # Get receipt prefix from settings
    prefix = "RCPT-"
    start_num = 1
    settings_row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
    if settings_row:
        try:
            settings_data = json.loads(settings_row.settings_json)
            prefix = settings_data.get("receiptPrefix", "RCPT-")
            start_num = settings_data.get("startingReceiptNumber", 1)
        except (json.JSONDecodeError, KeyError):
            pass

    # Get the current highest booking ID to determine next number
    max_id = db.query(func.max(Booking.id)).scalar() or 0
    
    # Next number = (historical bookings count) + custom start offset
    # If this is the very first booking (max_id = 0), it gets exactly start_num
    # If someone booked 5 people already (max_id = 5), next is start_num + 5
    next_number = max_id + start_num
    return f"{prefix}{next_number}"


@router.get("/")
def list_bookings(query: str = None, db: Session = Depends(get_db)):
    """Fetch all bookings, with optional query filtering by Name, Mobile, or Receipt."""
    try:
        q = db.query(Booking)
        if query:
            q = q.filter(
                (Booking.representative_name.ilike(f"%{query}%")) |
                (Booking.mobile.ilike(f"%{query}%")) |
                (Booking.receipt_no.ilike(f"%{query}%"))
            )
        
        bookings = q.order_by(Booking.id.desc()).all()
        data = [BookingResponse.model_validate(b).model_dump() for b in bookings]
        return success_response("Bookings fetched", data)
    except Exception as e:
        return error_response(f"Failed to fetch bookings: {str(e)}")


@router.post("/")
def create_booking(payload: BookingCreate, db: Session = Depends(get_db)):
    """Create a new customer booking with auto-generated receipt number + auto token assignment.
    
    CONCURRENCY SAFE: The booking_lock ensures that even if two cashiers
    click 'Book' at the exact same millisecond, they queue in order.
    """
    from database import booking_lock
    
    with booking_lock:
        try:
            receipt_no = _generate_receipt_no(db)

            booking = Booking(
                receipt_no=receipt_no,
                category_title=payload.category_title,
                amount_per_hissah=payload.amount_per_hissah,
                purpose=payload.purpose,
                representative_name=payload.representative_name,
                owner_names=json.dumps(payload.owner_names),
                hissah_count=payload.hissah_count,
                total_amount=payload.total_amount,
                address=payload.address,
                mobile=payload.mobile,
                reference=payload.reference,
                custom_fields_data=json.dumps(payload.custom_fields_data),
            )
            db.add(booking)
            db.flush() # Get booking.id

            # AUTO-ASSIGN NAMES TO TOKENS
            from routers.tokens import assign_names_to_tokens
            token_assignments = assign_names_to_tokens(
                db=db,
                category_title=payload.category_title,
                owner_names=payload.owner_names,
                booking_id=booking.id,
                purpose=payload.purpose,
            )

            # ONE SINGLE COMMIT for everything (Booking + Token Entries)
            safe_commit(db, "Failed to complete booking transaction")
            db.refresh(booking)

            data = BookingResponse.model_validate(booking).model_dump()
            data["token_assignments"] = token_assignments
            return success_response("Booking created", data)
        except Exception as e:
            return error_response(f"Failed to create booking: {str(e)}")


@router.get("/{booking_id}/details/")
def get_booking_details(booking_id: int, db: Session = Depends(get_db)):
    """Fetch a deep profile of a booking, including linked animal tokens."""
    try:
        booking = get_or_404(db, Booking, booking_id, "Booking")
        
        # Find all token entries for this booking
        from models import TokenEntry, Token
        entries = db.query(TokenEntry).filter(TokenEntry.booking_id == booking_id).all()
        
        # Enhance entries with Token info (token_no, qurbani_done)
        hissah_entries = []
        for e in entries:
            token = db.query(Token).filter(Token.id == e.token_id).first()
            hissah_entries.append({
                "id": e.id,
                "token_id": e.token_id,
                "token_no": token.token_no if token else 0,
                "category_title": token.category_title if token else "",
                "qurbani_done": token.qurbani_done if token else False,
                "serial_no": e.serial_no,
                "owner_name": e.owner_name,
                "purpose": e.purpose,
            })
            
        data = {
            "booking": BookingResponse.model_validate(booking).model_dump(),
            "hissah_entries": hissah_entries
        }
        return success_response("Booking details fetched", data)
    except Exception as e:
        return error_response(f"Failed to fetch booking details: {str(e)}")


@router.get("/{booking_id}/")
def get_booking(booking_id: int, db: Session = Depends(get_db)):
    """Fetch a single booking by ID."""
    try:
        booking = get_or_404(db, Booking, booking_id, "Booking")
        data = BookingResponse.model_validate(booking).model_dump()
        return success_response("Booking fetched", data)
    except Exception as e:
        return error_response(f"Failed to fetch booking: {str(e)}")


@router.delete("/{booking_id}/")
def delete_booking(booking_id: int, db: Session = Depends(get_db)):
    """Delete a booking by ID and clean up its token entries.
    
    CONCURRENCY SAFE + CASCADE SAFE:
    - Acquires booking_lock to prevent conflicts
    - Removes orphaned TokenEntry rows from tokens
    - Recalculates filled_slots so tokens don't stay falsely "full"
    """
    from database import booking_lock
    from models import Token, TokenEntry
    
    with booking_lock:
        try:
            booking = get_or_404(db, Booking, booking_id, "Booking")
            
            # Step 1: Find all token entries linked to this booking
            orphaned_entries = db.query(TokenEntry).filter(TokenEntry.booking_id == booking_id).all()
            
            # Step 2: Track which tokens are affected so we can recalculate
            affected_token_ids = set()
            for entry in orphaned_entries:
                affected_token_ids.add(entry.token_id)
                db.delete(entry)
            
            # Step 3: Recalculate filled_slots and repack serial_no for each affected token
            for token_id in affected_token_ids:
                token = db.query(Token).filter(Token.id == token_id).first()
                if token:
                    # Fetch remaining entries for this token, ordered by their original serial_no or ID
                    remaining_entries = db.query(TokenEntry).filter(TokenEntry.token_id == token_id).order_by(TokenEntry.id).all()
                    
                    # Repack their serial numbers to be perfectly sequential (1, 2, 3...)
                    for index, r_entry in enumerate(remaining_entries):
                        r_entry.serial_no = index + 1
                    
                    actual_count = len(remaining_entries)
                    token.filled_slots = actual_count
                    token.status = "full" if actual_count >= token.max_slots else "partial"
            
            # Step 4: Delete the booking itself
            db.delete(booking)
            safe_commit(db, "Failed to delete booking")
            return success_response(f"Booking '{booking.receipt_no}' deleted and {len(orphaned_entries)} token entries cleaned up")
        except Exception as e:
            return error_response(f"Failed to delete booking: {str(e)}")


class BookingUpdate(BaseModel):
    amount_per_hissah: float
    purpose: str
    representative_name: str
    total_amount: float
    address: str
    mobile: str
    reference: str
    custom_fields_data: dict

@router.put("/{booking_id}/")
def edit_booking(booking_id: int, payload: BookingUpdate, db: Session = Depends(get_db)):
    """Edit core details of a booking (except hissah count and owner names)."""
    try:
        booking = get_or_404(db, Booking, booking_id, "Booking")
        
        booking.amount_per_hissah = payload.amount_per_hissah
        booking.purpose = payload.purpose
        booking.representative_name = payload.representative_name
        booking.total_amount = payload.total_amount
        booking.address = payload.address
        booking.mobile = payload.mobile
        booking.reference = payload.reference
        booking.custom_fields_data = json.dumps(payload.custom_fields_data)
        
        # Sync the purpose to all associated token entries
        from models import TokenEntry
        entries = db.query(TokenEntry).filter(TokenEntry.booking_id == booking_id).all()
        for e in entries:
            e.purpose = payload.purpose
            
        safe_commit(db, "Failed to update booking")
        return success_response("Booking updated successfully")
    except Exception as e:
        return error_response(f"Failed to edit booking: {str(e)}")
