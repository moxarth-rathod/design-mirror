"""
DesignMirror AI — Fit-Check Collision Detection Service
========================================================

MENTOR MOMENT: What is Collision Detection?
───────────────────────────────────────────
In video games, collision detection prevents characters from walking
through walls. In DesignMirror, it prevents users from placing a sofa
inside a wall.

The algorithm is called AABB (Axis-Aligned Bounding Box) collision:
  1. Represent the furniture as a 3D box (width × depth × height).
  2. Represent each wall as a thin 3D box (line segment with thickness).
  3. Check if ANY of the furniture's box overlaps with ANY wall box.

AABB is the simplest and fastest collision detection method. It works
because furniture is typically rectangular and rooms have straight walls.

     Room (top-down view)
     ┌────────────────────────┐
     │                        │
     │    ┌────────┐          │  ← Sofa bounding box
     │    │  SOFA  │          │
     │    └────────┘          │
     │                        │
     │         ┌───┐          │
     │         │TBL│          │  ← Table bounding box
     │         └───┘          │
     │                        │
     └────────────────────────┘

Collision check:
  • Sofa box vs. North wall → No overlap ✓
  • Sofa box vs. West wall  → No overlap ✓
  • Sofa vs. Table          → No overlap ✓
  Result: FITS ✓

If we moved the sofa 1 meter to the left:
  • Sofa box vs. West wall  → OVERLAP! 0.3m into the wall
  Result: DOESN'T FIT ✕ ("Move 0.3m to the right")

HOW AABB OVERLAP WORKS:
───────────────────────
Two boxes overlap if and only if they overlap on ALL three axes.
For each axis: box1.min < box2.max AND box1.max > box2.min

This is O(1) per pair — constant time regardless of furniture size.
Checking all walls is O(n) where n = number of wall segments.
For a typical room (4-8 walls), this takes microseconds.
"""

import math
from typing import Any, Optional

from app.core.exceptions import NotFoundError
from app.core.logging import logger
from app.models.product import Product
from app.models.room import Room
from app.schemas.fitcheck import (
    CollisionDetail,
    DesignWarning,
    FitCheckRequest,
    FitCheckResponse,
    MultiFitCheckItem,
    MultiFitCheckRequest,
    MultiFitCheckResponse,
    MultiFitItemResult,
    PlacementPosition,
)
from app.services.placement_service import compute_optimal_position, determine_strategy
from app.services.unit_safety import LengthUnit, Measurement


# ── Design Constants ─────────────────────────────────────────────────────────
# These thresholds encode interior-design best practices.

MIN_WALKWAY_M = 0.60          # 60 cm — minimum passage width (ADA is 0.91 m)
COMFORTABLE_CLEARANCE_M = 0.90  # 90 cm — comfortable clearance around furniture
MAX_FILL_RATIO_WARNING = 0.40   # 40 % — warn when furniture fills >40 % of floor
MAX_FILL_RATIO_CRITICAL = 0.60  # 60 % — serious warning at >60 %
BED_SIDE_MIN_M = 0.60          # 60 cm clearance on at least one side of a bed
TABLE_CHAIR_PULLOUT_M = 0.75   # 75 cm behind a dining chair for pull-out room


# ── Data Structures ───────────────────────────────────────────────────────────

class AABB:
    """
    Axis-Aligned Bounding Box in 2D (top-down floor plan view).

    We use 2D for collision detection because furniture sits on the floor.
    Height is checked separately (e.g., does a tall shelf fit under the ceiling?).
    """
    __slots__ = ("min_x", "min_z", "max_x", "max_z")

    def __init__(self, min_x: float, min_z: float, max_x: float, max_z: float):
        self.min_x = min(min_x, max_x)
        self.min_z = min(min_z, max_z)
        self.max_x = max(min_x, max_x)
        self.max_z = max(min_z, max_z)

    def overlaps(self, other: "AABB") -> bool:
        """Check if this AABB overlaps with another AABB."""
        return (
            self.min_x < other.max_x
            and self.max_x > other.min_x
            and self.min_z < other.max_z
            and self.max_z > other.min_z
        )

    def overlap_amount(self, other: "AABB") -> tuple[float, float]:
        """
        Calculate how much two AABBs overlap on each axis.
        Returns (overlap_x, overlap_z). Values > 0 mean overlap.
        """
        overlap_x = min(self.max_x, other.max_x) - max(self.min_x, other.min_x)
        overlap_z = min(self.max_z, other.max_z) - max(self.min_z, other.min_z)
        return max(0, overlap_x), max(0, overlap_z)

    def distance_to_point(self, x: float, z: float) -> float:
        """Distance from a point to the nearest edge of this AABB."""
        dx = max(self.min_x - x, 0, x - self.max_x)
        dz = max(self.min_z - z, 0, z - self.max_z)
        return math.sqrt(dx * dx + dz * dz)

    @property
    def center(self) -> tuple[float, float]:
        return (
            (self.min_x + self.max_x) / 2,
            (self.min_z + self.max_z) / 2,
        )

    @property
    def width(self) -> float:
        return self.max_x - self.min_x

    @property
    def depth(self) -> float:
        return self.max_z - self.min_z


