"""
Qurbani Hissah Management System — FastAPI Backend
================================================
Entry point. Registers all routers and initializes the database.

Run with:
    uvicorn main:app --reload --host 0.0.0.0 --port 8000

Then open:
    http://localhost:8000/docs   → Swagger UI (visual API tester)
    http://localhost:8000/redoc  → Alternative docs
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from database import init_db
from routers import categories, settings, bookings, tokens

app = FastAPI(
    title="Qurbani Hissah API",
    description="Backend API for Qurbani Hissah Management System",
    version="1.0.0",
)

# ── CORS — Allow Flutter app (web/mobile) to talk to the server ──
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],           # Allow all origins (tighten in production)
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
