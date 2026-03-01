"""
DesignMirror AI — Room Service
================================

Business logic for room scan operations:
  • Submit and process new room scans
  • Retrieve user's room scans
  • Delete room scans

SECURITY: Every operation filters by owner_id to ensure users
can only access their own room scans.
"""

from datetime import datetime, timezone

from beanie import PydanticObjectId

from app.core.exceptions import ForbiddenError, NotFoundError
from app.core.logging import logger
from app.models.room import Room
from app.schemas.room import ManualRoomRequest, RoomResponse, RoomScanRequest, RoomUpdateRequest
from app.services.coordinate_service import transform_scan_to_dimensions
from app.services.unit_safety import LengthUnit, Measurement


async def create_room_scan(
    data: RoomScanRequest,
    owner_id: str,
) -> RoomResponse:
    """
    Process and store a new room scan.

    Steps:
    1. Create the Room document with raw AR data (status="processing").
    2. Run coordinate transformation to compute real-world dimensions.
    3. Update the document with processed dimensions (status="completed").
    4. Return the response.

    In the future (Sprint 4), step 2 could be moved to a Celery worker
    for heavy scans that include SAM segmentation.
    """
    logger.info(
        "Processing room scan '{}' from user {} — {} planes, {} points",
        data.room_name,
        owner_id,
        len(data.planes),
        len(data.measurement_points),
    )

    # Step 1: Create the room document with raw data
    room = Room(
        owner_id=PydanticObjectId(owner_id),
        room_name=data.room_name,
        room_type=data.room_type,
        status="processing",
        planes=[plane.model_dump() for plane in data.planes],
        measurement_points=[pt.model_dump() for pt in data.measurement_points],
        device_info=data.device_info.model_dump(),
    )
    await room.insert()

    # Step 2: Run coordinate transformation
    try:
        dimensions = transform_scan_to_dimensions(
            planes=room.planes,
            measurement_points=room.measurement_points,
            device_info=room.device_info,
        )

        # Step 3: Update with processed data
        room.dimensions = dimensions
        room.status = "completed"
        room.updated_at = datetime.now(timezone.utc)
        await room.save()

        logger.info("Room '{}' processed successfully — ID: {}", room.room_name, room.id)

    except Exception as e:
        # Mark as failed if processing errors occur
        room.status = "failed"
        room.updated_at = datetime.now(timezone.utc)
        await room.save()
        logger.error("Room processing failed for ID {}: {}", room.id, str(e))

    # Step 4: Return response
    return RoomResponse(
        id=str(room.id),
        room_name=room.room_name,
        room_type=room.room_type,
        status=room.status,
        dimensions=room.dimensions,
        plane_count=room.plane_count,
        point_count=room.point_count,
        created_at=room.created_at,
    )


async def create_manual_room(
    data: ManualRoomRequest,
    owner_id: str,
) -> RoomResponse:
    """
    Create a room from manually entered dimensions.

    Builds a rectangular room geometry with proper wall segments,
    area, and unit conversions — no AR scan needed.
    """
    w = data.width_m
    l = data.length_m
    h = data.height_m
    hw = w / 2
    hl = l / 2

    corners = [
        (-hw, -hl),
        (hw, -hl),
        (hw, hl),
        (-hw, hl),
    ]

    wall_segments = []
    for i in range(len(corners)):
        start = corners[i]
        end = corners[(i + 1) % len(corners)]
        dx = end[0] - start[0]
        dz = end[1] - start[1]
        seg_length = (dx * dx + dz * dz) ** 0.5
        seg_m = Measurement.meters(seg_length)
        wall_segments.append({
            "start": list(start),
            "end": list(end),
            "length_m": round(seg_length, 4),
            "length_ft": round(seg_m.to(LengthUnit.FEET).value, 4),
            "length_in": round(seg_m.to(LengthUnit.INCHES).value, 4),
        })

    measurement_points = [
        {"x": c[0], "y": 0, "z": c[1], "label": f"corner_{i + 1}"}
        for i, c in enumerate(corners)
    ]

    area = w * l
    width_m = Measurement.meters(w)
    length_m = Measurement.meters(l)

    dimensions = {
        "width_m": round(w, 4),
        "length_m": round(l, 4),
        "height_m": h,
        "area_m2": round(area, 3),
        "volume_m3": round(area * h, 3) if h else None,
        "wall_segments": wall_segments,
        "confidence": "high",
        "source": "manual",
        "unit_conversions": {
            "width_ft": round(width_m.to(LengthUnit.FEET).value, 2),
            "width_in": round(width_m.to(LengthUnit.INCHES).value, 2),
            "length_ft": round(length_m.to(LengthUnit.FEET).value, 2),
            "length_in": round(length_m.to(LengthUnit.INCHES).value, 2),
            "area_ft2": round(area * 10.7639, 2),
        },
    }

    room = Room(
        owner_id=PydanticObjectId(owner_id),
        room_name=data.room_name,
        room_type=data.room_type,
        status="completed",
        planes=[],
        measurement_points=measurement_points,
        device_info={"has_lidar": False, "tracking_quality": "not_available"},
        dimensions=dimensions,
    )
    await room.insert()

    logger.info(
        "Manual room '{}' created — {}×{}m, ID: {}",
        room.room_name, w, l, room.id,
    )

    return RoomResponse(
        id=str(room.id),
        room_name=room.room_name,
        room_type=room.room_type,
        status=room.status,
        dimensions=room.dimensions,
        plane_count=0,
        point_count=len(measurement_points),
        created_at=room.created_at,
    )