# ── Core Fit-Check Logic ──────────────────────────────────────────────────────

async def check_furniture_fit(request: FitCheckRequest) -> FitCheckResponse:
    """
    Main fit-check entry point.

    Steps:
    1. Load the room dimensions and wall segments from MongoDB.
    2. Load the product bounding box from MongoDB.
    3. Compute the furniture's AABB at the desired position.
    4. Check for collisions with room boundaries (walls).
    5. Check ceiling clearance (height).
    6. Return detailed results.
    """
    # ── Load Room ──────────────────────────────
    try:
        room = await Room.get(request.room_id)
    except Exception:
        room = None
    if not room:
        raise NotFoundError(
            message=f"Room '{request.room_id}' not found",
            error_code="ROOM_NOT_FOUND",
        )
    if not room.dimensions:
        raise NotFoundError(
            message="Room has no processed dimensions. Was the scan completed?",
            error_code="ROOM_NOT_PROCESSED",
        )

    # ── Load Product ───────────────────────────
    try:
        product = await Product.get(request.product_id)
    except Exception:
        product = None
    if not product:
        raise NotFoundError(
            message=f"Product '{request.product_id}' not found",
            error_code="PRODUCT_NOT_FOUND",
        )

    # ── Determine placement position ────────────
    room_w = room.dimensions.get("width_m") or 0
    room_l = room.dimensions.get("length_m") or 0
    room_h = room.dimensions.get("height_m") or 2.5

    if request.position is not None:
        position = request.position
        placement_strategy = "manual"
    else:
        opt_x, opt_z, opt_rot = compute_optimal_position(
            category=product.category,
            tags=product.tags if hasattr(product, "tags") else [],
            furniture_width=product.bounding_box.width_m,
            furniture_depth=product.bounding_box.depth_m,
            furniture_height=product.bounding_box.height_m,
            room_width=room_w,
            room_length=room_l,
            room_height=room_h,
        )
        position = PlacementPosition(x=opt_x, z=opt_z, rotation_y=opt_rot)
        placement_strategy = determine_strategy(
            product.category,
            product.tags if hasattr(product, "tags") else [],
        ).value

    logger.info(
        "Fit-check: '{}' in room '{}' at ({:.2f}, {:.2f}) strategy={}",
        product.name,
        room.room_name,
        position.x,
        position.z,
        placement_strategy,
    )

    # ── Compute Furniture AABB ─────────────────
    furniture_aabb = _compute_furniture_aabb(
        width_m=product.bounding_box.width_m,
        depth_m=product.bounding_box.depth_m,
        position=position,
    )

    # ── Build Room Boundary AABB ───────────────
    room_aabb = _compute_room_aabb(room.dimensions)

    # ── Run Collision Checks ───────────────────
    collisions: list[CollisionDetail] = []

    # Check 1: Is furniture inside the room boundaries?
    boundary_collisions = _check_boundary_collisions(furniture_aabb, room_aabb)
    collisions.extend(boundary_collisions)

    # Check 2: Wall segment collisions (more precise)
    wall_segments = room.dimensions.get("wall_segments", [])
    wall_collisions = _check_wall_collisions(furniture_aabb, wall_segments)
    collisions.extend(wall_collisions)

    # Check 3: Ceiling clearance
    room_height = room.dimensions.get("height_m")
    if room_height and product.bounding_box.height_m > room_height:
        height_diff = Measurement.meters(product.bounding_box.height_m - room_height)
        collisions.append(CollisionDetail(
            type="ceiling",
            description=(
                f"Furniture is {height_diff.to(LengthUnit.INCHES).value:.1f}\" "
                f"taller than the room ceiling"
            ),
            overlap_m=round(product.bounding_box.height_m - room_height, 4),
        ))

    # ── Validate dimensions ─────────────────────
    if room_w <= 0 or room_l <= 0:
        logger.warning(
            "Room '{}' has invalid dimensions ({}×{}m) — returning basic response",
            room.room_name, room_w, room_l,
        )
        return FitCheckResponse(
            fits=False,
            collisions=[CollisionDetail(
                type="boundary",
                description="Room dimensions are missing or zero — please re-scan the room",
            )],
            design_score=0,
            suggestion="The room has no valid dimensions. Try re-scanning or entering dimensions manually.",
            room_dimensions={
                "width_m": round(room_w, 2),
                "length_m": round(room_l, 2),
                "height_m": round(room_h, 2),
            },
            placement_used={
                "x": round(position.x, 4),
                "z": round(position.z, 4),
                "rotation_y": round(position.rotation_y, 1),
                "strategy": placement_strategy,
            },
        )

    # ── Compute Clearance ──────────────────────
    clearance = _compute_clearance(furniture_aabb, room_aabb)
    # Clamp negative clearances to 0 for display (negative = extends past wall)
    clearance_display = {k: max(0.0, v) for k, v in clearance.items()}

    # ── Floor fill ratio ──────────────────────
    room_floor_area = room_aabb.width * room_aabb.depth
    furniture_floor_area = product.bounding_box.width_m * product.bounding_box.depth_m
    fill_ratio = furniture_floor_area / room_floor_area if room_floor_area > 0 else 0
    fill_percent = round(fill_ratio * 100, 1)

    # ── Shared response data ──────────────────
    base_response = dict(
        room_fill_percent=fill_percent,
        room_dimensions={
            "width_m": round(room.dimensions.get("width_m") or 0, 2),
            "length_m": round(room.dimensions.get("length_m") or 0, 2),
            "height_m": round(room.dimensions.get("height_m") or 2.5, 2),
        },
        placement_used={
            "x": round(position.x, 4),
            "z": round(position.z, 4),
            "rotation_y": round(position.rotation_y, 1),
            "strategy": placement_strategy,
        },
        furniture_footprint={
            "min_x": round(furniture_aabb.min_x, 4),
            "min_z": round(furniture_aabb.min_z, 4),
            "max_x": round(furniture_aabb.max_x, 4),
            "max_z": round(furniture_aabb.max_z, 4),
            "width_m": round(furniture_aabb.width, 4),
            "depth_m": round(furniture_aabb.depth, 4),
        },
    )

    # ── Early exit: product is way too large ──
    too_wide = product.bounding_box.width_m > room_w
    too_deep = product.bounding_box.depth_m > room_l
    too_tall = product.bounding_box.height_m > room_h

    if fill_ratio > 1.0 or (too_wide and too_deep):
        reasons = []
        if too_wide:
            reasons.append(
                f"width ({product.bounding_box.width_m:.1f}m) exceeds room width ({room_w:.1f}m)"
            )
        if too_deep:
            reasons.append(
                f"depth ({product.bounding_box.depth_m:.1f}m) exceeds room length ({room_l:.1f}m)"
            )
        if too_tall:
            reasons.append(
                f"height ({product.bounding_box.height_m:.1f}m) exceeds ceiling ({room_h:.1f}m)"
            )
        if not reasons:
            reasons.append(
                f"floor area ({furniture_floor_area:.1f}m²) exceeds room area ({room_floor_area:.1f}m²)"
            )

        return FitCheckResponse(
            fits=False,
            verdict="too_large",
            collisions=[CollisionDetail(
                type="size",
                description=f"Product is too large for this room: {'; '.join(reasons)}",
            )],
            design_score=0,
            clearance=clearance_display,
            suggestion=(
                f"This {product.category} is too large for '{room.room_name}'. "
                f"Look for a smaller alternative or try a bigger room."
            ),
            **base_response,
        )

    # ── Deduplicate / filter collisions ────────
    # 1. If boundary collisions exist for a direction, wall-segment
    #    collisions on that same side are redundant.
    boundary_walls = set()
    for c in collisions:
        if c.type == "boundary":
            desc_lower = c.description.lower()
            for direction in ("west", "east", "south", "north"):
                if direction in desc_lower:
                    boundary_walls.add(direction)

    if boundary_walls:
        collisions = [
            c for c in collisions
            if c.type != "wall" or not any(
                d in c.description.lower() for d in boundary_walls
            )
        ]

    # 2. For any placement except center, wall-segment overlaps on
    #    intentionally flush sides are expected. Remove those wall collisions.
    if placement_strategy != "center" and clearance:
        flush_threshold = 0.15
        flush_sides = {
            s for s, key in [
                ("West", "west_m"), ("East", "east_m"),
                ("South", "south_m"), ("North", "north_m"),
            ]
            if clearance.get(key, 99) < flush_threshold
        }
        if flush_sides:
            collisions = [
                c for c in collisions
                if c.type != "wall" or not any(
                    side in c.description for side in flush_sides
                )
            ]

    # ── Design-Aware Checks ───────────────────
    warnings: list[DesignWarning] = []

    fill_warnings = _check_fill_ratio(fill_ratio, product.name)
    warnings.extend(fill_warnings)

    clearance_warnings = _check_clearance_quality(
        clearance, product.category, placement_strategy,
    )
    warnings.extend(clearance_warnings)

    category_warnings = _check_category_rules(
        clearance, product.category, product.bounding_box, placement_strategy,
    )
    warnings.extend(category_warnings)

    design_score = _compute_design_score(
        collisions, warnings, fill_ratio, clearance, placement_strategy,
    )

    # ── Determine verdict ─────────────────────
    fits = len(collisions) == 0
    if fits:
        verdict = "fits"
    elif too_wide or too_deep:
        verdict = "too_large"
    else:
        verdict = "tight_fit"

    # ── Generate Suggestion ────────────────────
    suggestion = _generate_suggestion(collisions, clearance, product.category) if not fits else None
    if fits and warnings:
        suggestion = "; ".join(w.message for w in warnings[:2]) + "."

    # ── Build Response ─────────────────────────
    return FitCheckResponse(
        fits=fits,
        verdict=verdict,
        collisions=collisions,
        warnings=warnings,
        design_score=design_score,
        clearance=clearance_display,
        suggestion=suggestion,
        **base_response,
    )


