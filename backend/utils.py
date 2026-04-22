"""
Reusable utility functions — imported by ALL routers.
DRY principle: write once, use everywhere.
"""
from fastapi import HTTPException
from sqlalchemy.orm import Session
from schemas import APIResponse


def success_response(message: str, data=None) -> dict:
    """Standard success response. Used in every single endpoint."""
    return APIResponse(success=True, message=message, data=data).model_dump()


def error_response(message: str, data=None) -> dict:
    """Standard error response. Used in every catch block."""
    return APIResponse(success=False, message=message, data=data).model_dump()


def get_or_404(db: Session, model, record_id: int, entity_name: str = "Record"):
    """
    Fetch a record by ID or raise 404.
    Reusable for ANY model — categories, bookings, etc.
    Eliminates duplicate 'if not found' checks across routers.
    """
    record = db.query(model).filter(model.id == record_id).first()
    if not record:
        raise HTTPException(status_code=404, detail=f"{entity_name} with id {record_id} not found")
    return record


def safe_commit(db: Session, error_msg: str = "Database operation failed"):
    """
    Commit with automatic rollback on failure.
    Reusable in every create/update/delete operation.
    """
    try:
        db.commit()
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"{error_msg}: {str(e)}")
