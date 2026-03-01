"""
DesignMirror AI — Wishlist Model
=================================
Tracks products a user has bookmarked for later review.
"""

from datetime import datetime, timezone
from typing import Optional

from beanie import Document, Indexed
from pydantic import Field
from beanie import PydanticObjectId


class WishlistItem(Document):
    user_id: Indexed(str)  # type: ignore[valid-type]
    product_id: Indexed(str)  # type: ignore[valid-type]
    note: Optional[str] = None
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Settings:
        name = "wishlist"
        indexes = [
            [("user_id", 1), ("product_id", 1)],
        ]