# ── Internal Helpers ──────────────────────────────────────────────────────────

def _compute_furniture_aabb(
    width_m: float,
    depth_m: float,
    position: PlacementPosition,
) -> AABB:
    """
    Compute the furniture's AABB at the desired position.

    For rotation, we compute the rotated bounding box. Since we use AABB
    (axis-aligned), a rotated object gets a LARGER bounding box — this is
    conservative (may say "doesn't fit" when it barely would with precise
    rotation), but it's safe. Better to be slightly cautious than to let
    furniture clip through walls.
    """
    half_w = width_m / 2
    half_d = depth_m / 2

    if position.rotation_y == 0:
        return AABB(
            min_x=position.x - half_w,
            min_z=position.z - half_d,
            max_x=position.x + half_w,
            max_z=position.z + half_d,
        )

    # Rotation: compute the axis-aligned bounding box of the rotated rectangle
    angle_rad = math.radians(position.rotation_y)
    cos_a = abs(math.cos(angle_rad))
    sin_a = abs(math.sin(angle_rad))

    # Rotated AABB dimensions (enclosing the rotated rectangle)
    new_half_w = half_w * cos_a + half_d * sin_a
    new_half_d = half_w * sin_a + half_d * cos_a

    return AABB(
        min_x=position.x - new_half_w,
        min_z=position.z - new_half_d,
        max_x=position.x + new_half_w,
        max_z=position.z + new_half_d,
    )


