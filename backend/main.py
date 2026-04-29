from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.orm import Session
from database import init_db, get_db
from routers import categories, settings, bookings, tokens
from models import Booking, Token, TokenEntry, FormSettingsRow
import json

app = FastAPI(
    title="Qurbani Hissah API",
    description="Backend API for Qurbani Hissah Management System",
    version="1.0.0",
)

# ── CORS — Allow Flutter app (web/mobile) to talk to the server ──
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Register all routers ──
app.include_router(categories.router)
app.include_router(settings.router)
app.include_router(bookings.router)
app.include_router(tokens.router)


@app.on_event("startup")
def on_startup():
    """Create database tables on first run. Safe to call repeatedly."""
    init_db()
    print("[OK] Database initialized. Tables created.")


@app.get("/", tags=["Health"])
def health_check():
    """Simple health check endpoint."""
    return {"status": "ok", "message": "Qurbani Hissah API is running"}


class AdminPinPayload(BaseModel):
    pin: str


@app.post("/api/admin/verify", tags=["Admin"])
def verify_admin_pin(payload: AdminPinPayload, db: Session = Depends(get_db)):
    """Verify admin PIN. Returns success if PIN matches."""
    admin_pin = "1234"  # Default
    settings_row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
    if settings_row:
        try:
            data = json.loads(settings_row.settings_json)
            admin_pin = data.get("adminPin", "1234")
        except:
            pass
    if payload.pin == admin_pin:
        return {"success": True, "message": "Admin verified"}
    return {"success": False, "message": "Invalid PIN"}


@app.post("/api/admin/reset", tags=["Admin"])
def reset_data(payload: AdminPinPayload, db: Session = Depends(get_db)):
    """Erase all bookings and tokens. Keeps categories and settings."""
    # Verify admin PIN first
    admin_pin = "1234"
    settings_row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
    if settings_row:
        try:
            data = json.loads(settings_row.settings_json)
            admin_pin = data.get("adminPin", "1234")
        except:
            pass
    if payload.pin != admin_pin:
        return {"success": False, "message": "Invalid admin PIN"}

    try:
        db.query(TokenEntry).delete()
        db.query(Token).delete()
        db.query(Booking).delete()
        db.commit()
        return {"success": True, "message": "All bookings and tokens cleared"}
    except Exception as e:
        db.rollback()
        return {"success": False, "message": f"Reset failed: {str(e)}"}

