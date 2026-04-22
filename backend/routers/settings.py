"""
Settings Router — GET/PUT for the singleton FormSettings row.
Stores all admin config as a single JSON blob.
"""
import json
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from models import FormSettingsRow
from schemas import FormSettingsSchema
from utils import success_response, error_response, safe_commit

router = APIRouter(prefix="/api/settings", tags=["Settings"])

# Default settings used when no row exists yet
_DEFAULTS = FormSettingsSchema()


def _get_or_create_settings(db: Session) -> FormSettingsRow:
    """
    Reusable: fetch the singleton settings row, or create it with defaults.
    This function is used by BOTH get and put — written once.
    """
    row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
    if not row:
        row = FormSettingsRow(id=1, settings_json=_DEFAULTS.model_dump_json())
        db.add(row)
        safe_commit(db, "Failed to initialize settings")
        db.refresh(row)
    return row


@router.get("/")
def get_settings(db: Session = Depends(get_db)):
    """Fetch all admin form settings."""
    try:
        row = _get_or_create_settings(db)
        data = json.loads(row.settings_json)
        return success_response("Settings fetched", data)
    except Exception as e:
        return error_response(f"Failed to fetch settings: {str(e)}")


@router.put("/")
def update_settings(payload: FormSettingsSchema, db: Session = Depends(get_db)):
    """Overwrite all admin form settings."""
    try:
        row = _get_or_create_settings(db)
        row.settings_json = payload.model_dump_json()
        safe_commit(db, "Failed to save settings")
        db.refresh(row)
        data = json.loads(row.settings_json)
        return success_response("Settings saved", data)
    except Exception as e:
        return error_response(f"Failed to save settings: {str(e)}")