def _compute_room_aabb(dimensions: dict[str, Any]) -> AABB:
    """
    Compute the room's bounding AABB from its dimensions.

    We center the room at origin (0, 0) for simplicity.
    The room extends from (-width/2, -length/2) to (width/2, length/2).
    """
    width = dimensions.get("width_m", 0)
    length = dimensions.get("length_m", 0)

    return AABB(
        min_x=-width / 2,
        min_z=-length / 2,
        max_x=width / 2,
        max_z=length / 2,
    )


def _check_boundary_collisions(
    furniture: AABB, room: AABB
) -> list[CollisionDetail]:
    """
    Check if any part of the furniture extends beyond the room boundaries.
    """
    collisions = []

    if furniture.min_x < room.min_x:
        overlap = room.min_x - furniture.min_x
        collisions.append(CollisionDetail(
            type="boundary",
            description=f"Extends {overlap:.2f}m past the west wall",
            overlap_m=round(overlap, 4),
        ))

    if furniture.max_x > room.max_x:
        overlap = furniture.max_x - room.max_x
        collisions.append(CollisionDetail(
            type="boundary",
            description=f"Extends {overlap:.2f}m past the east wall",
            overlap_m=round(overlap, 4),
        ))

    if furniture.min_z < room.min_z:
        overlap = room.min_z - furniture.min_z
        collisions.append(CollisionDetail(
            type="boundary",
            description=f"Extends {overlap:.2f}m past the south wall",
            overlap_m=round(overlap, 4),
        ))

    if furniture.max_z > room.max_z:
        overlap = furniture.max_z - room.max_z
        collisions.append(CollisionDetail(
            type="boundary",
            description=f"Extends {overlap:.2f}m past the north wall",
            overlap_m=round(overlap, 4),
        ))

    return collisions


