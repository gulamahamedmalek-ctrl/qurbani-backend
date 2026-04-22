"""
Categories Router — Full CRUD for Qurbani categories.
Uses shared utils for DRY error handling and responses.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from database import get_db
from models import Category
from schemas import CategoryCreate, CategoryUpdate, CategoryResponse, CategorySync
from utils import success_response, error_response, get_or_404, safe_commit

router = APIRouter(prefix="/api/categories", tags=["Categories"])


@router.post("/sync/")
def sync_categories(payload: CategorySync, db: Session = Depends(get_db)):
    """
    Bulk synchronize categories. 
    Deletes all existing ones and replaces them with the new list in ONE transaction.
    """
    try:
        # Delete all existing
        db.query(Category).delete()
        
        # Add new ones
        for item in payload.categories:
            db.add(Category(
                title=item.title,
                subtitle=item.subtitle,
                amount=item.amount,
                hissah_per_token=item.hissah_per_token
            ))
        
        safe_commit(db, "Failed to sync categories")
        return success_response("Categories synchronized successfully")
    except Exception as e:
        return error_response(f"Sync failed: {str(e)}")


@router.get("/")
def list_categories(db: Session = Depends(get_db)):
    """Fetch all categories, ordered by creation date."""
    try:
        categories = db.query(Category).order_by(Category.id).all()
        data = [CategoryResponse.model_validate(c).model_dump() for c in categories]
        return success_response("Categories fetched", data)
    except Exception as e:
        return error_response(f"Failed to fetch categories: {str(e)}")


@router.post("/")
def create_category(payload: CategoryCreate, db: Session = Depends(get_db)):
    """Create a new Qurbani category."""
    try:
        category = Category(
            title=payload.title,
            subtitle=payload.subtitle,
            amount=payload.amount,
            hissah_per_token=payload.hissah_per_token,
        )
        db.add(category)
        safe_commit(db, "Failed to create category")
        db.refresh(category)
        data = CategoryResponse.model_validate(category).model_dump()
        return success_response("Category created", data)
    except Exception as e:
        return error_response(f"Failed to create category: {str(e)}")


@router.put("/{category_id}/")
def update_category(category_id: int, payload: CategoryUpdate, db: Session = Depends(get_db)):
    """Update an existing category. Only provided fields are updated."""
    try:
        category = get_or_404(db, Category, category_id, "Category")

        # Smart partial update — only change fields that were actually sent
        update_data = payload.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            setattr(category, key, value)

        safe_commit(db, "Failed to update category")
        db.refresh(category)
        data = CategoryResponse.model_validate(category).model_dump()
        return success_response("Category updated", data)
    except Exception as e:
        return error_response(f"Failed to update category: {str(e)}")


@router.delete("/{category_id}/")
def delete_category(category_id: int, db: Session = Depends(get_db)):
    """Delete a category by ID."""
    try:
        category = get_or_404(db, Category, category_id, "Category")
        db.delete(category)
        safe_commit(db, "Failed to delete category")
        return success_response(f"Category '{category.title}' deleted")
    except Exception as e:
        return error_response(f"Failed to delete category: {str(e)}")
