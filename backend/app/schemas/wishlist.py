"""
DesignMirror AI — Wishlist Schemas
"""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class WishlistAddRequest(BaseModel):
    product_id: str
    note: Optional[str] = None


class WishlistItemResponse(BaseModel):
    id: str
    product_id: str
    product_name: str
    product_category: str
    product_image_url: Optional[str] = None
    product_price_usd: float
    note: Optional[str] = None
    created_at: datetime