def _wall_direction_label(start: list, end: list) -> str:
    """Determine a compass direction (N/S/E/W) for a wall segment."""
    mid_x = (start[0] + end[0]) / 2
    mid_z = (start[1] + end[1]) / 2
    dx = abs(end[0] - start[0])
    dz = abs(end[1] - start[1])

    if dx >= dz:
        # Horizontal wall (runs along X) → either North or South
        return "North" if mid_z > 0 else "South"
    else:
        # Vertical wall (runs along Z) → either East or West
        return "East" if mid_x > 0 else "West"


def _check_wall_collisions(
    furniture: AABB, wall_segments: list[dict[str, Any]]
) -> list[CollisionDetail]:
    """
    Check if the furniture overlaps with any wall segment.

    Each wall segment is represented as a thin AABB (line with thickness).
    Wall thickness is assumed to be 0.15m (6 inches) — standard interior wall.
    """
    collisions = []
    wall_thickness = 0.15  # 6 inches

    for segment in wall_segments:
        start = segment.get("start", [0, 0])
        end = segment.get("end", [0, 0])

        wall_aabb = AABB(
            min_x=min(start[0], end[0]) - wall_thickness / 2,
            min_z=min(start[1], end[1]) - wall_thickness / 2,
            max_x=max(start[0], end[0]) + wall_thickness / 2,
            max_z=max(start[1], end[1]) + wall_thickness / 2,
        )

        if furniture.overlaps(wall_aabb):
            overlap_x, overlap_z = furniture.overlap_amount(wall_aabb)
            overlap = max(overlap_x, overlap_z)
            label = _wall_direction_label(start, end)
            collisions.append(CollisionDetail(
                type="wall",
                description=f"Overlaps with {label} wall by {overlap:.2f}m",
                overlap_m=round(overlap, 4),
            ))

    return collisions


def _compute_clearance(furniture: AABB, room: AABB) -> dict[str, float]:
    """
    Compute the distance from each furniture edge to the nearest room wall.

    Returns distances in meters for all four directions.
    Useful for the Flutter app to show "breathing room" indicators.
    """
    return {
        "west_m": round(furniture.min_x - room.min_x, 4),
        "east_m": round(room.max_x - furniture.max_x, 4),
        "south_m": round(furniture.min_z - room.min_z, 4),
        "north_m": round(room.max_z - furniture.max_z, 4),
    }


def _generate_suggestion(
    collisions: list[CollisionDetail],
    clearance: dict[str, float],
    category: str = "",
) -> str:
    """
    Generate a concise, non-contradictory suggestion.

    If the product overflows on opposite sides (e.g. both east AND west),
    that means it's physically wider than the room — "move it" makes no sense.
    In that case, suggest a smaller product or bigger room.
    """
    if not collisions:
        return "The furniture fits perfectly!"

    boundary = [c for c in collisions if c.type == "boundary"]
    ceiling = [c for c in collisions if c.type == "ceiling"]

    # Detect opposite-wall overflow (product larger than room on that axis)
    dirs_hit = set()
    for c in boundary:
        for d in ("west", "east", "south", "north"):
            if d in c.description:
                dirs_hit.add(d)

    width_overflow = "west" in dirs_hit and "east" in dirs_hit
    depth_overflow = "south" in dirs_hit and "north" in dirs_hit

    if width_overflow or depth_overflow:
        label = category or "product"
        return (
            f"This {label} is wider/deeper than the room allows. "
            f"Consider a smaller alternative or a larger room."
        )

    suggestions = []
    for c in boundary:
        if c.overlap_m:
            overlap_in = Measurement.meters(c.overlap_m).to(LengthUnit.INCHES)
            if "west" in c.description:
                suggestions.append(f"Move {overlap_in.value:.1f}\" to the right")
            elif "east" in c.description:
                suggestions.append(f"Move {overlap_in.value:.1f}\" to the left")
            elif "south" in c.description:
                suggestions.append(f"Move {overlap_in.value:.1f}\" forward")
            elif "north" in c.description:
                suggestions.append(f"Move {overlap_in.value:.1f}\" backward")

    if ceiling:
        suggestions.append("Choose a shorter piece or check ceiling height")

    if not suggestions:
        suggestions.append("Try repositioning or rotating the furniture")

    # Deduplicate
    seen = set()
    unique = []
    for s in suggestions:
        if s not in seen:
            seen.add(s)
            unique.append(s)

    return "; ".join(unique[:3]) + "."


