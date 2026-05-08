"""
Google Drive Backup Module — Automated & Manual Backups.

Exports all database tables (bookings, tokens, token_entries, categories, settings)
as a single compressed JSON file and uploads it to Google Drive.

Schedule: Every 24 hours automatically via APScheduler.
Manual: Triggered from Admin Panel via API endpoint.
"""
import os
import json
import gzip
import io
import logging
from datetime import datetime, timezone
from google.oauth2.credentials import Credentials
from google.auth.transport.requests import Request
from googleapiclient.discovery import build
from googleapiclient.http import MediaIoBaseUpload, MediaIoBaseDownload
from sqlalchemy.orm import Session
from database import SessionLocal
from models import Booking, Token, TokenEntry, Category, FormSettingsRow

logger = logging.getLogger("backup")
logger.setLevel(logging.INFO)

# ── Google Drive Config ──
SCOPES = ["https://www.googleapis.com/auth/drive"]
BACKUP_FOLDER_NAME = "Qurbani Backups"

# Cache the folder ID so we don't look it up every time
_cached_folder_id = None


def _get_credentials():
    """Load OAuth2 credentials using refresh token from environment variables."""
    refresh_token = os.environ.get("GOOGLE_REFRESH_TOKEN")
    client_id = os.environ.get("GOOGLE_CLIENT_ID")
    client_secret = os.environ.get("GOOGLE_CLIENT_SECRET")

    if not all([refresh_token, client_id, client_secret]):
        raise RuntimeError(
            "Google OAuth2 credentials not configured. "
            "Set GOOGLE_REFRESH_TOKEN, GOOGLE_CLIENT_ID, and GOOGLE_CLIENT_SECRET env vars."
        )

    creds = Credentials(
        token=None,
        refresh_token=refresh_token,
        token_uri="https://oauth2.googleapis.com/token",
        client_id=client_id,
        client_secret=client_secret,
        scopes=SCOPES,
    )
    # Refresh to get a valid access token
    creds.refresh(Request())
    return creds


def _get_drive_service():
    """Build and return Google Drive API service."""
    creds = _get_credentials()
    return build("drive", "v3", credentials=creds, cache_discovery=False)


def _find_backup_folder(service):
    """Find the 'Qurbani Backups' folder that was shared with the service account."""
    global _cached_folder_id
    if _cached_folder_id:
        return _cached_folder_id

    # Search for folder shared with this service account
    query = f"name='{BACKUP_FOLDER_NAME}' and mimeType='application/vnd.google-apps.folder' and trashed=false"
    results = service.files().list(
        q=query,
        spaces="drive",
        fields="files(id, name)",
        supportsAllDrives=True,
        includeItemsFromAllDrives=True,
    ).execute()
    files = results.get("files", [])

    if not files:
        raise RuntimeError(
            f"Folder '{BACKUP_FOLDER_NAME}' not found! "
            f"Please create a folder named '{BACKUP_FOLDER_NAME}' in your Google Drive "
            f"and share it with the service account email as Editor."
        )

    _cached_folder_id = files[0]["id"]
    logger.info(f"Found backup folder: {_cached_folder_id}")
    return _cached_folder_id


