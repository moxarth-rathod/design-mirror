"""
DesignMirror AI — Fit-Check Router
====================================

Endpoint for the collision detection system.
Checks if a piece of furniture fits at a specific position in a scanned room.

This is PROTECTED — only authenticated users can run fit-checks,
and only against their own rooms (verified in the service layer).
"""

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query

from app.core.exceptions import DesignMirrorException, NotFoundError
from app.core.logging import logger
from app.dependencies import get_current_user
from app.models.product import Product
from app.models.room import Room
from app.models.user import User
from app.models.fitcheck_history import FitCheckHistory
from app.schemas.fitcheck import (
    FitCheckRequest,
    FitCheckResponse,
    MultiFitCheckRequest,
    MultiFitCheckResponse,
)
from app.services import fitcheck_service

router = APIRouter(prefix="/fitcheck", tags=["Fit-Check"])


@router.post(
    "",
    response_model=FitCheckResponse,
    summary="Check if furniture fits in a room",
)
async def check_fit(
    data: FitCheckRequest,
    current_user: User = Depends(get_current_user),
) -> FitCheckResponse:
    try:
        result = await fitcheck_service.check_furniture_fit(data)

        # Auto-save to history
        try:
            room = await Room.get(data.room_id)
            product = await Product.get(data.product_id)
            if room and product:
                await FitCheckHistory(
                    user_id=str(current_user.id),
                    room_id=data.room_id,
                    room_name=room.room_name,
                    product_id=data.product_id,
                    product_name=product.name,
                    product_category=product.category,
                    verdict=result.verdict,
                    design_score=result.design_score,
                    result_snapshot=result.model_dump(mode="json"),
                ).insert()
        except Exception as e:
            logger.warning("Failed to save fit-check history: {}", str(e))

        return result
    except (HTTPException, DesignMirrorException):
        raise
    except Exception as e:
        logger.error("Fit-check failed: {}", str(e), exc_info=True)
        raise HTTPException(status_code=500, detail=f"Fit-check error: {e}")


@router.post(
    "/multi",
    response_model=MultiFitCheckResponse,
    summary="Check multiple furniture items in a room simultaneously",
)
async def check_multi_fit(
    data: MultiFitCheckRequest,
    current_user: User = Depends(get_current_user),
) -> MultiFitCheckResponse:
    """Check if multiple furniture items fit in a room, with inter-furniture collision detection."""
    try:
        return await fitcheck_service.check_multi_furniture_fit(data)
    except (HTTPException, DesignMirrorException):
        raise
    except Exception as e:
        logger.error("Multi fit-check failed: {}", str(e), exc_info=True)
        raise HTTPException(status_code=500, detail=f"Multi fit-check error: {e}")


@router.get(
    "/history",
    summary="List past fit-check results",
)
async def list_history(
    current_user: User = Depends(get_current_user),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
):
    skip = (page - 1) * page_size
    total = await FitCheckHistory.find(
        FitCheckHistory.user_id == str(current_user.id)
    ).count()
    items = await FitCheckHistory.find(
        FitCheckHistory.user_id == str(current_user.id)
    ).sort("-created_at").skip(skip).limit(page_size).to_list()

    return {
        "items": [
            {
                "id": str(h.id),
                "room_id": h.room_id,
                "room_name": h.room_name,
                "product_id": h.product_id,
                "product_name": h.product_name,
                "product_category": h.product_category,
                "verdict": h.verdict,
                "design_score": h.design_score,
                "result_snapshot": h.result_snapshot,
                "created_at": h.created_at.isoformat(),
            }
            for h in items
        ],
        "total": total,
        "page": page,
        "page_size": page_size,
        "has_next": (skip + page_size) < total,
    }


@router.delete(
    "/history/{history_id}",
    status_code=204,
    summary="Delete a fit-check history entry",
)
async def delete_history_entry(
    history_id: str,
    current_user: User = Depends(get_current_user),
) -> None:
    entry = await FitCheckHistory.get(history_id)
    if not entry or entry.user_id != str(current_user.id):
        raise NotFoundError(message="History entry not found", error_code="NOT_FOUND")
    await entry.delete()
