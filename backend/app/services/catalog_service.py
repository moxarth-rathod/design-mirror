"""
DesignMirror AI — Catalog Service (with Redis Caching)
=======================================================

Business logic for the product catalog with a Redis caching layer.

MENTOR MOMENT: Why Cache the Catalog?
────────────────────────────────────
Without caching, every time a user opens the catalog:
  1. Flutter sends GET /api/v1/catalog
  2. FastAPI queries MongoDB
  3. MongoDB scans the products collection
  4. Results travel back through the network

With 1,000 users browsing simultaneously, that's 1,000 identical MongoDB
queries per second — wasteful since the catalog rarely changes.

PATTERN: Cache-Aside (Lazy Loading)
───────────────────────────────────
  1. Check Redis for cached data → HIT? Return it instantly.
  2. MISS? Query MongoDB, store the result in Redis with a TTL (Time To Live).
  3. Next request hits the cache — no MongoDB query needed.
  4. When a product is created/updated/deleted, invalidate the cache.

TTL (Time To Live) = 5 minutes. This means:
  • 99% of catalog requests are served from Redis (sub-millisecond)
  • New products appear within 5 minutes (or instantly if we invalidate)
  • No stale data forever — the cache auto-expires

This is the same pattern Amazon uses for their product catalog pages.
"""

import json
from datetime import datetime, timezone
from typing import Optional

from beanie import PydanticObjectId
from redis.asyncio import Redis

from app.config import settings
from app.core.exceptions import NotFoundError
from app.core.logging import logger
from app.models.product import BoundingBox3D, Product
from app.schemas.product import (
    CatalogPageResponse,
    ProductCreateRequest,
    ProductResponse,
    ProductUpdateRequest,
)

# ── Redis Configuration ───────────────────────────────────────────────────────

CACHE_TTL_SECONDS = 300  # 5 minutes
CACHE_KEY_PREFIX = "catalog:"


def _cache_key(params: dict) -> str:
    """Generate a deterministic cache key from query parameters."""
    sorted_params = sorted(params.items())
    return f"{CACHE_KEY_PREFIX}{hash(tuple(sorted_params))}"


async def _get_redis() -> Redis:
    """Create an async Redis connection."""
    return Redis.from_url(settings.REDIS_URL, decode_responses=True)


async def _invalidate_catalog_cache() -> None:
    """
    Clear ALL catalog cache entries.

    Called whenever a product is created, updated, or deleted.
    We clear the entire catalog cache (not just one key) because
    a product change could affect any filtered/paginated view.
    """
    try:
        redis = await _get_redis()
        # Find and delete all catalog cache keys
        cursor = 0
        while True:
            cursor, keys = await redis.scan(cursor, match=f"{CACHE_KEY_PREFIX}*", count=100)
            if keys:
                await redis.delete(*keys)
            if cursor == 0:
                break
        await redis.aclose()
        logger.debug("Catalog cache invalidated")
    except Exception as e:
        logger.warning("Failed to invalidate cache: {}", str(e))


# ── Catalog Query ─────────────────────────────────────────────────────────────

async def get_catalog(
    category: Optional[str] = None,
    search: Optional[str] = None,
    min_price: Optional[float] = None,
    max_price: Optional[float] = None,
    tags: Optional[list[str]] = None,
    max_width_m: Optional[float] = None,
    max_depth_m: Optional[float] = None,
    max_height_m: Optional[float] = None,
    page: int = 1,
    page_size: int = 20,
) -> CatalogPageResponse:
    """
    Get paginated, filtered product catalog with Redis caching.

    The cache key is derived from ALL query parameters, so different
    searches/filters get separate cache entries.
    """
    # Build cache key from parameters
    cache_params = {
        "category": category,
        "search": search,
        "min_price": min_price,
        "max_price": max_price,
        "tags": tuple(tags) if tags else None,
        "max_width_m": max_width_m,
        "max_depth_m": max_depth_m,
        "max_height_m": max_height_m,
        "page": page,
        "page_size": page_size,
    }
    cache_key = _cache_key(cache_params)

    # ── Step 1: Check Redis cache ──────────────
    try:
        redis = await _get_redis()
        cached = await redis.get(cache_key)
        if cached:
            logger.debug("Cache HIT for {}", cache_key)
            await redis.aclose()
            return CatalogPageResponse(**json.loads(cached))
        await redis.aclose()
    except Exception as e:
        logger.warning("Redis cache read failed: {}", str(e))

    logger.debug("Cache MISS for {} — querying MongoDB", cache_key)

    # ── Step 2: Build MongoDB query ────────────
    query_filters = {"is_active": True}

    if category:
        query_filters["category"] = category.lower()

    if min_price is not None:
        query_filters.setdefault("price_usd", {})["$gte"] = min_price

    if max_price is not None:
        query_filters.setdefault("price_usd", {})["$lte"] = max_price

    if tags:
        query_filters["tags"] = {"$all": [t.lower() for t in tags]}

    if max_width_m is not None:
        query_filters["bounding_box.width_m"] = {"$lte": max_width_m}

    if max_depth_m is not None:
        query_filters["bounding_box.depth_m"] = {"$lte": max_depth_m}

    if max_height_m is not None:
        query_filters["bounding_box.height_m"] = {"$lte": max_height_m}

    # Text search on name and description
    if search:
        query_filters["$or"] = [
            {"name": {"$regex": search, "$options": "i"}},
            {"description": {"$regex": search, "$options": "i"}},
        ]

    # ── Step 3: Execute query with pagination ──
    skip = (page - 1) * page_size

    total = await Product.find(query_filters).count()
    products = await Product.find(query_filters).skip(skip).limit(page_size).to_list()

    items = [ProductResponse(**p.to_response_dict()) for p in products]

    result = CatalogPageResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        has_next=(skip + page_size) < total,
    )

    # ── Step 4: Store in Redis cache ───────────
    try:
        redis = await _get_redis()
        await redis.setex(cache_key, CACHE_TTL_SECONDS, result.model_dump_json())
        await redis.aclose()
    except Exception as e:
        logger.warning("Redis cache write failed: {}", str(e))

    return result


