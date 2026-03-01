"""
DesignMirror AI — Product Document Model (Beanie ODM)
======================================================

Represents a furniture product in the catalog.

MENTOR MOMENT: 3D Bounding Boxes
─────────────────────────────────
Every piece of furniture has a 3D bounding box — the smallest rectangular
box that completely encloses the object. Think of it as the cardboard box
the furniture would ship in.

    ┌───────────────────┐
    │                   │  height
    │   ┌───────────┐   │    ↕
    │   │   SOFA    │   │
    │   └───────────┘   │
    │        width       │
    └───────────────────┘
           depth

The bounding box is defined by three measurements: width, depth, height.
The Fit-Check algorithm uses this box to determine if the furniture
physically fits in the room without overlapping walls or other furniture.

WHY store dimensions in meters?
──────────────────────────────
We store everything in meters (our canonical unit) and convert to
feet/inches on demand using the Unit Safety module. This prevents
the "mixed units" bugs that have crashed real engineering projects.
"""

from datetime import datetime, timezone
from typing import Optional

from beanie import Document, Indexed
from pydantic import BaseModel, Field


class BoundingBox3D(BaseModel):
    """
    3D bounding box dimensions in meters.

    These are the OUTER dimensions of the furniture — the smallest
    rectangular box that completely contains the object.
    """
    width_m: float = Field(..., gt=0, description="Width in meters (X axis)")
    depth_m: float = Field(..., gt=0, description="Depth in meters (Z axis)")
    height_m: float = Field(..., gt=0, description="Height in meters (Y axis)")

    @property
    def volume_m3(self) -> float:
        """Volume of the bounding box in cubic meters."""
        return self.width_m * self.depth_m * self.height_m

    @property
    def footprint_m2(self) -> float:
        """Floor footprint area in square meters."""
        return self.width_m * self.depth_m


class Product(Document):
    """
    Represents a furniture product in the DesignMirror catalog.

    Maps to the 'products' collection in MongoDB.
    """

    # ── Product Info ───────────────────────────
    name: Indexed(str)  # type: ignore[valid-type]
    """Product name, indexed for search."""

    category: Indexed(str)  # type: ignore[valid-type]
    """
    Furniture category. Indexed for filtering.
    Examples: "sofa", "table", "chair", "lighting", "storage", "bed", "rug"
    """

    description: str = Field(default="")
    """Optional product description."""

    # ── Dimensions ─────────────────────────────
    bounding_box: BoundingBox3D
    """
    3D bounding box of the furniture in meters.
    This is the key data used by the Fit-Check collision algorithm.
    """

    # ── Visual / Commerce ──────────────────────
    color: str = Field(default="")
    price_usd: float = Field(..., ge=0)
    image_url: Optional[str] = Field(default=None)
    model_file: Optional[str] = Field(
        default=None,
        description="Filename of the 3D model in MinIO (.glb or .usdz)",
    )

    # ── Metadata ───────────────────────────────
    tags: list[str] = Field(default_factory=list)
    """Searchable tags: ["modern", "mid-century", "small-space"]"""

    is_active: bool = Field(default=True)
    """Inactive products are hidden from catalog searches."""

    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: Optional[datetime] = Field(default=None)

    # ── Beanie Settings ────────────────────────
    class Settings:
        name = "products"

    def to_response_dict(self) -> dict:
        """Convert to a dict suitable for API responses."""
        return {
            "id": str(self.id),
            "name": self.name,
            "category": self.category,
            "description": self.description,
            "bounding_box": self.bounding_box.model_dump(),
            "color": self.color,
            "price_usd": self.price_usd,
            "image_url": self.image_url,
            "model_file": self.model_file,
            "tags": self.tags,
        }