# ── Design-Aware Helpers ─────────────────────────────────────────────────────

def _check_fill_ratio(fill_ratio: float, product_name: str) -> list[DesignWarning]:
    """Warn when a single piece of furniture occupies too much floor area."""
    warnings = []

    if fill_ratio >= MAX_FILL_RATIO_CRITICAL:
        pct = round(fill_ratio * 100)
        warnings.append(DesignWarning(
            severity="warning",
            category="fill_ratio",
            message=(
                f"'{product_name}' would occupy {pct}% of the floor — "
                f"this leaves almost no usable space"
            ),
        ))
    elif fill_ratio >= MAX_FILL_RATIO_WARNING:
        pct = round(fill_ratio * 100)
        warnings.append(DesignWarning(
            severity="caution",
            category="fill_ratio",
            message=(
                f"'{product_name}' fills {pct}% of the floor — "
                f"consider a smaller alternative for a more open feel"
            ),
        ))

    return warnings


def _get_open_sides(
    clearance: dict[str, float], strategy: str,
) -> dict[str, float]:
    """
    Return only the sides that are expected to be "open" (walkable).

    When furniture is intentionally placed against a wall or in a corner,
    the wall-touching side(s) should not generate warnings — that's the
    whole point of the placement. Only the open/walkable sides matter.

    A side is considered "intentionally flush" if clearance < 15cm AND
    the placement strategy expects wall contact on that side.
    """
    all_sides = {
        "west": clearance.get("west_m", 99),
        "east": clearance.get("east_m", 99),
        "south": clearance.get("south_m", 99),
        "north": clearance.get("north_m", 99),
    }

    if strategy == "center":
        return all_sides

    # For ANY placement (including manual), exclude intentionally flush sides.
    # If a user manually placed furniture against a wall, warning about that
    # wall's clearance is unhelpful — they chose that position deliberately.
    flush_threshold = 0.15
    open_sides = {
        s: d for s, d in all_sides.items() if d >= flush_threshold
    }

    return open_sides if open_sides else all_sides


def _check_clearance_quality(
    clearance: dict[str, float], category: str, strategy: str,
) -> list[DesignWarning]:
    """Warn when walkway space on OPEN sides is too tight."""
    warnings = []
    open_sides = _get_open_sides(clearance, strategy)

    if not open_sides:
        return warnings

    blocked = [s for s, d in open_sides.items() if 0 < d < MIN_WALKWAY_M]
    tight = [
        s for s, d in open_sides.items()
        if MIN_WALKWAY_M <= d < COMFORTABLE_CLEARANCE_M
    ]

    if blocked:
        names = ", ".join(blocked)
        warnings.append(DesignWarning(
            severity="warning",
            category="clearance",
            message=f"Less than 60cm clearance on {names} side(s) — may block walkway",
        ))

    if tight and not blocked:
        names = ", ".join(tight)
        warnings.append(DesignWarning(
            severity="caution",
            category="clearance",
            message=f"Tight clearance on {names} side(s) — consider leaving 90cm for comfort",
        ))

    return warnings


