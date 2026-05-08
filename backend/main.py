import os
import json
import logging
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from sqlalchemy.orm import Session
from database import init_db, get_db
from routers import categories, settings, bookings, tokens
from routers import backup as backup_router
from models import Booking, Token, TokenEntry, FormSettingsRow

logger = logging.getLogger("main")

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
app.include_router(backup_router.router)


@app.on_event("startup")
def on_startup():
    """Create database tables on first run and start backup scheduler."""
    init_db()
    print("[OK] Database initialized. Tables created.")

    # Start auto-backup scheduler if Google OAuth2 credentials are configured
    if os.environ.get("GOOGLE_REFRESH_TOKEN"):
        try:
            from apscheduler.schedulers.background import BackgroundScheduler
            from backup import run_scheduled_backup

            scheduler = BackgroundScheduler()
            scheduler.add_job(
                run_scheduled_backup,
                "interval",
                hours=24,
                id="auto_backup",
                replace_existing=True,
            )
            scheduler.start()
            logger.info("✅ Auto-backup scheduler started (every 24 hours)")
        except Exception as e:
            logger.warning(f"⚠️ Could not start backup scheduler: {e}")
    else:
        logger.info("ℹ️ Google credentials not set — auto-backup disabled")


@app.get("/", tags=["Health"])
def health_check():
    """Simple health check endpoint."""
    return {"status": "ok", "message": "Qurbani Hissah API is running"}


class AdminLoginPayload(BaseModel):
    email: str
    password: str


@app.post("/api/admin/verify", tags=["Admin"])
def verify_admin_login(payload: AdminLoginPayload, db: Session = Depends(get_db)):
    """Verify admin email + password. Returns success if credentials match."""
    admin_email = "taalimulquran@madrasa.com"
    admin_password = "ahemfariza@0011"
    settings_row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
    if settings_row:
        try:
            data = json.loads(settings_row.settings_json)
            admin_email = data.get("adminEmail", admin_email)
            admin_password = data.get("adminPassword", admin_password)
        except:
            pass
    if payload.email == admin_email and payload.password == admin_password:
        return {"success": True, "message": "Admin verified"}
    return {"success": False, "message": "Invalid credentials"}


@app.post("/api/admin/reset", tags=["Admin"])
def reset_data(payload: AdminLoginPayload, db: Session = Depends(get_db)):
    """Erase all bookings and tokens. Keeps categories and settings."""
    admin_email = "taalimulquran@madrasa.com"
    admin_password = "ahemfariza@0011"
    settings_row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
    if settings_row:
        try:
            data = json.loads(settings_row.settings_json)
            admin_email = data.get("adminEmail", admin_email)
            admin_password = data.get("adminPassword", admin_password)
        except:
            pass
    if payload.email != admin_email or payload.password != admin_password:
        return {"success": False, "message": "Invalid credentials"}

    try:
        db.query(TokenEntry).delete()
        db.query(Token).delete()
        db.query(Booking).delete()
        db.commit()
        return {"success": True, "message": "All bookings and tokens cleared"}
    except Exception as e:
        db.rollback()
        return {"success": False, "message": f"Reset failed: {str(e)}"}


