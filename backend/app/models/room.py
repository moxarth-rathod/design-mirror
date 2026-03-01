"""
DesignMirror AI — Room Document Model (Beanie ODM)
====================================================

Stores room scan data submitted from the Flutter AR client.

Each room document contains:
  • The original AR scan data (planes, measurement points)
  • Processed real-world dimensions (computed by the Coordinate Transformation Service)
  • Processing status (so the client knows when SAM segmentation is done)
  • Owner reference (ties the room to a specific user)

SECURITY: Room scans are private data. Every query must filter by owner_id
to prevent users from accessing each other's room scans.
"""

from datetime import datetime, timezone
from typing import Any, Optional

from beanie import Document, Indexed, PydanticObjectId
from pydantic import Field


class Room(Document):
    """
    Represents a scanned room in the DesignMirror system.

    Maps to the 'rooms' collection in MongoDB.
    """

    # ── Ownership ──────────────────────────────
    owner_id: Indexed(PydanticObjectId)  # type: ignore[valid-type]
    """
    Reference to the User who owns this room scan.
    Indexed for fast queries: "get all rooms for user X".
    """

    # ── Room Metadata ──────────────────────────
    room_name: str = Field(..., min_length=1, max_length=100)
    """User-provided room name (e.g., "Living Room", "Master Bedroom")."""

    room_type: Optional[str] = Field(default=None)
    """Room type tag used for style recommendations (bedroom, living_room, etc.)."""

    status: str = Field(default="processing")
    """
    Processing status:
      • "processing" — scan received, coordinate transform in progress
      • "completed"  — all processing done, dimensions available
      • "failed"     — processing encountered an error
    """

    # ── AR Scan Data (raw from device) ─────────
    planes: list[dict[str, Any]] = Field(default_factory=list)
    """
    Raw AR plane data from the device.
    Each plane: {id, type, center: {x,y,z}, extent: {width, height}, transform: [...]}
    Stored as raw dicts because the AR data format may vary by device.
    """

    measurement_points: list[dict[str, Any]] = Field(default_factory=list)
    """
    User-tapped measurement points.
    Each point: {x, y, z, label}
    """

    device_info: dict[str, Any] = Field(default_factory=dict)
    """
    Device capability information.
    {has_lidar: bool, tracking_quality: "normal"|"limited"}
    """

    # ── Processed Data (from Coordinate Transform) ──
    dimensions: Optional[dict[str, Any]] = Field(default=None)
    """
    Processed real-world dimensions (populated after coordinate transformation).
    Example:
    {
        "width_m": 4.2,
        "length_m": 5.1,
        "height_m": 2.7,
        "area_m2": 21.42,
        "volume_m3": 57.83,
        "wall_segments": [
            {"start": [0, 0], "end": [4.2, 0], "length_m": 4.2},
            ...
        ]
    }
    """

    # ── Photos ──────────────────────────────────
    photos: list[str] = Field(default_factory=list)
    """URLs of reference photos stored in MinIO."""

    # ── Timestamps ─────────────────────────────
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: Optional[datetime] = Field(default=None)

    # ── Beanie Settings ────────────────────────
    class Settings:
        name = "rooms"

    # ── Helper Properties ──────────────────────
    @property
    def plane_count(self) -> int:
        return len(self.planes)

    @property
    def point_count(self) -> int:
        return len(self.measurement_points)

    def to_response_dict(self) -> dict:
        """Convert to a dict suitable for API responses."""
        return {
            "id": str(self.id),
            "room_name": self.room_name,
            "room_type": self.room_type,
            "status": self.status,
            "dimensions": self.dimensions,
            "plane_count": self.plane_count,
            "point_count": self.point_count,
            "photos": self.photos,
            "created_at": self.created_at.isoformat(),
        }