def _check_category_rules(
    clearance: dict[str, float],
    category: str,
    bounding_box: Any,
    strategy: str,
) -> list[DesignWarning]:
    """Category-specific practical spacing rules."""
    warnings = []
    open_sides = _get_open_sides(clearance, strategy)

    if category == "bed":
        # Beds need at least one accessible side for getting in/out
        side_clearances = [
            v for k, v in open_sides.items() if k in ("west", "east")
        ]
        if not side_clearances:
            # Both sides are flush with walls — that's intentional (wall placement)
            # but check if at least one side has 60cm
            all_side = [clearance.get("west_m", 0), clearance.get("east_m", 0)]
            if max(all_side) < BED_SIDE_MIN_M:
                warnings.append(DesignWarning(
                    severity="warning",
                    category="proportion",
                    message="Bed has no accessible side — leave at least 60cm on one side for getting in/out",
                ))
        else:
            accessible = sum(1 for s in side_clearances if s >= BED_SIDE_MIN_M)
            if accessible == 0:
                warnings.append(DesignWarning(
                    severity="caution",
                    category="proportion",
                    message="Open side(s) of bed have tight clearance — aim for 60cm+ for easy access",
                ))

    elif category == "table":
        if open_sides:
            min_open = min(open_sides.values())
            if min_open < TABLE_CHAIR_PULLOUT_M:
                warnings.append(DesignWarning(
                    severity="caution",
                    category="proportion",
                    message="Less than 75cm on open side(s) — chairs may not have pull-out room",
                ))

    elif category == "sofa":
        # Only warn about front clearance if the front side is open
        front = open_sides.get("north", open_sides.get("south"))
        if front is not None and front < COMFORTABLE_CLEARANCE_M:
            warnings.append(DesignWarning(
                severity="caution",
                category="proportion",
                message="Less than 90cm in front of sofa — consider leaving space for a coffee table",
            ))

    return warnings


def _compute_design_score(
    collisions: list[CollisionDetail],
    warnings: list[DesignWarning],
    fill_ratio: float,
    clearance: dict[str, float],
    strategy: str,
) -> int:
    """
    Compute a 0-100 design quality score.

    Placement-aware: intentionally wall-flush sides don't penalize the score.
    """
    score = 100

    score -= len(collisions) * 50

    for w in warnings:
        if w.severity == "warning":
            score -= 15
        else:
            score -= 5

    overfill = max(0, fill_ratio - 0.30)
    score -= int(overfill * 100)

    # Only penalize clearance on open sides
    open_sides = _get_open_sides(clearance, strategy)
    if open_sides:
        min_open = min(open_sides.values())
        if min_open < MIN_WALKWAY_M:
            score -= 5

    return max(0, min(100, score))


# ── Multi-Furniture Layout Check ─────────────────────────────────────────────

