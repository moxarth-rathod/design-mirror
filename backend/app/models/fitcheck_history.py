"""
DesignMirror AI — Fit-Check History Model
==========================================
Stores snapshots of past fit-check results so users can revisit them.
"""

from datetime import datetime, timezone
from typing import Any, Optional

from beanie import Document, Indexed
from pydantic import Field


class FitCheckHistory(Document):
    user_id: Indexed(str)  # type: ignore[valid-type]
    room_id: str
    room_name: str
    product_id: str
    product_name: str
    product_category: str
    verdict: str
    design_score: int = 0
    result_snapshot: dict[str, Any] = Field(default_factory=dict)
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

    class Settings:
        name = "fitcheck_history"
