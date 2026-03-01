"""
DesignMirror AI — Product & Catalog Schemas (Pydantic)
=======================================================

Request/response schemas for the product catalog endpoints.

PUBLIC DATA: Unlike room scans, the product catalog is public.
Any user (even unauthenticated) can browse furniture.
Only admin operations (create/update/delete) require auth.
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field


# ── Nested Schemas ────────────────────────────────────────────────────────────

class BoundingBox3DSchema(BaseModel):
    """3D bounding box dimensions in meters."""
    width_m: float = Field(..., gt=0)
    depth_m: float = Field(..., gt=0)
    height_m: float = Field(..., gt=0)


# ── Request Schemas ───────────────────────────────────────────────────────────

class ProductCreateRequest(BaseModel):
    """Schema for creating a new product."""
    name: str = Field(..., min_length=1, max_length=200)
    category: str = Field(..., min_length=1, max_length=50)
    description: str = Field(default="", max_length=1000)
    bounding_box: BoundingBox3DSchema
    color: str = Field(default="", max_length=50)
    price_usd: float = Field(..., ge=0)
    image_url: Optional[str] = None
    model_file: Optional[str] = None
    tags: list[str] = Field(default_factory=list)


class ProductUpdateRequest(BaseModel):
    """Schema for updating a product. All fields optional."""
    name: Optional[str] = Field(default=None, min_length=1, max_length=200)
    category: Optional[str] = Field(default=None, min_length=1, max_length=50)
    description: Optional[str] = Field(default=None, max_length=1000)
    bounding_box: Optional[BoundingBox3DSchema] = None
    color: Optional[str] = None
    price_usd: Optional[float] = Field(default=None, ge=0)
    image_url: Optional[str] = None
    model_file: Optional[str] = None
    tags: Optional[list[str]] = None


# ── Response Schemas ──────────────────────────────────────────────────────────

class ProductResponse(BaseModel):
    """Product data returned to the client."""
    id: str
    name: str
    category: str
    description: str
    bounding_box: BoundingBox3DSchema
    color: str
    price_usd: float
    image_url: Optional[str] = None
    model_file: Optional[str] = None
    tags: list[str]


class CatalogPageResponse(BaseModel):
    """
    Paginated catalog response.

    MENTOR MOMENT: Why pagination?
    ─────────────────────────────
    If the catalog has 10,000 products and the Flutter app requests ALL
    of them at once, it would:
      1. Take forever to download
      2. Use massive memory on the phone
      3. Overload the backend and MongoDB

    Instead, we return 20 items at a time (a "page"). The app requests
    page 1, then page 2 as the user scrolls. This is "cursor-based"
    pagination — fast even with millions of records.
    """
    items: list[ProductResponse]
    total: int
    page: int
    page_size: int
    has_next: bool


class CatalogFilterParams(BaseModel):
    """Query parameters for filtering and searching the catalog."""
    category: Optional[str] = None
    search: Optional[str] = None
    min_price: Optional[float] = Field(default=None, ge=0)
    max_price: Optional[float] = Field(default=None, ge=0)
    tags: Optional[list[str]] = None
    max_width_m: Optional[float] = Field(default=None, ge=0)
    max_depth_m: Optional[float] = Field(default=None, ge=0)
    max_height_m: Optional[float] = Field(default=None, ge=0)
    page: int = Field(default=1, ge=1)
    page_size: int = Field(default=20, ge=1, le=100)
