"""
Token Router — The CORE engine of the system.
Handles automatic token assignment: fills partial tokens first, creates new ones when needed.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func
from pydantic import BaseModel
from typing import List
from database import get_db
from models import Token, TokenEntry, Category, Booking
from schemas import TokenResponse
from utils import success_response, error_response, safe_commit

router = APIRouter(prefix="/api/tokens", tags=["Tokens"])


def assign_names_to_tokens(
    db: Session,
    category_title: str,
    owner_names: list[str],
    booking_id: int,
    purpose: str = "Qurbani",
) -> list[dict]:
    """
    THE MAIN ENGINE — assigns each name to a token slot.
    
    Rules (UPDATED FOR GLOBAL TOKENS):
    1. Find the latest PARTIAL token (regardless of category)
    2. Fill its remaining slots first
    3. If all slots are filled, create a NEW token
    4. Repeat until all names are assigned
    """
    # Get max slots from category, default to 7
    category = db.query(Category).filter(Category.title == category_title).first()
    max_slots = category.hissah_per_token if category else 7

    assignments = []

    for name in owner_names:
        # Step 1: Find the latest partial token globally
        partial_token = (
            db.query(Token)
            .filter(Token.status == "partial")
            .order_by(Token.token_no.asc())
            .first()
        )

        if partial_token:
            # Step 2: Fill the next slot in the existing partial token
            next_serial = partial_token.filled_slots + 1

            entry = TokenEntry(
                token_id=partial_token.id,
                serial_no=next_serial,
                owner_name=name,
                booking_id=booking_id,
                purpose=purpose,
            )
            db.add(entry)

            partial_token.filled_slots = next_serial
            if partial_token.filled_slots >= partial_token.max_slots:
                partial_token.status = "full"
            
            # CRITICAL FIX for 8/7 bug: Flush so the next loop iteration sees the updated status
            db.flush()

            assignments.append({
                "token_no": partial_token.token_no,
                "serial_no": next_serial,
                "owner_name": name,
            })
        else:
            # Step 3: No partial token — create a NEW one globally
            last_token_no = (
                db.query(func.max(Token.token_no))
                .scalar()
            ) or 0

            new_token = Token(
                token_no=last_token_no + 1,
                category_title=category_title, # Takes the category of whoever starts it
                max_slots=max_slots,
                filled_slots=1,
                status="full" if max_slots <= 1 else "partial",
            )
            db.add(new_token)
            db.flush() # Ensure new_token.id is available for the entry

            entry = TokenEntry(
                token_id=new_token.id,
                serial_no=1,
                owner_name=name,
                booking_id=booking_id,
                purpose=purpose,
            )
            db.add(entry)
            db.flush()

            assignments.append({
                "token_no": new_token.token_no,
                "serial_no": 1,
                "owner_name": name,
            })

    return assignments


# ═══════════════════════════════════════════════
# API ENDPOINTS
# ═══════════════════════════════════════════════

@router.get("/")
def list_tokens(category: str = None, db: Session = Depends(get_db)):
    """List all tokens, optionally filtered by category."""
    try:
        query = db.query(Token).order_by(Token.token_no)
        if category:
            query = query.filter(Token.category_title == category)
        tokens = query.all()
        data = [TokenResponse.model_validate(t).model_dump() for t in tokens]
        return success_response("Tokens fetched", data)
    except Exception as e:
        return error_response(f"Failed to fetch tokens: {str(e)}")


@router.get("/summary/")
def token_summary(db: Session = Depends(get_db)):
    """Quick summary of token status per category."""
    try:
        categories = db.query(Category).all()
        summary = []
        for cat in categories:
            total_tokens = db.query(Token).filter(Token.category_title == cat.title).count()
            full_tokens = db.query(Token).filter(Token.category_title == cat.title, Token.status == "full").count()
            partial_tokens = db.query(Token).filter(Token.category_title == cat.title, Token.status == "partial").count()
            total_names = db.query(TokenEntry).join(Token).filter(Token.category_title == cat.title).count()

            # Current partial token info
            current_partial = (
                db.query(Token)
                .filter(Token.category_title == cat.title, Token.status == "partial")
                .first()
            )

            summary.append({
                "category": cat.title,
                "hissah_per_token": cat.hissah_per_token,
                "total_tokens": total_tokens,
                "full_tokens": full_tokens,
                "partial_tokens": partial_tokens,
                "total_names": total_names,
                "current_token_no": current_partial.token_no if current_partial else None,
                "current_filled": current_partial.filled_slots if current_partial else 0,
                "current_remaining": (current_partial.max_slots - current_partial.filled_slots) if current_partial else 0,
            })

        return success_response("Token summary fetched", summary)
    except Exception as e:
        return error_response(f"Failed to fetch summary: {str(e)}")


@router.get("/{token_id}/")
def get_token(token_id: int, db: Session = Depends(get_db)):
    """Get a single token with all its entries."""
    try:
        token = db.query(Token).filter(Token.id == token_id).first()
        if not token:
            return error_response("Token not found")
        data = TokenResponse.model_validate(token).model_dump()
        return success_response("Token fetched", data)
    except Exception as e:
        return error_response(f"Failed to fetch token: {str(e)}")


@router.put("/{token_id}/qurbani-done/")
def mark_qurbani_done(token_id: int, db: Session = Depends(get_db)):
    """Mark a token's qurbani as completed with current timestamp."""
    try:
        token = db.query(Token).filter(Token.id == token_id).first()
        if not token:
            return error_response("Token not found")

        from datetime import datetime, timezone
        token.qurbani_done = True
        token.qurbani_done_at = datetime.now(timezone.utc)
        safe_commit(db, "Failed to mark qurbani done")
        db.refresh(token)

        data = TokenResponse.model_validate(token).model_dump()
        return success_response("Qurbani marked as done", data)
    except Exception as e:
        return error_response(f"Failed to mark qurbani done: {str(e)}")


