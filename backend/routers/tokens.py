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
    separate_token: bool = False,
) -> list[dict]:
    """
    THE MAIN ENGINE — assigns each name to a token slot.
    
    Rules (UPDATED FOR GLOBAL TOKENS):
    1. Find the latest PARTIAL token with matching capacity
    2. Fill its remaining slots first
    3. If all slots are filled, create a NEW token
    4. Repeat until all names are assigned
    
    If separate_token=True, skip step 1 and always create a fresh token
    so the family stays together.
    """
    # Get max slots from category, default to 7
    category = db.query(Category).filter(Category.title == category_title).first()
    max_slots = category.hissah_per_token if category else 7

    assignments = []
    # When separate_token is True, we track the dedicated token we create
    dedicated_token = None

    for name in owner_names:
        partial_token = None
        
        if separate_token and dedicated_token is not None:
            # Re-use the dedicated token we already created for this family
            if dedicated_token.filled_slots < dedicated_token.max_slots:
                partial_token = dedicated_token
        elif not separate_token:
            # Normal flow: find any existing partial token with matching capacity
            partial_token = (
                db.query(Token)
                .filter(
                    Token.max_slots == max_slots,
                    Token.status == "partial",
                    Token.qurbani_done == False
                )
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
            
            # Track this as the dedicated token for the family
            if separate_token:
                dedicated_token = new_token

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
        
        # SELF-HEALING: Fix any corrupted ghost counts left over from previous bugs
        needs_commit = False
        for t in tokens:
            actual_count = len(t.entries)
            if actual_count == 0:
                db.delete(t)
                needs_commit = True
            elif t.filled_slots != actual_count:
                t.filled_slots = actual_count
                t.status = "full" if actual_count >= t.max_slots else "partial"
                needs_commit = True
                
        if needs_commit:
            from utils import safe_commit
            safe_commit(db, "Auto-healing token counts")
            
        # Re-query if we deleted anything, so the response is accurate
        if needs_commit:
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
        return error_response(f"Failed to update entry: {str(e)}")

class MoveEntryRequest(BaseModel):
    new_token_id: int

@router.put("/entries/{entry_id}/move")
def move_entry_to_token(entry_id: int, req: MoveEntryRequest, db: Session = Depends(get_db)):
    """Manually move a person from their current token to a different token."""
    from database import booking_lock
    
    with booking_lock:
        try:
            entry = db.query(TokenEntry).filter(TokenEntry.id == entry_id).first()
            if not entry:
                return error_response("Token entry not found")
            
            old_token_id = entry.token_id
            if old_token_id == req.new_token_id:
                return error_response("Entry is already in this token.")
                
            old_token = db.query(Token).filter(Token.id == old_token_id).first()
            new_token = db.query(Token).filter(Token.id == req.new_token_id).first()
            
            if not new_token:
                return error_response("Destination token not found")
                
            if new_token.filled_slots >= new_token.max_slots:
                return error_response("Destination token is already full.")
                
            # 1. Update the entry's token_id and set to the end of the new token
            entry.token_id = new_token.id
            entry.serial_no = new_token.filled_slots + 1
            db.flush()
            
            # 2. Repack the old token's remaining entries
            if old_token:
                remaining_entries = db.query(TokenEntry).filter(TokenEntry.token_id == old_token.id).order_by(TokenEntry.id).all()
                for idx, r_entry in enumerate(remaining_entries):
                    r_entry.serial_no = idx + 1
                
                actual_count = len(remaining_entries)
                if actual_count == 0:
                    db.delete(old_token)
                else:
                    old_token.filled_slots = actual_count
                    old_token.status = "full" if actual_count >= old_token.max_slots else "partial"
            
            # 3. Update the new token's counts
            new_token.filled_slots += 1
            if new_token.filled_slots >= new_token.max_slots:
                new_token.status = "full"
                
            safe_commit(db, "Failed to move token entry")
            return success_response(f"Successfully moved to Token #{new_token.token_no}")
            
        except Exception as e:
            return error_response(f"Failed to move token: {str(e)}")

class SwapRequest(BaseModel):
    entry1_id: int
    entry2_id: int

@router.post("/swap")
def swap_entries(req: SwapRequest, db: Session = Depends(get_db)):
    """Swap two people between their tokens, even if both tokens are full."""
    from database import booking_lock
    with booking_lock:
        try:
            entry1 = db.query(TokenEntry).filter(TokenEntry.id == req.entry1_id).first()
            entry2 = db.query(TokenEntry).filter(TokenEntry.id == req.entry2_id).first()
            
            if not entry1 or not entry2:
                return error_response("One or both entries not found")
                
            token1 = db.query(Token).filter(Token.id == entry1.token_id).first()
            token2 = db.query(Token).filter(Token.id == entry2.token_id).first()
            
            if token1.qurbani_done or token2.qurbani_done:
                return error_response("Cannot swap because one of the tokens is already marked as DONE.")
            
            # Bug #6 fix: Prevent swapping within the same token (meaningless)
            if entry1.token_id == entry2.token_id:
                return error_response("Both entries are already in the same token.")
                
            # Perform the swap!
            temp_token_id = entry1.token_id
            temp_serial_no = entry1.serial_no
            
            entry1.token_id = entry2.token_id
            entry1.serial_no = entry2.serial_no
            
            entry2.token_id = temp_token_id
            entry2.serial_no = temp_serial_no
            
            safe_commit(db, "Failed to swap entries")
            return success_response("Successfully swapped the two entries.")
        except Exception as e:
            return error_response(f"Failed to swap: {str(e)}")

class BulkMoveRequest(BaseModel):
    entry_ids: list[int]
    target_token_id: int | None = None # If None, creates a new token

@router.post("/move_bulk")
def bulk_move_entries(req: BulkMoveRequest, db: Session = Depends(get_db)):
    """Move an entire group of people into a token, or start a brand new token for them."""
    from database import booking_lock
    from sqlalchemy import func
    
    if not req.entry_ids:
        return error_response("No entries selected")
        
    with booking_lock:
        try:
            entries = db.query(TokenEntry).filter(TokenEntry.id.in_(req.entry_ids)).all()
            if len(entries) != len(req.entry_ids):
                return error_response("Some entries were not found.")
                
            # Gather old tokens and check if any are done
            old_token_ids = set(e.token_id for e in entries)
            for tid in old_token_ids:
                t = db.query(Token).filter(Token.id == tid).first()
                if t and t.qurbani_done:
                    return error_response(f"Cannot move. Token #{t.token_no} is already marked as DONE.")
            
            # Setup Target Token
            target_token = None
            if req.target_token_id:
                target_token = db.query(Token).filter(Token.id == req.target_token_id).first()
                if not target_token:
                    return error_response("Target token not found.")
                if target_token.qurbani_done:
                    return error_response("Target token is already marked as DONE.")
                if target_token.max_slots - target_token.filled_slots < len(entries):
                    return error_response(f"Target token does not have enough free space for {len(entries)} people.")
            else:
                # Create a brand new token!
                # Bug #5 fix: Validate all entries are from the same category
                source_categories = set()
                for ent in entries:
                    src_token = db.query(Token).filter(Token.id == ent.token_id).first()
                    if src_token:
                        source_categories.add(src_token.category_title)
                
                if len(source_categories) > 1:
                    return error_response(
                        f"Cannot extract mixed categories ({', '.join(source_categories)}) into one token. "
                        f"Please select people from the same category only."
                    )
                
                sample_entry = entries[0]
                sample_token = db.query(Token).filter(Token.id == sample_entry.token_id).first()
                cat_title = sample_token.category_title if sample_token else "Large Animal"
                cat = db.query(Category).filter(Category.title == cat_title).first()
                max_s = cat.hissah_per_token if cat else 7
                
                last_no = db.query(func.max(Token.token_no)).scalar() or 0
                target_token = Token(
                    token_no=last_no + 1,
                    category_title=cat_title,
                    max_slots=max_s,
                    filled_slots=0,
                    status="partial"
                )
                db.add(target_token)
                db.flush()
                
            # Move the entries
            for e in entries:
                e.token_id = target_token.id
                e.serial_no = target_token.filled_slots + 1
                target_token.filled_slots += 1
                
            target_token.status = "full" if target_token.filled_slots >= target_token.max_slots else "partial"
            db.flush()
            
            # Repack the old tokens
            for tid in old_token_ids:
                if tid == target_token.id: continue # Rare case where they move within same token?
                t = db.query(Token).filter(Token.id == tid).first()
                if t:
                    rem = db.query(TokenEntry).filter(TokenEntry.token_id == t.id).order_by(TokenEntry.id).all()
                    for idx, r_entry in enumerate(rem):
                        r_entry.serial_no = idx + 1
                    ac = len(rem)
                    if ac == 0:
                        db.delete(t)
                    else:
                        t.filled_slots = ac
                        t.status = "full" if ac >= t.max_slots else "partial"
                        
            safe_commit(db, "Failed to perform bulk move")
            return success_response(f"Successfully moved {len(entries)} people to Token #{target_token.token_no}")
            
        except Exception as e:
            return error_response(f"Failed to perform bulk move: {str(e)}")
