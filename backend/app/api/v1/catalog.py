"""
DesignMirror AI — Catalog Router
==================================

Endpoints for browsing and managing the furniture catalog.

PUBLIC endpoints (no auth required):
  GET  /api/v1/catalog              → Browse catalog (paginated, filtered, cached)
  GET  /api/v1/catalog/categories   → List all categories
  GET  /api/v1/catalog/{product_id} → Get product details

ADMIN endpoints (auth required):
  POST   /api/v1/catalog            → Create a new product
  PUT    /api/v1/catalog/{product_id} → Update a product
  DELETE /api/v1/catalog/{product_id} → Soft-delete a product
"""

from typing import Optional

from fastapi import APIRouter, Depends, Query, status

from app.dependencies import get_current_user
from app.models.user import User
from app.schemas.product import (
    CatalogPageResponse,
    ProductCreateRequest,
    ProductResponse,
    ProductUpdateRequest,
)
from app.services import catalog_service

router = APIRouter(prefix="/catalog", tags=["Catalog"])


# ── PUBLIC ENDPOINTS ──────────────────────────────────────────────────────────


@router.get(
    "",
    response_model=CatalogPageResponse,
    summary="Browse the furniture catalog",
    responses={
        200: {"description": "Paginated catalog results (served from cache when available)"},
    },
)
async def browse_catalog(
    category: Optional[str] = Query(default=None, description="Filter by category"),
    search: Optional[str] = Query(default=None, description="Search by name/description"),
    min_price: Optional[float] = Query(default=None, ge=0, description="Minimum price USD"),
    max_price: Optional[float] = Query(default=None, ge=0, description="Maximum price USD"),
    tags: Optional[str] = Query(default=None, description="Comma-separated tags"),
    max_width_m: Optional[float] = Query(default=None, ge=0, description="Max bounding box width (m) - filter furniture that fits"),
    max_depth_m: Optional[float] = Query(default=None, ge=0, description="Max bounding box depth (m) - filter furniture that fits"),
    max_height_m: Optional[float] = Query(default=None, ge=0, description="Max bounding box height (m) - filter furniture that fits"),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
) -> CatalogPageResponse:
    """
    Browse the furniture catalog with optional filters.

    Results are **cached in Redis** for 5 minutes — so repeated requests
    are served in sub-millisecond time without hitting MongoDB.

    **Examples:**
    - `/catalog` — all products, page 1
    - `/catalog?category=sofa` — only sofas
    - `/catalog?search=modern&min_price=100&max_price=500` — search + price range
    - `/catalog?tags=modern,small-space` — filter by tags
    - `/catalog?max_width_m=2&max_depth_m=1.5&max_height_m=1` — furniture that fits in room
    - `/catalog?page=2&page_size=10` — page 2 with 10 items per page
    """
    tag_list = [t.strip() for t in tags.split(",")] if tags else None

    return await catalog_service.get_catalog(
        category=category,
        search=search,
        min_price=min_price,
        max_price=max_price,
        tags=tag_list,
        max_width_m=max_width_m,
        max_depth_m=max_depth_m,
        max_height_m=max_height_m,
        page=page,
        page_size=page_size,
    )


