"""
SQLAlchemy ORM models — the actual database table definitions.
Each class = one table.
"""
from sqlalchemy import Column, Integer, String, Float, Text, DateTime, Boolean, ForeignKey
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
from database import Base


class Category(Base):
    __tablename__ = "categories"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    title = Column(String(100), nullable=False)
    subtitle = Column(String(200), default="")
    amount = Column(Float, nullable=False, default=0.0)
    hissah_per_token = Column(Integer, nullable=False, default=7)  # Cow=7, Goat=1, etc.
    created_at = Column(DateTime(timezone=True), server_default=func.now())


class FormSettingsRow(Base):
    """
    Singleton row (id=1) storing all admin form settings as a JSON blob.
    This avoids 10+ tiny tables for toggles, lists, and nested config.
    """
    __tablename__ = "form_settings"

    id = Column(Integer, primary_key=True, default=1)
    settings_json = Column(Text, nullable=False, default="{}")
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class Booking(Base):
    __tablename__ = "bookings"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    receipt_no = Column(String(50), unique=True, nullable=False)
    category_title = Column(String(100), nullable=False)
    amount_per_hissah = Column(Float, nullable=False)
    purpose = Column(String(50), default="Qurbani")
    representative_name = Column(String(200), default="")
    owner_names = Column(Text, default="[]")           # JSON array
    hissah_count = Column(Integer, nullable=False, default=1)
    total_amount = Column(Float, nullable=False, default=0.0)
    address = Column(Text, default="")
    mobile = Column(String(20), default="")
    reference = Column(String(200), default="")
    custom_fields_data = Column(Text, default="{}")    # JSON object

    # Future fields — columns exist but not used in API yet
    payment_status = Column(String(20), default="unpaid")    # unpaid / paid / partial
    booking_status = Column(String(20), default="confirmed") # confirmed / cancelled

    created_at = Column(DateTime(timezone=True), server_default=func.now())


class Token(Base):
    """
    Represents one animal (jaanwar).
    Each token has a fixed number of slots (hissah_per_token from category).
    System fills partial tokens before creating new ones.
    """
    __tablename__ = "tokens"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    token_no = Column(Integer, nullable=False)              # Sequential: 1, 2, 3...
    category_title = Column(String(100), nullable=False)    # Which category this token belongs to
    max_slots = Column(Integer, nullable=False, default=7)  # Total hissah capacity
    filled_slots = Column(Integer, nullable=False, default=0)  # How many are filled so far
    status = Column(String(20), default="partial")          # "partial" or "full"
    qurbani_done = Column(Boolean, default=False)            # Has qurbani been performed?
    qurbani_done_at = Column(DateTime(timezone=True), nullable=True)  # When was qurbani done?
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationship to entries
    entries = relationship("TokenEntry", back_populates="token", cascade="all, delete-orphan")


class TokenEntry(Base):
    """
    Each individual name (hissah) assigned to a token.
    serial_no = position within the token (1 to max_slots).
    """
    __tablename__ = "token_entries"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    token_id = Column(Integer, ForeignKey("tokens.id"), nullable=False)
    serial_no = Column(Integer, nullable=False)             # 1, 2, 3... up to max_slots
    owner_name = Column(String(200), nullable=False)
    booking_id = Column(Integer, ForeignKey("bookings.id"), nullable=True)
    purpose = Column(String(50), default="Qurbani")
    created_at = Column(DateTime(timezone=True), server_default=func.now())

    # Relationship back to token
    token = relationship("Token", back_populates="entries")
    booking = relationship("Booking")
    
    @property
    def booking_reference(self):
        return self.booking.reference if self.booking else None
        
    @property
    def booking_date(self):
        return self.booking.created_at if self.booking else None
