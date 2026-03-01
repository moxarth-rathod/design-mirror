"""
DesignMirror AI — Room Style Recommendation Engine
====================================================

Suggests curated furniture sets based on room type and dimensions.

The engine maps room types to relevant furniture categories, then
queries products that physically fit in the room, grouped by category
and sorted by design relevance.
"""

from __future__ import annotations

from app.core.logging import logger
from app.models.product import Product

# Room type → ordered list of furniture categories that belong in that room.
# The order reflects typical importance / shopping priority.
ROOM_CATEGORY_MAP: dict[str, list[str]] = {
    "bedroom": ["bed", "nightstand", "dresser", "wardrobe", "storage", "rug", "lighting", "mirror", "decor"],
    "living_room": ["sofa", "table", "rug", "lighting", "storage", "decor", "plant", "mirror"],
    "dining_room": ["table", "chair", "storage", "lighting", "rug", "decor"],
    "office": ["desk", "chair", "storage", "lighting", "decor", "plant"],
    "kitchen": ["table", "chair", "storage", "lighting"],
    "bathroom": ["storage", "mirror", "decor"],
    "kids_room": ["bed", "desk", "chair", "storage", "rug", "lighting", "decor"],
    "guest_room": ["bed", "nightstand", "dresser", "rug", "lighting", "mirror"],
    "other": ["table", "chair", "storage", "lighting", "rug", "decor"],
}

MAX_PER_CATEGORY = 3


async def get_recommendations(
    room_type: str,
    room_width: float,
    room_length: float,
    room_height: float | None = None,
) -> list[dict]:
    """
    Return recommended products grouped by category for the given room type.

    Each group: { "category": str, "products": [...] }
    Products are filtered to physically fit in the room and sorted by price.
    """
    categories = ROOM_CATEGORY_MAP.get(room_type, ROOM_CATEGORY_MAP["other"])

    logger.info(
        "Generating recommendations for {} ({}×{}m) — categories: {}",
        room_type, room_width, room_length, categories,
    )

    groups: list[dict] = []

    for cat in categories:
        filters = {
            "category": cat,
            "is_active": True,
            "bounding_box.width_m": {"$lte": room_width},
            "bounding_box.depth_m": {"$lte": room_length},
        }
        if room_height:
            filters["bounding_box.height_m"] = {"$lte": room_height}

        products = (
            await Product.find(filters)
            .sort("+price_usd")
            .limit(MAX_PER_CATEGORY)
            .to_list()
        )

        if not products:
            continue

        groups.append({
            "category": cat,
            "products": [
                {
                    "id": str(p.id),
                    "name": p.name,
                    "category": p.category,
                    "price_usd": p.price_usd,
                    "image_url": p.image_url,
                    "bounding_box": {
                        "width_m": p.bounding_box.width_m,
                        "depth_m": p.bounding_box.depth_m,
                        "height_m": p.bounding_box.height_m,
                    },
                    "tags": p.tags,
                }
                for p in products
            ],
        })

    logger.info("Recommendations: {} categories with results", len(groups))
    return groups
