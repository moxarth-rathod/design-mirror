"""
DesignMirror AI — V1 Router Aggregator
========================================

This file collects all v1 routers into a single APIRouter.
Adding a new feature is as simple as:
  1. Create a new router file (e.g., rooms.py)
  2. Import and include it here

PATTERN: Composite Router
─────────────────────────
Instead of registering every router in main.py (which gets messy),
we compose them here. main.py only sees ONE router: `v1_router`.
"""

from fastapi import APIRouter

from app.api.v1.auth import router as auth_router
from app.api.v1.health import router as health_router
from app.api.v1.rooms import router as rooms_router
from app.api.v1.catalog import router as catalog_router
from app.api.v1.fitcheck import router as fitcheck_router
from app.api.v1.wishlist import router as wishlist_router

v1_router = APIRouter(prefix="/api/v1")

v1_router.include_router(auth_router)
v1_router.include_router(health_router)
v1_router.include_router(rooms_router)
v1_router.include_router(catalog_router)
v1_router.include_router(fitcheck_router)
v1_router.include_router(wishlist_router)

