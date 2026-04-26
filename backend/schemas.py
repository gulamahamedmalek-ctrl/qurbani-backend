"""
Pydantic schemas — request/response validation.
FastAPI uses these to auto-validate incoming data before it touches the DB.
"""
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime


# ═══════════════════════════════════════════════
# Category Schemas
# ═══════════════════════════════════════════════
class CategoryCreate(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    subtitle: str = Field(default="", max_length=200)
    amount: float = Field(..., ge=0)
    hissah_per_token: int = Field(default=7, ge=1, le=20)


class CategoryUpdate(BaseModel):
    title: Optional[str] = Field(None, min_length=1, max_length=100)
    subtitle: Optional[str] = Field(None, max_length=200)
    amount: Optional[float] = Field(None, ge=0)
    hissah_per_token: Optional[int] = Field(None, ge=1, le=20)


class CategorySync(BaseModel):
    categories: List[CategoryCreate]


class CategoryResponse(BaseModel):
    id: int
    title: str
    subtitle: str
    amount: float
    hissah_per_token: int
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


# ═══════════════════════════════════════════════
# Form Settings Schemas
# ═══════════════════════════════════════════════
class CustomFieldSchema(BaseModel):
    id: str
    label: str
    fieldType: str = "text"
    isRequired: bool = False
    dropdownOptions: List[str] = []


class FormSettingsSchema(BaseModel):
    purposes: List[str] = ["Qurbani", "Aqiqah"]
    maxHissahLimit: int = Field(default=7, ge=1, le=20)
    showRepresentativeName: bool = True
    showAddress: bool = True
    showMobileNumber: bool = True
    showReference: bool = True
    referenceAsDropdown: bool = False
    referenceOptions: List[str] = ["Friend", "Social Media", "Masjid Announcement", "Other"]
    customFields: List[CustomFieldSchema] = []
    organizationName: str = "Qurbani Management"
    receiptPrefix: str = "RCPT-"
    startingReceiptNumber: int = 1
    currencySymbol: str = "₹"
    logoBase64: str = ""


# ═══════════════════════════════════════════════
# Booking Schemas
# ═══════════════════════════════════════════════
class BookingCreate(BaseModel):
    category_title: str
    amount_per_hissah: float = Field(..., ge=0)
    purpose: str = "Qurbani"
    representative_name: str = ""
    owner_names: List[str] = []
    hissah_count: int = Field(..., ge=1)
    total_amount: float = Field(..., ge=0)
    address: str = ""
    mobile: str = ""
    reference: str = ""
    custom_fields_data: Dict[str, Any] = {}


class BookingResponse(BaseModel):
    id: int
    receipt_no: str
    category_title: str
    amount_per_hissah: float
    purpose: str
    representative_name: str
    owner_names: str          # JSON string from DB
    hissah_count: int
    total_amount: float
    address: str
    mobile: str
    reference: str
    custom_fields_data: str   # JSON string from DB
    payment_status: str
    booking_status: str
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


# ═══════════════════════════════════════════════
# Token Schemas
# ═══════════════════════════════════════════════
class TokenEntryResponse(BaseModel):
    id: int
    serial_no: int
    owner_name: str
    booking_id: Optional[int] = None
    purpose: str
    booking_reference: Optional[str] = None
    booking_date: Optional[datetime] = None
    booking_category: Optional[str] = None
    receipt_no: Optional[str] = None
    representative_name: Optional[str] = None
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


class TokenResponse(BaseModel):
    id: int
    token_no: int
    category_title: str
    max_slots: int
    filled_slots: int
    status: str
    qurbani_done: bool = False
    qurbani_done_at: Optional[datetime] = None
    entries: List[TokenEntryResponse] = []
    created_at: Optional[datetime] = None

    class Config:
        from_attributes = True


# ═══════════════════════════════════════════════
# Unified API Response Wrapper
# ═══════════════════════════════════════════════
class APIResponse(BaseModel):
    """
    Every single API response uses this wrapper.
    Reusable across ALL routers — never write response formatting twice.
    """
    success: bool
    message: str
    data: Any = None
