"""
Backup Router — API endpoints for backup management.

Endpoints:
  POST /api/backup/create   — Trigger a manual backup now
  GET  /api/backup/list     — List recent backups from Google Drive
  POST /api/backup/restore  — Restore from a specific backup
  GET  /api/backup/status   — Check if backup system is configured
"""
import json
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.orm import Session
from database import get_db
from models import FormSettingsRow
from utils import success_response, error_response
from backup import create_backup, list_backups, restore_backup

router = APIRouter(prefix="/api/backup", tags=["Backup"])


def _verify_admin(db: Session, email: str, password: str) -> bool:
    """Quick admin credential check (reused pattern from main.py)."""
    admin_email = "taalimulquran@madrasa.com"
    admin_password = "ahemfariza@0011"
    row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
    if row:
        try:
            data = json.loads(row.settings_json)
            admin_email = data.get("adminEmail", admin_email)
            admin_password = data.get("adminPassword", admin_password)
        except:
            pass
    return email == admin_email and password == admin_password


class AdminPayload(BaseModel):
    email: str
    password: str


class RestorePayload(BaseModel):
    email: str
    password: str
    gdrive_file_id: str


@router.get("/status")
def backup_status():
    """Check if Google Drive backup is properly configured."""
    import os
    configured = bool(os.environ.get("GOOGLE_REFRESH_TOKEN") and os.environ.get("GOOGLE_CLIENT_ID"))
    return success_response("Backup status", {"configured": configured})


@router.post("/create")
def trigger_backup(payload: AdminPayload, db: Session = Depends(get_db)):
    """Trigger a manual backup. Requires admin credentials."""
    if not _verify_admin(db, payload.email, payload.password):
        return error_response("Invalid admin credentials")
    try:
        result = create_backup(db)
        return success_response("Backup created successfully", result)
    except Exception as e:
        return error_response(f"Backup failed: {str(e)}")


@router.get("/list")
def get_backup_list():
    """List recent backups stored in Google Drive."""
    try:
        backups = list_backups(limit=30)
        return success_response("Backups fetched", {"backups": backups, "count": len(backups)})
    except Exception as e:
        return error_response(f"Failed to list backups: {str(e)}")


@router.post("/restore")
def restore_from_backup(payload: RestorePayload, db: Session = Depends(get_db)):
    """Restore database from a Google Drive backup. Requires admin credentials."""
    if not _verify_admin(db, payload.email, payload.password):
        return error_response("Invalid admin credentials")
    try:
        result = restore_backup(db, payload.gdrive_file_id)
        return success_response("Backup restored", result)
    except Exception as e:
        return error_response(f"Restore failed: {str(e)}")