def _export_database(db: Session) -> dict:
    """Export all database tables to a dictionary."""
    # Categories
    categories = []
    for cat in db.query(Category).all():
        categories.append({
            "id": cat.id,
            "title": cat.title,
            "subtitle": cat.subtitle,
            "amount": cat.amount,
            "hissah_per_token": cat.hissah_per_token,
            "created_at": str(cat.created_at) if cat.created_at else None,
        })

    # Bookings
    bookings = []
    for b in db.query(Booking).all():
        bookings.append({
            "id": b.id,
            "receipt_no": b.receipt_no,
            "category_title": b.category_title,
            "amount_per_hissah": b.amount_per_hissah,
            "purpose": b.purpose,
            "representative_name": b.representative_name,
            "owner_names": b.owner_names,
            "hissah_count": b.hissah_count,
            "total_amount": b.total_amount,
            "address": b.address,
            "mobile": b.mobile,
            "reference": b.reference,
            "custom_fields_data": b.custom_fields_data,
            "payment_status": b.payment_status,
            "booking_status": b.booking_status,
            "created_at": str(b.created_at) if b.created_at else None,
        })

    # Tokens
    tokens = []
    for t in db.query(Token).all():
        tokens.append({
            "id": t.id,
            "token_no": t.token_no,
            "category_title": t.category_title,
            "max_slots": t.max_slots,
            "filled_slots": t.filled_slots,
            "status": t.status,
            "qurbani_done": t.qurbani_done,
            "qurbani_done_at": str(t.qurbani_done_at) if t.qurbani_done_at else None,
            "created_at": str(t.created_at) if t.created_at else None,
        })

    # Token Entries
    entries = []
    for e in db.query(TokenEntry).all():
        entries.append({
            "id": e.id,
            "token_id": e.token_id,
            "serial_no": e.serial_no,
            "owner_name": e.owner_name,
            "booking_id": e.booking_id,
            "purpose": e.purpose,
            "created_at": str(e.created_at) if e.created_at else None,
        })

    # Settings
    settings_data = {}
    row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
    if row:
        try:
            settings_data = json.loads(row.settings_json)
            # Remove large base64 blobs from backup to save space
            settings_data.pop("logoBase64", None)
            settings_data.pop("rulesAttachmentBase64", None)
        except:
            settings_data = {}

    return {
        "backup_version": "1.0",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "stats": {
            "categories": len(categories),
            "bookings": len(bookings),
            "tokens": len(tokens),
            "token_entries": len(entries),
        },
        "data": {
            "categories": categories,
            "bookings": bookings,
            "tokens": tokens,
            "token_entries": entries,
            "settings": settings_data,
        },
    }


def create_backup(db: Session) -> dict:
    """
    Full backup flow:
    1. Export all tables to JSON
    2. Compress with gzip
    3. Upload to Google Drive
    Returns: dict with backup details (filename, size, gdrive file id)
    """
    logger.info("Starting backup...")

    # Step 1: Export
    data = _export_database(db)
    json_str = json.dumps(data, ensure_ascii=False, indent=2)

    # Step 2: Compress
    buffer = io.BytesIO()
    with gzip.GzipFile(fileobj=buffer, mode="wb") as gz:
        gz.write(json_str.encode("utf-8"))
    compressed_bytes = buffer.getvalue()
    size_kb = len(compressed_bytes) / 1024

    # Step 3: Upload to Google Drive
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")
    filename = f"qurbani_backup_{timestamp}.json.gz"

    service = _get_drive_service()
    folder_id = _find_backup_folder(service)

    file_metadata = {
        "name": filename,
        "parents": [folder_id],
    }
    media = MediaIoBaseUpload(io.BytesIO(compressed_bytes), mimetype="application/gzip")
    uploaded = service.files().create(body=file_metadata, media_body=media, fields="id,name,size").execute()

    logger.info(f"Backup uploaded: {filename} ({size_kb:.1f} KB) -> GDrive ID: {uploaded['id']}")

    return {
        "filename": filename,
        "gdrive_file_id": uploaded["id"],
        "size_kb": round(size_kb, 1),
        "stats": data["stats"],
        "created_at": data["created_at"],
    }


def list_backups(limit: int = 20) -> list:
    """List recent backups from Google Drive folder."""
    service = _get_drive_service()
    folder_id = _find_backup_folder(service)

    query = f"'{folder_id}' in parents and trashed=false"
    results = service.files().list(
        q=query,
        spaces="drive",
        fields="files(id, name, size, createdTime)",
        orderBy="createdTime desc",
        pageSize=limit,
    ).execute()

    backups = []
    for f in results.get("files", []):
        backups.append({
            "gdrive_file_id": f["id"],
            "filename": f["name"],
            "size_kb": round(int(f.get("size", 0)) / 1024, 1),
            "created_at": f.get("createdTime", ""),
        })
    return backups


