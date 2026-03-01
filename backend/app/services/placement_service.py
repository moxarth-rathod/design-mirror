"""
DesignMirror AI — Smart Placement Engine
==========================================

Automatically determines the optimal position for furniture in a room
based on the product's category, tags, and dimensions.

The engine uses interior-design heuristics:
  - Beds → against the longest wall, centered
  - Sofas → against a wall, facing the room center
  - Tables → centered in the room
  - Lighting → corners or beside other furniture
  - Storage → against a wall
  - Rugs → centered on the floor

When multiple candidate positions exist, the engine scores each one
and picks the best. This is extensible: adding new categories or tags
automatically inherits sensible defaults.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import Any

from app.core.logging import logger


class PlacementStrategy(str, Enum):
    CENTER = "center"
    AGAINST_WALL = "against_wall"
    CORNER = "corner"
    NEAR_WALL = "near_wall"


# ── Category → Strategy mapping ──────────────────────────────────────────────
# New categories automatically fall back to AGAINST_WALL (the safest default).

_CATEGORY_STRATEGY: dict[str, PlacementStrategy] = {
    "sofa": PlacementStrategy.AGAINST_WALL,
    "bed": PlacementStrategy.AGAINST_WALL,
    "table": PlacementStrategy.CENTER,
    "chair": PlacementStrategy.CENTER,
    "lighting": PlacementStrategy.CORNER,
    "storage": PlacementStrategy.AGAINST_WALL,
    "rug": PlacementStrategy.CENTER,
    "desk": PlacementStrategy.AGAINST_WALL,
    "dresser": PlacementStrategy.AGAINST_WALL,
    "wardrobe": PlacementStrategy.AGAINST_WALL,
    "mirror": PlacementStrategy.AGAINST_WALL,
    "plant": PlacementStrategy.CORNER,
    "decor": PlacementStrategy.NEAR_WALL,
}

# Tags that override or refine the category default
_TAG_OVERRIDES: dict[str, PlacementStrategy] = {
    "corner": PlacementStrategy.CORNER,
    "center": PlacementStrategy.CENTER,
    "wall-mounted": PlacementStrategy.AGAINST_WALL,
    "freestanding": PlacementStrategy.CENTER,
    "accent": PlacementStrategy.CORNER,
    "floor": PlacementStrategy.CORNER,
    "bedroom": PlacementStrategy.CORNER,
    "small-space": PlacementStrategy.CORNER,
    "bedside": PlacementStrategy.CORNER,
}

# Which wall to prefer for AGAINST_WALL by category
# "longest" = the longest wall, "short" = the shortest wall
_WALL_PREFERENCE: dict[str, str] = {
    "bed": "longest",
    "sofa": "longest",
    "storage": "any",
    "desk": "short",
}

# Margin from the wall (gap so it's not literally inside the wall)
_WALL_MARGIN_M = 0.05


@dataclass
class CandidatePosition:
    x: float
    z: float
    rotation_y: float
    label: str
    score: float = 0.0


def determine_strategy(category: str, tags: list[str]) -> PlacementStrategy:
    """Derive the best placement strategy from category and tags."""
    for tag in tags:
        tag_lower = tag.lower()
        if tag_lower in _TAG_OVERRIDES:
            return _TAG_OVERRIDES[tag_lower]

    return _CATEGORY_STRATEGY.get(
        category.lower(), PlacementStrategy.AGAINST_WALL
    )


def compute_optimal_position(
    category: str,
    tags: list[str],
    furniture_width: float,
    furniture_depth: float,
    furniture_height: float,
    room_width: float,
    room_length: float,
    room_height: float | None = None,
    occupied_boxes: list[Any] | None = None,
) -> tuple[float, float, float]:
    """
    Compute the optimal (x, z, rotation_y) for a piece of furniture.

    Room is centered at origin:
      x: [-room_width/2, +room_width/2]
      z: [-room_length/2, +room_length/2]

    Returns (x, z, rotation_y) in the room coordinate system.
    """
    strategy = determine_strategy(category, tags)

    logger.debug(
        "Placement: category='{}' strategy={} furniture={}×{}m room={}×{}m",
        category, strategy.value, furniture_width, furniture_depth,
        room_width, room_length,
    )

    half_rw = room_width / 2
    half_rl = room_length / 2

    candidates: list[CandidatePosition] = []

    if strategy == PlacementStrategy.CENTER:
        candidates = _center_candidates(
            furniture_width, furniture_depth, half_rw, half_rl
        )
    elif strategy == PlacementStrategy.AGAINST_WALL:
        candidates = _wall_candidates(
            category, furniture_width, furniture_depth, half_rw, half_rl
        )
    elif strategy == PlacementStrategy.CORNER:
        candidates = _corner_candidates(
            furniture_width, furniture_depth, half_rw, half_rl
        )
    elif strategy == PlacementStrategy.NEAR_WALL:
        candidates = _near_wall_candidates(
            furniture_width, furniture_depth, half_rw, half_rl
        )

    if not candidates:
        return (0.0, 0.0, 0.0)

    # Score each candidate
    for c in candidates:
        c.score = _score_position(
            c, furniture_width, furniture_depth, half_rw, half_rl,
            occupied_boxes=occupied_boxes,
        )

    best = max(candidates, key=lambda c: c.score)

    logger.info(
        "Placement result: {} at ({:.2f}, {:.2f}) rot={:.0f}° score={:.1f}",
        best.label, best.x, best.z, best.rotation_y, best.score,
    )

    return (round(best.x, 4), round(best.z, 4), round(best.rotation_y, 1))


# ── Candidate generators ─────────────────────────────────────────────────────

def _center_candidates(
    fw: float, fd: float, hrw: float, hrl: float,
) -> list[CandidatePosition]:
    """Place at room center (tables, rugs, chairs)."""
    return [
        CandidatePosition(0, 0, 0, "center"),
        CandidatePosition(0, 0, 90, "center-rotated"),
    ]


def _wall_candidates(
    category: str, fw: float, fd: float, hrw: float, hrl: float,
) -> list[CandidatePosition]:
    """
    Generate positions against each wall, centered along the wall.
    The furniture's depth face is flush with the wall.
    """
    margin = _WALL_MARGIN_M
    candidates = []

    # North wall (z = +hrl): furniture depth goes toward -z
    z_n = hrl - fd / 2 - margin
    candidates.append(CandidatePosition(0, z_n, 0, "north-wall"))

    # South wall (z = -hrl): furniture depth goes toward +z
    z_s = -hrl + fd / 2 + margin
    candidates.append(CandidatePosition(0, z_s, 180, "south-wall"))

    # East wall (x = +hrw): rotate 90°, width becomes depth axis
    x_e = hrw - fd / 2 - margin
    candidates.append(CandidatePosition(x_e, 0, 90, "east-wall"))

    # West wall (x = -hrw): rotate 270°
    x_w = -hrw + fd / 2 + margin
    candidates.append(CandidatePosition(x_w, 0, 270, "west-wall"))

    # Prefer longest wall for beds and sofas
    pref = _WALL_PREFERENCE.get(category.lower(), "any")
    if pref == "longest":
        room_w = hrw * 2
        room_l = hrl * 2
        if room_w >= room_l:
            for c in candidates:
                if "north" in c.label or "south" in c.label:
                    c.score += 20
        else:
            for c in candidates:
                if "east" in c.label or "west" in c.label:
                    c.score += 20
    elif pref == "short":
        room_w = hrw * 2
        room_l = hrl * 2
        if room_w < room_l:
            for c in candidates:
                if "north" in c.label or "south" in c.label:
                    c.score += 20
        else:
            for c in candidates:
                if "east" in c.label or "west" in c.label:
                    c.score += 20

    return candidates


def _corner_candidates(
    fw: float, fd: float, hrw: float, hrl: float,
) -> list[CandidatePosition]:
    """Place in each of the four corners (lamps, nightstands, plants)."""
    margin = _WALL_MARGIN_M
    hfw = fw / 2
    hfd = fd / 2
    candidates = []

    corners = [
        ("sw-corner", -hrw + hfw + margin, -hrl + hfd + margin),
        ("se-corner",  hrw - hfw - margin, -hrl + hfd + margin),
        ("nw-corner", -hrw + hfw + margin,  hrl - hfd - margin),
        ("ne-corner",  hrw - hfw - margin,  hrl - hfd - margin),
    ]

    for label, x, z in corners:
        candidates.append(CandidatePosition(x, z, 0, label))

    return candidates


def _near_wall_candidates(
    fw: float, fd: float, hrw: float, hrl: float,
) -> list[CandidatePosition]:
    """Place near a wall but with some breathing room (decor, accents)."""
    margin = 0.3
    candidates = []

    z_n = hrl - fd / 2 - margin
    candidates.append(CandidatePosition(0, z_n, 0, "near-north"))

    z_s = -hrl + fd / 2 + margin
    candidates.append(CandidatePosition(0, z_s, 0, "near-south"))

    return candidates


# ── Scoring ──────────────────────────────────────────────────────────────────

def _score_position(
    c: CandidatePosition,
    fw: float, fd: float,
    hrw: float, hrl: float,
    occupied_boxes: list[Any] | None = None,
) -> float:
    """
    Score a candidate position (higher = better).

    Factors:
      - Does furniture fit within room? (hard requirement)
      - Clearance on walkway sides
      - Balance (centered along the wall is better than off-center)
      - No overlap with already-placed furniture
    """
    score = c.score  # start with any bonus from wall preference

    rot_rad = math.radians(c.rotation_y)
    cos_a = abs(math.cos(rot_rad))
    sin_a = abs(math.sin(rot_rad))
    eff_hw = (fw * cos_a + fd * sin_a) / 2
    eff_hd = (fw * sin_a + fd * cos_a) / 2

    min_x = c.x - eff_hw
    max_x = c.x + eff_hw
    min_z = c.z - eff_hd
    max_z = c.z + eff_hd

    # Penalty: outside room boundaries
    if min_x < -hrw or max_x > hrw or min_z < -hrl or max_z > hrl:
        score -= 100

    # Clearance on all sides
    cl_w = min_x - (-hrw)
    cl_e = hrw - max_x
    cl_s = min_z - (-hrl)
    cl_n = hrl - max_z

    min_cl = min(cl_w, cl_e, cl_s, cl_n)

    # Reward having at least walkway clearance on open sides
    walkable_sides = sum(1 for cl in [cl_w, cl_e, cl_s, cl_n] if cl >= 0.6)
    score += walkable_sides * 10

    # Reward balance: being centered along the wall
    x_balance = 1.0 - abs(c.x) / max(hrw, 0.1)
    z_balance = 1.0 - abs(c.z) / max(hrl, 0.1)
    score += (x_balance + z_balance) * 5

    # Penalize if minimum clearance is too tight (unless it's a wall-flush position)
    if min_cl < 0:
        score -= 50
    elif min_cl < 0.3:
        score += 5  # tight but okay for wall-flush

    # Penalize overlap with already-placed furniture (multi-layout mode)
    if occupied_boxes:
        for occ in occupied_boxes:
            # occ is an AABB-like object with min_x, min_z, max_x, max_z
            overlap_x = min(max_x, occ.max_x) - max(min_x, occ.min_x)
            overlap_z = min(max_z, occ.max_z) - max(min_z, occ.min_z)
            if overlap_x > 0 and overlap_z > 0:
                score -= 200  # hard penalty for furniture-furniture collision

    return score
