"""
DesignMirror AI — Room Schemas (Pydantic)
==========================================

Request/response schemas for the room scan endpoints.

These schemas validate the JSON data sent from the Flutter app.
If ANY field is missing or has the wrong type, Pydantic rejects the
request with a clear error message BEFORE it reaches our business logic.

SECURITY: Pydantic validation is our first line of defense against
malformed or malicious input. No raw user data ever touches the database.
"""

from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, Field


# ── Nested Schemas (AR data structure) ────────────────────────────────────────

class ARPointSchema(BaseModel):
    """A 3D point in AR world coordinates (meters)."""
    x: float
    y: float
    z: float


class PlaneExtentSchema(BaseModel):
    """2D extent (size) of a detected AR plane."""
    width: float = Field(..., gt=0, description="Width in meters")
    height: float = Field(..., gt=0, description="Height in meters")


class ARPlaneSchema(BaseModel):
    """A detected AR surface (floor, wall, etc.)."""
    id: str = Field(..., min_length=1)
    type: str = Field(..., pattern="^(floor|wall|ceiling|table|seat|unknown)$")
    center: ARPointSchema
    extent: PlaneExtentSchema
    transform: Optional[list[float]] = Field(
        default=None,
        description="4x4 transformation matrix (16 floats, column-major)",
    )


class MeasurementPointSchema(BaseModel):
    """A user-tapped measurement point."""
    x: float
    y: float
    z: float
    label: str = Field(..., min_length=1, max_length=50)


class DeviceInfoSchema(BaseModel):
    """Device capabilities sent with scan data."""
    has_lidar: bool
    tracking_quality: str = Field(
        ..., pattern="^(normal|limited|not_available)$"
    )


# ── Request Schemas ───────────────────────────────────────────────────────────

VALID_ROOM_TYPES = [
    "bedroom", "living_room", "dining_room", "office",
    "kitchen", "bathroom", "kids_room", "guest_room", "other",
]


class RoomScanRequest(BaseModel):
    """
    Complete room scan data submitted from the Flutter app.

    This is the JSON packet described in the Flutter ar_models.dart file.
    Pydantic validates every nested object recursively.
    """
    room_name: str = Field(..., min_length=1, max_length=100)
    room_type: Optional[str] = Field(default=None, description="Room type tag for recommendations")
    planes: list[ARPlaneSchema] = Field(
        ..., description="Detected AR planes"
    )
    measurement_points: list[MeasurementPointSchema] = Field(
        ..., min_length=3, description="At least 3 measurement points required"
    )
    device_info: DeviceInfoSchema


class ManualRoomRequest(BaseModel):
    """
    Manual room dimensions entered by the user (tape measure, visual estimate, etc.).
    No AR scan needed — the user provides width, length, and optionally height.
    """
    room_name: str = Field(..., min_length=1, max_length=100)
    room_type: Optional[str] = Field(default=None, description="Room type tag for recommendations")
    width_m: float = Field(..., gt=0, le=50, description="Room width in meters")
    length_m: float = Field(..., gt=0, le=50, description="Room length in meters")
    height_m: Optional[float] = Field(
        default=None, gt=0, le=10, description="Ceiling height in meters (optional)"
    )
    shape: str = Field(
        default="rectangular",
        pattern="^(rectangular|l_shaped|custom)$",
        description="Room shape type",
    )


class RoomUpdateRequest(BaseModel):
    """Partial update for room metadata (e.g. setting room type)."""
    room_name: Optional[str] = Field(default=None, min_length=1, max_length=100)
    room_type: Optional[str] = Field(default=None)


# ── Response Schemas ──────────────────────────────────────────────────────────

class RoomResponse(BaseModel):
    """Room data returned to the client after scan submission or retrieval."""
    id: str
    room_name: str
    room_type: Optional[str] = None
    status: str
    dimensions: Optional[dict[str, Any]] = None
    plane_count: int
    point_count: int
    photos: list[str] = Field(default_factory=list)
    created_at: datetime


class RoomDimensionsResponse(BaseModel):
    """Processed room dimensions (after coordinate transformation)."""
    width_m: float
    length_m: float
    height_m: Optional[float] = None
    area_m2: float
    volume_m3: Optional[float] = None
    wall_segments: list[dict[str, Any]] = Field(default_factory=list)