async def get_user_rooms(owner_id: str) -> list[RoomResponse]:
    """
    Get all room scans belonging to a specific user.

    SECURITY: Only returns rooms where owner_id matches the authenticated user.
    """
    rooms = await Room.find(
        Room.owner_id == PydanticObjectId(owner_id)
    ).sort(-Room.created_at).to_list()

    return [
        RoomResponse(
            id=str(room.id),
            room_name=room.room_name,
            room_type=room.room_type,
            status=room.status,
            dimensions=room.dimensions,
            plane_count=room.plane_count,
            point_count=room.point_count,
            created_at=room.created_at,
        )
        for room in rooms
    ]


async def get_room_by_id(room_id: str, owner_id: str) -> RoomResponse:
    """
    Get a specific room scan by ID, verifying ownership.

    SECURITY: We check that the room belongs to the requesting user.
    Without this check, any authenticated user could access any room by ID.
    """
    room = await Room.get(room_id)

    if room is None:
        raise NotFoundError(
            message=f"Room with ID '{room_id}' not found",
            error_code="ROOM_NOT_FOUND",
        )

    # Ownership check
    if str(room.owner_id) != owner_id:
        raise ForbiddenError(
            message="You do not have access to this room",
            error_code="ROOM_ACCESS_DENIED",
        )

    return RoomResponse(
        id=str(room.id),
        room_name=room.room_name,
        room_type=room.room_type,
        status=room.status,
        dimensions=room.dimensions,
        plane_count=room.plane_count,
        point_count=room.point_count,
        created_at=room.created_at,
    )


async def update_room(room_id: str, owner_id: str, data: RoomUpdateRequest) -> RoomResponse:
    """Update room metadata (name, type)."""
    room = await Room.get(room_id)
    if room is None:
        raise NotFoundError(message=f"Room '{room_id}' not found", error_code="ROOM_NOT_FOUND")
    if str(room.owner_id) != owner_id:
        raise ForbiddenError(message="Access denied", error_code="ROOM_ACCESS_DENIED")

    if data.room_name is not None:
        room.room_name = data.room_name
    if data.room_type is not None:
        room.room_type = data.room_type
    room.updated_at = datetime.now(timezone.utc)
    await room.save()

    return RoomResponse(
        id=str(room.id),
        room_name=room.room_name,
        room_type=room.room_type,
        status=room.status,
        dimensions=room.dimensions,
        plane_count=room.plane_count,
        point_count=room.point_count,
        created_at=room.created_at,
    )


async def delete_room(room_id: str, owner_id: str) -> None:
    """
    Delete a room scan, verifying ownership first.
    """
    room = await Room.get(room_id)

    if room is None:
        raise NotFoundError(
            message=f"Room with ID '{room_id}' not found",
            error_code="ROOM_NOT_FOUND",
        )

    if str(room.owner_id) != owner_id:
        raise ForbiddenError(
            message="You do not have access to this room",
            error_code="ROOM_ACCESS_DENIED",
        )

    await room.delete()
    logger.info("Room '{}' (ID: {}) deleted by user {}", room.room_name, room_id, owner_id)

