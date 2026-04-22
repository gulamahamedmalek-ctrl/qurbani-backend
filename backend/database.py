"""
Database connection & session management.
Single source of truth for all DB operations.

Production: PostgreSQL on Neon.tech (cloud)
Development: Can fall back to SQLite locally if needed.

Concurrency Safety:
  - PostgreSQL handles concurrent reads/writes natively
  - A global threading.Lock serializes WRITE operations as extra safety
"""
import os
import threading
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base

# ── DATABASE URL ──
# Production: Neon.tech PostgreSQL (set via environment variable or hardcoded)
# To use local SQLite for development, set DATABASE_URL=sqlite:///./qurbani.db
DATABASE_URL = os.environ.get(
    "DATABASE_URL",
    "postgresql://neondb_owner:npg_SH8hznjbs5Uf@ep-still-mode-aopn755a-pooler.c-2.ap-southeast-1.aws.neon.tech/qurbani_db?sslmode=require"
)

# ── Global write lock — extra concurrency guard ──
booking_lock = threading.Lock()

# ── Engine configuration ──
# PostgreSQL doesn't need check_same_thread (that's SQLite-only)
connect_args = {}
if DATABASE_URL.startswith("sqlite"):
    connect_args = {"check_same_thread": False}

engine = create_engine(
    DATABASE_URL,
    connect_args=connect_args,
    echo=False,
    pool_pre_ping=True,          # Auto-reconnect if connection drops
    pool_size=5,                 # Keep 5 connections ready
    max_overflow=10,             # Allow up to 10 extra during peak
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()


def get_db():
    """
    Reusable DB session dependency.
    Yields a session and guarantees cleanup via finally block.
    Import this in ANY router that needs DB access.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    """Create all tables on startup. Safe to call multiple times."""
    Base.metadata.create_all(bind=engine)