def restore_backup(db: Session, gdrive_file_id: str) -> dict:
    """
    Download a backup from Google Drive and restore it into the database.
    WARNING: This REPLACES all existing data!
    """
    service = _get_drive_service()

    # Download file
    request = service.files().get_media(fileId=gdrive_file_id)
    buffer = io.BytesIO()
    downloader = MediaIoBaseDownload(buffer, request)
    done = False
    while not done:
        _, done = downloader.next_chunk()

    # Decompress
    buffer.seek(0)
    with gzip.GzipFile(fileobj=buffer, mode="rb") as gz:
        json_str = gz.read().decode("utf-8")
    data = json.loads(json_str)

    backup_data = data.get("data", {})

    # Clear existing data (order matters due to foreign keys)
    db.query(TokenEntry).delete()
    db.query(Token).delete()
    db.query(Booking).delete()
    db.query(Category).delete()

    # Restore Categories
    for cat in backup_data.get("categories", []):
        db.add(Category(
            id=cat["id"],
            title=cat["title"],
            subtitle=cat.get("subtitle", ""),
            amount=cat["amount"],
            hissah_per_token=cat.get("hissah_per_token", 7),
        ))
    db.flush()

    # Restore Bookings
    for b in backup_data.get("bookings", []):
        db.add(Booking(
            id=b["id"],
            receipt_no=b["receipt_no"],
            category_title=b["category_title"],
            amount_per_hissah=b["amount_per_hissah"],
            purpose=b.get("purpose", "Qurbani"),
            representative_name=b.get("representative_name", ""),
            owner_names=b.get("owner_names", "[]"),
            hissah_count=b["hissah_count"],
            total_amount=b["total_amount"],
            address=b.get("address", ""),
            mobile=b.get("mobile", ""),
            reference=b.get("reference", ""),
            custom_fields_data=b.get("custom_fields_data", "{}"),
            payment_status=b.get("payment_status", "unpaid"),
            booking_status=b.get("booking_status", "confirmed"),
        ))
    db.flush()

    # Restore Tokens
    for t in backup_data.get("tokens", []):
        db.add(Token(
            id=t["id"],
            token_no=t["token_no"],
            category_title=t["category_title"],
            max_slots=t["max_slots"],
            filled_slots=t["filled_slots"],
            status=t.get("status", "partial"),
            qurbani_done=t.get("qurbani_done", False),
        ))
    db.flush()

    # Restore Token Entries
    for e in backup_data.get("token_entries", []):
        db.add(TokenEntry(
            id=e["id"],
            token_id=e["token_id"],
            serial_no=e["serial_no"],
            owner_name=e["owner_name"],
            booking_id=e.get("booking_id"),
            purpose=e.get("purpose", "Qurbani"),
        ))

    # Restore Settings (merge — keep existing logo/rules blobs)
    settings_backup = backup_data.get("settings", {})
    if settings_backup:
        row = db.query(FormSettingsRow).filter(FormSettingsRow.id == 1).first()
        if row:
            try:
                existing = json.loads(row.settings_json)
                # Keep blobs from current, restore everything else from backup
                settings_backup["logoBase64"] = existing.get("logoBase64", "")
                settings_backup["rulesAttachmentBase64"] = existing.get("rulesAttachmentBase64", "")
            except:
                pass
            row.settings_json = json.dumps(settings_backup, ensure_ascii=False)
        else:
            db.add(FormSettingsRow(id=1, settings_json=json.dumps(settings_backup, ensure_ascii=False)))

    db.commit()

    stats = data.get("stats", {})
    logger.info(f"Backup restored: {stats}")
    return {
        "message": "Backup restored successfully",
        "stats": stats,
        "backup_date": data.get("created_at", ""),
    }


def run_scheduled_backup():
    """Called by APScheduler every 24 hours."""
    logger.info("⏰ Scheduled backup triggered")
    db = SessionLocal()
    try:
        result = create_backup(db)
        logger.info(f"✅ Scheduled backup complete: {result['filename']}")
    except Exception as e:
        logger.error(f"❌ Scheduled backup failed: {e}")
    finally:
        db.close()
