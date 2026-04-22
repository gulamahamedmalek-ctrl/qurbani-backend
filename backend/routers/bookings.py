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
def list_bookings(db: Session = Depends(get_db)):
    """Fetch all bookings, newest first."""
    try:
        bookings = db.query(Booking).order_by(Booking.id.desc()).all()
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


@router.get("/{booking_id}")
def get_booking(booking_id: int, db: Session = Depends(get_db)):
    """Fetch a single booking by ID."""
    try:
        booking = get_or_404(db, Booking, booking_id, "Booking")
        data = BookingResponse.model_validate(booking).model_dump()
        return success_response("Booking fetched", data)
    except Exception as e:
        return error_response(f"Failed to fetch booking: {str(e)}")


@router.delete("/{booking_id}")
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
            
            # Step 3: Recalculate filled_slots for each affected token
            for token_id in affected_token_ids:
                token = db.query(Token).filter(Token.id == token_id).first()
                if token:
                    actual_count = db.query(TokenEntry).filter(TokenEntry.token_id == token_id).count()
                    token.filled_slots = actual_count
                    token.status = "full" if actual_count >= token.max_slots else "partial"
            
            # Step 4: Delete the booking itself
            db.delete(booking)
            safe_commit(db, "Failed to delete booking")
            return success_response(f"Booking '{booking.receipt_no}' deleted and {len(orphaned_entries)} token entries cleaned up")
        except Exception as e:
            return error_response(f"Failed to delete booking: {str(e)}")