class BulkTokenRequest(BaseModel):
    token_ids: List[int]

@router.put("/bulk/qurbani-done/")
def bulk_mark_qurbani_done(req: BulkTokenRequest, db: Session = Depends(get_db)):
    """Mark multiple tokens' qurbani as completed with current timestamp."""
    try:
        from datetime import datetime, timezone
        tokens = db.query(Token).filter(Token.id.in_(req.token_ids)).all()
        if not tokens:
            return error_response("No matching tokens found")
            
        now = datetime.now(timezone.utc)
        for token in tokens:
            token.qurbani_done = True
            token.qurbani_done_at = now
            
        safe_commit(db, "Failed to perform bulk qurbani update")
        
        return success_response(f"Qurbani marked as done for {len(tokens)} tokens")
    except Exception as e:
        return error_response(f"Failed to perform bulk update: {str(e)}")

class EditEntryRequest(BaseModel):
    new_name: str

@router.put("/entries/{entry_id}")
def edit_entry_name(entry_id: int, req: EditEntryRequest, db: Session = Depends(get_db)):
    """Edit the owner name of a specific hissah in a token and sync with original booking."""
    try:
        entry = db.query(TokenEntry).filter(TokenEntry.id == entry_id).first()
        if not entry:
            return error_response("Token entry not found")

        # Get all entries for this booking ordered by ID to find the correct index
        if entry.booking_id:
            booking = db.query(Booking).filter(Booking.id == entry.booking_id).first()
            if booking and booking.owner_names:
                all_entries = db.query(TokenEntry).filter(TokenEntry.booking_id == booking.id).order_by(TokenEntry.id).all()
                try:
                    # Find index of this specific entry
                    entry_index = [e.id for e in all_entries].index(entry.id)
                    
                    import json
                    owner_names = json.loads(booking.owner_names)
                    if 0 <= entry_index < len(owner_names):
                        owner_names[entry_index] = req.new_name
                        booking.owner_names = json.dumps(owner_names)
                except (ValueError, json.JSONDecodeError):
                    pass # Ignore if JSON is corrupt or index not found

        # Update the entry itself
        entry.owner_name = req.new_name
        safe_commit(db, "Failed to update owner name")
        
        return success_response("Name updated successfully")
    except Exception as e:
        return error_response(f"Failed to edit name: {str(e)}")
