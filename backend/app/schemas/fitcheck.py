"""
DesignMirror AI — Fit-Check Schemas (Pydantic)
================================================

Request/response schemas for the collision detection endpoint.

The Fit-Check answers the question:
  "Will this piece of furniture fit in this spot in my room?"

It checks:
  1. Does the furniture's bounding box overlap with any wall?
  2. Does it overlap with any other placed furniture?
  3. Is there enough clearance for doors/walkways?
"""

from typing import Any, Optional

from pydantic import BaseModel, Field


class PlacementPosition(BaseModel):
    """
    Where the user wants to place furniture in the room.

    Coordinates are in meters, relative to the room's coordinate system
    (same coordinate system used in the room scan).
    """
    x: float = Field(..., description="X position in meters (left-right)")
    y: float = Field(default=0.0, description="Y position in meters (up-down, usually 0 for floor)")
    z: float = Field(..., description="Z position in meters (front-back)")
    rotation_y: float = Field(
        default=0.0,
        ge=0,
        lt=360,
        description="Rotation around Y axis in degrees (0-360)",
    )


class FitCheckRequest(BaseModel):
    """
    Request to check if furniture fits at a specific position in a room.

    The client sends:
      • room_id — which room to check against
      • product_id — which furniture to place
      • position — (optional) where in the room to place it.
        If omitted, the AI placement engine picks the optimal spot.
    """
    room_id: str
    product_id: str
    position: Optional[PlacementPosition] = Field(
        default=None,
        description="Manual placement position. If omitted, AI picks the optimal spot.",
    )


class CollisionDetail(BaseModel):
    """Details about a detected collision."""
    type: str = Field(
        ...,
        description="What it collides with: 'wall', 'furniture', 'boundary'",
    )
    description: str
    overlap_m: Optional[float] = Field(
        default=None,
        description="How far into the obstruction (meters)",
    )


class DesignWarning(BaseModel):
    """A non-blocking design concern (furniture fits but layout is poor)."""
    severity: str = Field(
        ..., description="'caution' or 'warning' — caution is mild, warning is serious"
    )
    category: str = Field(
        ..., description="fill_ratio | clearance | proportion"
    )
    message: str


class FitCheckResponse(BaseModel):
    """
    Result of the fit-check collision detection.

    Returns three levels of feedback:
      1. collisions — hard blockers (furniture overlaps a wall)
      2. warnings  — design problems (room too crowded, no walking space)
      3. clearance — raw distances so the Flutter app can visualise breathing room
    """
    fits: bool = Field(..., description="True if the furniture fits without collisions")
    verdict: str = Field(
        default="fits",
        description="'fits', 'tight_fit', 'too_large' — helps the UI pick the right display",
    )
    collisions: list[CollisionDetail] = Field(default_factory=list)
    warnings: list[DesignWarning] = Field(default_factory=list)
    design_score: int = Field(
        default=100,
        ge=0, le=100,
        description="0-100 design quality score (100 = great layout)",
    )
    clearance: Optional[dict[str, float]] = Field(
        default=None,
        description="Distance to nearest walls: {north_m, south_m, east_m, west_m}",
    )
    suggestion: Optional[str] = Field(
        default=None,
        description="Human-readable suggestion if it doesn't fit",
    )
    furniture_footprint: Optional[dict[str, Any]] = Field(
        default=None,
        description="The computed footprint of the furniture at the given position",
    )
    room_fill_percent: Optional[float] = Field(
        default=None,
        description="Percentage of floor area occupied by this furniture",
    )
    room_dimensions: Optional[dict[str, float]] = Field(
        default=None,
        description="Room dimensions: {width_m, length_m, height_m}",
    )
    placement_used: Optional[dict[str, Any]] = Field(
        default=None,
        description="The actual placement position used: {x, z, rotation_y, strategy}",
    )


# ── Multi-Furniture Layout Schemas ────────────────────────────────────────────

class MultiFitCheckItem(BaseModel):
    """One item in a multi-furniture layout check."""
    product_id: str
    position: Optional[PlacementPosition] = None


class MultiFitCheckRequest(BaseModel):
    """Check multiple furniture items in the same room simultaneously."""
    room_id: str
    items: list[MultiFitCheckItem] = Field(..., min_length=1, max_length=20)


class MultiFitItemResult(BaseModel):
    """Per-item result within a multi-furniture layout check."""
    product_id: str
    product_name: str
    category: str
    fits: bool
    verdict: str = "fits"
    collisions: list[CollisionDetail] = Field(default_factory=list)
    warnings: list[DesignWarning] = Field(default_factory=list)
    design_score: int = 100
    clearance: Optional[dict[str, float]] = None
    placement_used: Optional[dict[str, Any]] = None
    furniture_footprint: Optional[dict[str, Any]] = None


class MultiFitCheckResponse(BaseModel):
    """Result of checking multiple furniture items in one room."""
    overall_fits: bool
    total_fill_percent: float = 0.0
    overall_score: int = 100
    room_dimensions: Optional[dict[str, float]] = None
    items: list[MultiFitItemResult] = Field(default_factory=list)
    inter_collisions: list[CollisionDetail] = Field(default_factory=list)
    combined_warnings: list[DesignWarning] = Field(default_factory=list)