async def check_multi_furniture_fit(request: MultiFitCheckRequest) -> MultiFitCheckResponse:
    """
    Check multiple furniture items in the same room, including
    inter-furniture collision detection.
    """
    # Load room
    try:
        room = await Room.get(request.room_id)
    except Exception:
        room = None
    if not room or not room.dimensions:
        raise NotFoundError(message="Room not found or not processed", error_code="ROOM_NOT_FOUND")

    room_w = room.dimensions.get("width_m") or 0
    room_l = room.dimensions.get("length_m") or 0
    room_h = room.dimensions.get("height_m") or 2.5
    room_aabb = _compute_room_aabb(room.dimensions)
    room_floor_area = room_aabb.width * room_aabb.depth

    item_results: list[MultiFitItemResult] = []
    placed_boxes: list[AABB] = []
    placed_names: list[str] = []
    total_footprint = 0.0

    for item in request.items:
        try:
            product = await Product.get(item.product_id)
        except Exception:
            product = None
        if not product:
            item_results.append(MultiFitItemResult(
                product_id=item.product_id,
                product_name="Unknown",
                category="unknown",
                fits=False,
                verdict="too_large",
                collisions=[CollisionDetail(type="size", description="Product not found")],
            ))
            continue

        # Determine placement (avoid already-placed furniture)
        if item.position is not None:
            position = item.position
            strategy_label = "manual"
        else:
            opt_x, opt_z, opt_rot = compute_optimal_position(
                category=product.category,
                tags=product.tags if hasattr(product, "tags") else [],
                furniture_width=product.bounding_box.width_m,
                furniture_depth=product.bounding_box.depth_m,
                furniture_height=product.bounding_box.height_m,
                room_width=room_w,
                room_length=room_l,
                room_height=room_h,
                occupied_boxes=placed_boxes,
            )
            position = PlacementPosition(x=opt_x, z=opt_z, rotation_y=opt_rot)
            strategy_label = determine_strategy(
                product.category,
                product.tags if hasattr(product, "tags") else [],
            ).value

        furn_aabb = _compute_furniture_aabb(
            product.bounding_box.width_m,
            product.bounding_box.depth_m,
            position,
        )

        # Wall/boundary collisions
        collisions: list[CollisionDetail] = []
        collisions.extend(_check_boundary_collisions(furn_aabb, room_aabb))

        wall_segments = room.dimensions.get("wall_segments", [])
        wall_cols = _check_wall_collisions(furn_aabb, wall_segments)
        if strategy_label != "center":
            clearance_raw = _compute_clearance(furn_aabb, room_aabb)
            flush_threshold = 0.15
            flush_sides = {
                s for s, key in [("West", "west_m"), ("East", "east_m"),
                                  ("South", "south_m"), ("North", "north_m")]
                if clearance_raw.get(key, 99) < flush_threshold
            }
            # Only keep wall collisions for non-flush sides
            for wc in wall_cols:
                if not any(side in wc.description for side in flush_sides):
                    collisions.append(wc)
        else:
            collisions.extend(wall_cols)

        if room_h and product.bounding_box.height_m > room_h:
            collisions.append(CollisionDetail(
                type="ceiling",
                description=f"Furniture exceeds ceiling by {product.bounding_box.height_m - room_h:.2f}m",
                overlap_m=round(product.bounding_box.height_m - room_h, 4),
            ))

        # Furniture-to-furniture collisions
        for i, existing_box in enumerate(placed_boxes):
            if furn_aabb.overlaps(existing_box):
                collisions.append(CollisionDetail(
                    type="furniture",
                    description=f"Overlaps with '{placed_names[i]}'",
                    overlap_m=round(max(*furn_aabb.overlap_amount(existing_box)), 4),
                ))

        clearance = _compute_clearance(furn_aabb, room_aabb)
        clearance_display = {k: max(0.0, v) for k, v in clearance.items()}

        furn_area = product.bounding_box.width_m * product.bounding_box.depth_m
        total_footprint += furn_area

        fits = len(collisions) == 0
        too_big = (product.bounding_box.width_m > room_w and product.bounding_box.depth_m > room_l)
        verdict = "fits" if fits else ("too_large" if too_big else "tight_fit")

        warnings: list[DesignWarning] = []
        item_fill = furn_area / room_floor_area if room_floor_area > 0 else 0
        warnings.extend(_check_fill_ratio(item_fill, product.name))
        warnings.extend(_check_clearance_quality(clearance, product.category, strategy_label))

        score = _compute_design_score(collisions, warnings, item_fill, clearance, strategy_label)

        item_results.append(MultiFitItemResult(
            product_id=str(product.id),
            product_name=product.name,
            category=product.category,
            fits=fits,
            verdict=verdict,
            collisions=collisions,
            warnings=warnings,
            design_score=score,
            clearance=clearance_display,
            placement_used={
                "x": round(position.x, 4),
                "z": round(position.z, 4),
                "rotation_y": round(position.rotation_y, 1),
                "strategy": strategy_label,
            },
            furniture_footprint={
                "min_x": round(furn_aabb.min_x, 4),
                "min_z": round(furn_aabb.min_z, 4),
                "max_x": round(furn_aabb.max_x, 4),
                "max_z": round(furn_aabb.max_z, 4),
                "width_m": round(furn_aabb.width, 4),
                "depth_m": round(furn_aabb.depth, 4),
            },
        ))

        placed_boxes.append(furn_aabb)
        placed_names.append(product.name)

    # Combined metrics
    total_fill_pct = round((total_footprint / room_floor_area * 100) if room_floor_area > 0 else 0, 1)
    overall_fits = all(r.fits for r in item_results)
    avg_score = int(sum(r.design_score for r in item_results) / max(len(item_results), 1))

    combined_warnings: list[DesignWarning] = []
    if total_fill_pct > 60:
        combined_warnings.append(DesignWarning(
            severity="warning", category="fill_ratio",
            message=f"Combined furniture fills {total_fill_pct}% of the floor — very crowded",
        ))
    elif total_fill_pct > 40:
        combined_warnings.append(DesignWarning(
            severity="caution", category="fill_ratio",
            message=f"Combined furniture fills {total_fill_pct}% of the floor",
        ))

    # Collect inter-furniture collisions across all items
    inter_collisions = [
        c for r in item_results for c in r.collisions if c.type == "furniture"
    ]

    return MultiFitCheckResponse(
        overall_fits=overall_fits,
        total_fill_percent=total_fill_pct,
        overall_score=avg_score,
        room_dimensions={
            "width_m": round(room_w, 2),
            "length_m": round(room_l, 2),
            "height_m": round(room_h, 2),
        },
        items=item_results,
        inter_collisions=inter_collisions,
        combined_warnings=combined_warnings,
    )
