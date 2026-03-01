"""
DesignMirror AI — Rooms Router
================================

Endpoints for room scan operations:
  POST /api/v1/rooms/scan       → Submit a new AR room scan
  GET  /api/v1/rooms            → List user's room scans
  GET  /api/v1/rooms/{room_id}  → Get a specific room scan
  DELETE /api/v1/rooms/{room_id} → Delete a room scan

ALL endpoints are PROTECTED — they require a valid JWT access token.
Each endpoint uses Depends(get_current_user) to ensure ownership.
"""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, UploadFile, File, status

from app.core.exceptions import NotFoundError
from app.dependencies import get_current_user
from app.models.room import Room
from app.models.user import User
from app.schemas.room import ManualRoomRequest, RoomResponse, RoomScanRequest, RoomUpdateRequest
from app.services import room_service, storage_service

router = APIRouter(prefix="/rooms", tags=["Rooms"])


@router.post(
    "/scan",
    response_model=RoomResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Submit a new room scan",
    responses={
        422: {"description": "Invalid scan data (validation error)"},
        401: {"description": "Not authenticated"},
    },
)
async def submit_scan(
    data: RoomScanRequest,
    current_user: User = Depends(get_current_user),
) -> RoomResponse:
    """
    Submit AR room scan data for processing.

    The backend will:
    1. Validate the scan data (planes, measurement points, device info).
    2. Transform AR coordinates into real-world measurements.
    3. Store the processed room in the database.
    4. Return the room with dimensions.

    **Requires:** At least 3 measurement points.

    **Request body example:**
    ```json
    {
      "room_name": "Living Room",
      "planes": [
        {
          "id": "plane_001",
          "type": "floor",
          "center": {"x": 0.0, "y": 0.0, "z": -2.5},
          "extent": {"width": 4.2, "height": 3.1},
          "transform": null
        }
      ],
      "measurement_points": [
        {"x": -2.1, "y": 0.0, "z": -1.5, "label": "corner_1"},
        {"x":  2.1, "y": 0.0, "z": -1.5, "label": "corner_2"},
        {"x":  2.1, "y": 0.0, "z":  1.5, "label": "corner_3"},
        {"x": -2.1, "y": 0.0, "z":  1.5, "label": "corner_4"}
      ],
      "device_info": {
        "has_lidar": true,
        "tracking_quality": "normal"
      }
    }
    ```
    """
    return await room_service.create_room_scan(
        data=data,
        owner_id=str(current_user.id),
    )


@router.post(
    "/manual",
    response_model=RoomResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create room from manual dimensions",
    responses={
        422: {"description": "Invalid dimensions (validation error)"},
        401: {"description": "Not authenticated"},
    },
)
async def create_manual_room(
    data: ManualRoomRequest,
    current_user: User = Depends(get_current_user),
) -> RoomResponse:
    """
    Create a room from manually entered dimensions (no AR scan required).

    The user measures their room with a tape measure or estimates it,
    then enters width, length, and optionally ceiling height.

    The backend builds the room geometry (wall segments, area, etc.)
    from these dimensions directly.
    """
    return await room_service.create_manual_room(
        data=data,
        owner_id=str(current_user.id),
    )


@router.get(
    "",
    response_model=list[RoomResponse],
    summary="List all room scans for the current user",
)
async def list_rooms(
    current_user: User = Depends(get_current_user),
) -> list[RoomResponse]:
    """
    Get all room scans belonging to the authenticated user.
    Sorted by creation date (newest first).
    """
    return await room_service.get_user_rooms(owner_id=str(current_user.id))


@router.get(
    "/{room_id}",
    response_model=RoomResponse,
    summary="Get a specific room scan",
    responses={
        404: {"description": "Room not found"},
        403: {"description": "Access denied — not your room"},
    },
)
async def get_room(
    room_id: str,
    current_user: User = Depends(get_current_user),
) -> RoomResponse:
    """
    Get a specific room scan by ID.
    Only the room's owner can access it.
    """
    return await room_service.get_room_by_id(
        room_id=room_id,
        owner_id=str(current_user.id),
    )


@router.patch(
    "/{room_id}",
    response_model=RoomResponse,
    summary="Update room metadata (name, type)",
)
async def update_room(
    room_id: str,
    data: RoomUpdateRequest,
    current_user: User = Depends(get_current_user),
) -> RoomResponse:
    """Update room metadata such as name or room type."""
    return await room_service.update_room(
        room_id=room_id,
        owner_id=str(current_user.id),
        data=data,
    )


@router.delete(
    "/{room_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a room scan",
    responses={
        404: {"description": "Room not found"},
        403: {"description": "Access denied — not your room"},
    },
)
async def delete_room(
    room_id: str,
    current_user: User = Depends(get_current_user),
) -> None:
    """
    Delete a room scan by ID.
    Only the room's owner can delete it.
    """
    await room_service.delete_room(
        room_id=room_id,
        owner_id=str(current_user.id),
    )


@router.post(
    "/{room_id}/photos",
    summary="Upload a reference photo for a room",
    status_code=status.HTTP_201_CREATED,
)
async def upload_room_photo(
    room_id: str,
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
):
    room = await Room.get(room_id)
    if not room or str(room.owner_id) != str(current_user.id):
        raise NotFoundError(message="Room not found", error_code="ROOM_NOT_FOUND")

    data = await file.read()
    url = storage_service.upload_photo(
        data=data,
        content_type=file.content_type or "image/jpeg",
        user_id=str(current_user.id),
    )

    room.photos.append(url)
    room.updated_at = datetime.now(timezone.utc)
    await room.save()

    return {"url": url, "photos": room.photos}


@router.delete(
    "/{room_id}/photos/{photo_index}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a room photo by index",
)
async def delete_room_photo(
    room_id: str,
    photo_index: int,
    current_user: User = Depends(get_current_user),
) -> None:
    room = await Room.get(room_id)
    if not room or str(room.owner_id) != str(current_user.id):
        raise NotFoundError(message="Room not found", error_code="ROOM_NOT_FOUND")

    if photo_index < 0 or photo_index >= len(room.photos):
        raise NotFoundError(message="Photo not found", error_code="PHOTO_NOT_FOUND")

    url = room.photos.pop(photo_index)
    try:
        storage_service.delete_photo(url)
    except Exception:
        pass

    room.updated_at = datetime.now(timezone.utc)
    await room.save()