@router.get(
    "/budget-picks",
    summary="Get furniture that fits a room within a budget",
)
async def budget_picks(
    room_id: str = Query(..., description="Room ID to check dimensions against"),
    budget_inr: float = Query(..., gt=0, description="Total budget in INR"),
    current_user: User = Depends(get_current_user),
):
    from app.models.room import Room
    from app.models.product import Product

    room = await Room.get(room_id)
    if not room or not room.dimensions:
        return {"items": [], "total_inr": 0, "budget_inr": budget_inr}

    room_w = room.dimensions.get("width_m", 99)
    room_l = room.dimensions.get("length_m", 99)
    room_h = room.dimensions.get("height_m", 99)

    usd_to_inr = 83.5
    max_usd = budget_inr / usd_to_inr

    products = await Product.find(
        {"is_active": True, "price_usd": {"$lte": max_usd}},
    ).sort("price_usd").to_list()

    picks = []
    for p in products:
        if (
            p.bounding_box.width_m <= room_w
            and p.bounding_box.depth_m <= room_l
            and p.bounding_box.height_m <= room_h
        ):
            picks.append({
                "id": str(p.id),
                "name": p.name,
                "category": p.category,
                "price_usd": p.price_usd,
                "price_inr": round(p.price_usd * usd_to_inr),
                "image_url": p.image_url,
                "dimensions": f"{p.bounding_box.width_m}m × {p.bounding_box.depth_m}m × {p.bounding_box.height_m}m",
            })

    # Sort by category variety then price
    seen_cats = set()
    diverse = []
    rest = []
    for p in picks:
        if p["category"] not in seen_cats:
            seen_cats.add(p["category"])
            diverse.append(p)
        else:
            rest.append(p)
    ordered = diverse + rest

    # Only include items until cumulative total exceeds budget
    capped = []
    running = 0
    for p in ordered:
        if running + p["price_inr"] <= budget_inr:
            capped.append(p)
            running += p["price_inr"]

    return {
        "items": capped,
        "count": len(capped),
        "total_inr": running,
        "budget_inr": budget_inr,
    }


@router.get(
    "/recommendations",
    summary="Get style-based furniture recommendations for a room",
)
async def recommendations(
    room_id: str = Query(..., description="Room ID"),
    current_user: User = Depends(get_current_user),
):
    """
    Return curated furniture recommendations grouped by category
    based on room type and dimensions.
    """
    from app.models.room import Room
    from app.services.recommendation_service import get_recommendations

    room = await Room.get(room_id)
    if not room or not room.dimensions:
        return {"room_type": None, "groups": []}

    room_type = room.room_type or "other"
    room_w = room.dimensions.get("width_m", 99)
    room_l = room.dimensions.get("length_m", 99)
    room_h = room.dimensions.get("height_m")

    groups = await get_recommendations(room_type, room_w, room_l, room_h)

    return {
        "room_id": str(room.id),
        "room_type": room_type,
        "room_name": room.room_name,
        "groups": groups,
    }


@router.get(
    "/categories",
    response_model=list[str],
    summary="List all product categories",
)
async def list_categories() -> list[str]:
    """Get all unique product categories (e.g., ["sofa", "table", "chair"])."""
    return await catalog_service.get_categories()


@router.get(
    "/{product_id}",
    response_model=ProductResponse,
    summary="Get product details",
    responses={404: {"description": "Product not found"}},
)
async def get_product(product_id: str) -> ProductResponse:
    """Get detailed information about a specific product."""
    return await catalog_service.get_product_by_id(product_id)


# ── ADMIN ENDPOINTS (Auth Required) ──────────────────────────────────────────


@router.post(
    "",
    response_model=ProductResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a new product (admin)",
)
async def create_product(
    data: ProductCreateRequest,
    current_user: User = Depends(get_current_user),
) -> ProductResponse:
    """
    Add a new furniture product to the catalog.

    Requires authentication. Automatically invalidates the Redis cache
    so new products appear immediately.
    """
    return await catalog_service.create_product(data)


@router.put(
    "/{product_id}",
    response_model=ProductResponse,
    summary="Update a product (admin)",
    responses={404: {"description": "Product not found"}},
)
async def update_product(
    product_id: str,
    data: ProductUpdateRequest,
    current_user: User = Depends(get_current_user),
) -> ProductResponse:
    """Update an existing product. Only provided fields are changed."""
    return await catalog_service.update_product(product_id, data)


@router.delete(
    "/{product_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a product (admin)",
    responses={404: {"description": "Product not found"}},
)
async def delete_product(
    product_id: str,
    current_user: User = Depends(get_current_user),
) -> None:
    """Soft-delete a product (marks it inactive, doesn't destroy data)."""
    await catalog_service.delete_product(product_id)
