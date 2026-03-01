"""
DesignMirror AI — FastAPI Application Entry Point
===================================================

This is where everything comes together. Think of it as the "main()" of a
Python script, but for a web server.

STARTUP FLOW:
  1. Configure logging (Loguru)
  2. Create the FastAPI app with metadata
  3. Register exception handlers (custom error responses)
  4. Add middleware (CORS, rate limiting)
  5. Include API routers
  6. On startup: connect to MongoDB
  7. On shutdown: close MongoDB connection
  8. Uvicorn serves the app

MENTOR MOMENT: What is a "Lifespan"?
────────────────────────────────────
In older FastAPI, you'd use @app.on_event("startup") and "shutdown".
The modern way is `lifespan` — an async context manager that runs setup
code BEFORE the app starts and cleanup code AFTER it stops.

    async with lifespan(app):
        # ↑ startup code runs here (connect to DB)
        yield
        # ↓ shutdown code runs here (close DB connection)
"""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.middleware import SlowAPIMiddleware

from app.config import settings
from app.core.logging import logger, setup_logging
from app.core.exceptions import register_exception_handlers
from app.database import connect_to_mongodb, close_mongodb_connection
from app.api.v1.router import v1_router


# ── Configure Logging ─────────────────────────────────────────────────────────
setup_logging(app_env=settings.APP_ENV)


# ── Lifespan (Startup / Shutdown) ─────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Manage application lifecycle events.

    STARTUP:  Connect to MongoDB (opens connection pool)
    SHUTDOWN: Close MongoDB connection (releases resources)
    """
    logger.info("🚀 Starting {} ({})", settings.APP_NAME, settings.APP_ENV)

    # ── Startup ──────────────────────────────
    await connect_to_mongodb()

    yield  # App is running and serving requests here

    # ── Shutdown ─────────────────────────────
    await close_mongodb_connection()
    logger.info("👋 {} shut down gracefully.", settings.APP_NAME)


# ── Create FastAPI App ────────────────────────────────────────────────────────

app = FastAPI(
    title=settings.APP_NAME,
    description=(
        "AI-powered interior design assistant with AR room scanning, "
        "furniture fit-checking, and real-time staging."
    ),
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.DEBUG else None,      # Swagger UI (dev only)
    redoc_url="/redoc" if settings.DEBUG else None,     # ReDoc (dev only)
)


# ── Middleware ─────────────────────────────────────────────────────────────────

# CORS — Cross-Origin Resource Sharing
# In development, we allow all origins so the Flutter app can talk to the API.
# In production, restrict this to your actual domain(s).
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if settings.DEBUG else ["https://yourdomain.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rate Limiting
# Protects auth endpoints from brute-force attacks.
# Default: 100 requests/minute per IP address.
limiter = Limiter(key_func=get_remote_address, default_limits=["100/minute"])
app.state.limiter = limiter
app.add_middleware(SlowAPIMiddleware)


# ── Exception Handlers ────────────────────────────────────────────────────────
register_exception_handlers(app)


# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(v1_router)


# ── Root Endpoint ─────────────────────────────────────────────────────────────

@app.get("/", tags=["Root"])
async def root():
    """Root endpoint — confirms the API is running."""
    return {
        "service": settings.APP_NAME,
        "version": "0.1.0",
        "docs": "/docs" if settings.DEBUG else "disabled",
    }