# ── Product CRUD ──────────────────────────────────────────────────────────────

async def get_product_by_id(product_id: str) -> ProductResponse:
    """Get a single product by ID."""
    product = await Product.get(product_id)
    if not product or not product.is_active:
        raise NotFoundError(
            message=f"Product '{product_id}' not found",
            error_code="PRODUCT_NOT_FOUND",
        )
    return ProductResponse(**product.to_response_dict())


async def create_product(data: ProductCreateRequest) -> ProductResponse:
    """Create a new product and invalidate the catalog cache."""
    product = Product(
        name=data.name,
        category=data.category.lower(),
        description=data.description,
        bounding_box=BoundingBox3D(**data.bounding_box.model_dump()),
        color=data.color,
        price_usd=data.price_usd,
        image_url=data.image_url,
        model_file=data.model_file,
        tags=[t.lower() for t in data.tags],
    )
    await product.insert()
    await _invalidate_catalog_cache()

    logger.info("Product created: {} ({})", product.name, product.id)

    return ProductResponse(**product.to_response_dict())


async def update_product(
    product_id: str, data: ProductUpdateRequest
) -> ProductResponse:
    """Update a product and invalidate the catalog cache."""
    product = await Product.get(product_id)
    if not product:
        raise NotFoundError(
            message=f"Product '{product_id}' not found",
            error_code="PRODUCT_NOT_FOUND",
        )

    update_data = data.model_dump(exclude_unset=True)
    if "category" in update_data and update_data["category"]:
        update_data["category"] = update_data["category"].lower()
    if "tags" in update_data and update_data["tags"]:
        update_data["tags"] = [t.lower() for t in update_data["tags"]]
    if "bounding_box" in update_data and update_data["bounding_box"]:
        update_data["bounding_box"] = BoundingBox3D(**update_data["bounding_box"])

    update_data["updated_at"] = datetime.now(timezone.utc)

    await product.update({"$set": update_data})
    await _invalidate_catalog_cache()

    # Re-fetch to return updated data
    product = await Product.get(product_id)
    logger.info("Product updated: {} ({})", product.name, product_id)

    return ProductResponse(**product.to_response_dict())


async def delete_product(product_id: str) -> None:
    """Soft-delete a product (mark inactive) and invalidate cache."""
    product = await Product.get(product_id)
    if not product:
        raise NotFoundError(
            message=f"Product '{product_id}' not found",
            error_code="PRODUCT_NOT_FOUND",
        )

    product.is_active = False
    product.updated_at = datetime.now(timezone.utc)
    await product.save()
    await _invalidate_catalog_cache()

    logger.info("Product soft-deleted: {} ({})", product.name, product_id)


async def get_categories() -> list[str]:
    """Get all unique product categories. Cached separately."""
    cache_key = f"{CACHE_KEY_PREFIX}categories"
    try:
        redis = await _get_redis()
        cached = await redis.get(cache_key)
        if cached:
            await redis.aclose()
            return json.loads(cached)
        await redis.aclose()
    except Exception:
        pass

    # Beanie's find() doesn't have distinct(), so we use aggregate
    pipeline = [
        {"$match": {"is_active": True}},
        {"$group": {"_id": "$category"}},
        {"$sort": {"_id": 1}},
    ]
    results = await Product.aggregate(pipeline).to_list()
    categories = [r["_id"] for r in results if r["_id"]]

    try:
        redis = await _get_redis()
        await redis.setex(cache_key, CACHE_TTL_SECONDS, json.dumps(categories))
        await redis.aclose()
    except Exception:
        pass

    return categories
