"""
DesignMirror AI — Coordinate Transformation Service
=====================================================

MENTOR MOMENT: What is Coordinate Transformation?
──────────────────────────────────────────────────
When the phone scans a room, ARKit/ARCore gives us 3D coordinates in its
own coordinate system — where (0,0,0) is wherever the phone was when scanning
started, and 1 unit = 1 meter.

The problem: these coordinates are RELATIVE to the phone's starting position,
not to the room itself. If you start scanning from the center of the room,
the corner of the room might be at (-2.1, 0, -1.5).

This service transforms those AR coordinates into meaningful real-world
measurements:
  • Room width, length, height (in meters)
  • Floor area (m²)
  • Volume (m³)
  • Wall segments with actual lengths

HOW THE MATH WORKS:
───────────────────
1. We take the measurement points (user-tapped room corners) in 3D space.
2. We project them onto the floor plane (ignore Y axis for 2D floor plan).
3. We compute the bounding box (min/max X and Z coordinates).
4. The difference between max and min gives us width and length.
5. For height, we look at wall planes or ceiling planes.
6. We compute wall segments by connecting consecutive corner points.

This is "Geometric AI" — not deep learning, but computational geometry
that gives precise, deterministic results.
"""

import math
from typing import Any

from app.core.logging import logger
from app.services.unit_safety import LengthUnit, Measurement


def transform_scan_to_dimensions(
    planes: list[dict[str, Any]],
    measurement_points: list[dict[str, Any]],
    device_info: dict[str, Any],
) -> dict[str, Any]:
    """
    Transform raw AR scan data into real-world room dimensions.

    This is the core of the "Precision Engine" — it takes raw AR coordinates
    and produces actionable measurements that the Fit-Check algorithm can use.

    Args:
        planes: List of detected AR planes (with center, extent, transform).
        measurement_points: List of user-tapped 3D points (x, y, z, label).
        device_info: Device capabilities (has_lidar, tracking_quality).

    Returns:
        A dimensions dict:
        {
            "width_m": float,
            "length_m": float,
            "height_m": float | None,
            "area_m2": float,
            "volume_m3": float | None,
            "wall_segments": [{start, end, length_m}, ...],
            "confidence": str,      # "high" (LiDAR) or "medium" (camera only)
            "unit_conversions": {    # Convenience for the Flutter app
                "width_ft": float,
                "length_ft": float,
                ...
            }
        }
    """
    logger.info(
        "Transforming scan: {} planes, {} measurement points",
        len(planes),
        len(measurement_points),
    )

    # ── Step 1: Extract 2D floor coordinates ──────────────────────────────
    # Project measurement points onto the XZ plane (floor plan view).
    # In AR coordinate space: X = left/right, Y = up/down, Z = forward/back.
    floor_points = _extract_floor_points(measurement_points)

    if len(floor_points) < 3:
        logger.warning("Fewer than 3 valid floor points — cannot compute dimensions")
        return {
            "width_m": 0,
            "length_m": 0,
            "height_m": None,
            "area_m2": 0,
            "volume_m3": None,
            "wall_segments": [],
            "confidence": "low",
            "unit_conversions": {},
        }

    # ── Step 2: Compute bounding box dimensions ──────────────────────────
    width_m, length_m = _compute_bounding_box(floor_points)

    # ── Step 3: Estimate room height from planes ─────────────────────────
    height_m = _estimate_height(planes)

    # ── Step 4: Calculate area and volume ─────────────────────────────────
    # Use the Shoelace formula for polygon area (more accurate than bounding box)
    area_m2 = _compute_polygon_area(floor_points)
    volume_m3 = area_m2 * height_m if height_m else None

    # ── Step 5: Build wall segments ──────────────────────────────────────
    wall_segments = _build_wall_segments(floor_points)

    # ── Step 6: Unit conversions using our Unit Safety module ────────────
    unit_conversions = _build_unit_conversions(width_m, length_m, height_m, area_m2)

    # ── Step 7: Assess confidence ────────────────────────────────────────
    confidence = "high" if device_info.get("has_lidar") else "medium"
    if device_info.get("tracking_quality") == "limited":
        confidence = "low"

    dimensions = {
        "width_m": round(width_m, 4),
        "length_m": round(length_m, 4),
        "height_m": round(height_m, 4) if height_m else None,
        "area_m2": round(area_m2, 4),
        "volume_m3": round(volume_m3, 4) if volume_m3 else None,
        "wall_segments": wall_segments,
        "confidence": confidence,
        "unit_conversions": unit_conversions,
    }

    logger.info(
        "Room dimensions computed: {:.2f}m × {:.2f}m, area={:.2f}m², confidence={}",
        width_m,
        length_m,
        area_m2,
        confidence,
    )

    return dimensions


# ── Internal Helper Functions ──────────────────────────────────────────────────


def _extract_floor_points(
    measurement_points: list[dict[str, Any]],
) -> list[tuple[float, float]]:
    """
    Extract 2D floor coordinates from 3D measurement points.

    We take the X and Z coordinates (ignoring Y / vertical axis)
    to create a 2D floor plan view.
    """
    floor_points: list[tuple[float, float]] = []
    for point in measurement_points:
        x = float(point.get("x", 0))
        z = float(point.get("z", 0))
        floor_points.append((x, z))
    return floor_points


def _compute_bounding_box(
    floor_points: list[tuple[float, float]],
) -> tuple[float, float]:
    """
    Compute the bounding box width and length from 2D floor points.

    This gives the maximum extent of the room in each direction.
    """
    xs = [p[0] for p in floor_points]
    zs = [p[1] for p in floor_points]

    width = max(xs) - min(xs)
    length = max(zs) - min(zs)

    return abs(width), abs(length)


def _estimate_height(planes: list[dict[str, Any]]) -> float | None:
    """
    Estimate room height from detected planes.

    Strategy:
    1. Find the floor plane (lowest horizontal plane).
    2. Find the ceiling plane (highest horizontal plane).
    3. Height = ceiling.y - floor.y

    If no ceiling is detected, try using wall planes' vertical extent.
    If nothing works, return None.
    """
    floor_y = None
    ceiling_y = None

    for plane in planes:
        plane_type = plane.get("type", "unknown")
        center = plane.get("center", {})
        y = center.get("y", 0)

        if plane_type == "floor":
            if floor_y is None or y < floor_y:
                floor_y = y
        elif plane_type == "ceiling":
            if ceiling_y is None or y > ceiling_y:
                ceiling_y = y

    # If we found both floor and ceiling, compute height
    if floor_y is not None and ceiling_y is not None:
        height = abs(ceiling_y - floor_y)
        if height > 0.5:  # Sanity check: rooms are at least 0.5m tall
            return height

    # Fallback: look for wall planes and use their vertical extent
    for plane in planes:
        if plane.get("type") == "wall":
            extent = plane.get("extent", {})
            wall_height = extent.get("height", 0)
            if wall_height > 1.0:  # Walls should be at least 1m
                return wall_height

    # No height data available
    return None


def _compute_polygon_area(floor_points: list[tuple[float, float]]) -> float:
    """
    Compute the area of a polygon using the Shoelace formula.

    MENTOR MOMENT: The Shoelace Formula
    ───────────────────────────────────
    For a polygon with vertices (x1,y1), (x2,y2), ..., (xn,yn):
        Area = 0.5 * |Σ(xi * yi+1 - xi+1 * yi)|

    It's called "Shoelace" because if you write the coordinates in two
    columns and cross-multiply diagonally, it looks like a shoelace pattern.

    This works for ANY polygon shape (not just rectangles), which is
    important because real rooms are rarely perfect rectangles.
    """
    n = len(floor_points)
    if n < 3:
        return 0.0

    area = 0.0
    for i in range(n):
        j = (i + 1) % n
        area += floor_points[i][0] * floor_points[j][1]
        area -= floor_points[j][0] * floor_points[i][1]

    return abs(area) / 2.0


def _build_wall_segments(
    floor_points: list[tuple[float, float]],
) -> list[dict[str, Any]]:
    """
    Build wall segments by connecting consecutive floor corner points.

    Each segment represents a wall with a start point, end point, and length.
    """
    segments = []
    n = len(floor_points)

    for i in range(n):
        j = (i + 1) % n  # Connect last point back to first
        start = floor_points[i]
        end = floor_points[j]

        # Euclidean distance in 2D
        length = math.sqrt(
            (end[0] - start[0]) ** 2 + (end[1] - start[1]) ** 2
        )

        # Use Unit Safety for conversions
        length_measurement = Measurement.meters(length)

        segments.append({
            "start": list(start),
            "end": list(end),
            "length_m": round(length, 4),
            "length_ft": round(length_measurement.to(LengthUnit.FEET).value, 4),
            "length_in": round(length_measurement.to(LengthUnit.INCHES).value, 4),
        })

    return segments


def _build_unit_conversions(
    width_m: float,
    length_m: float,
    height_m: float | None,
    area_m2: float,
) -> dict[str, float]:
    """
    Build a convenience dict with measurements in multiple units.

    Uses the Unit Safety module to prevent conversion errors.
    """
    width = Measurement.meters(width_m)
    length = Measurement.meters(length_m)

    conversions = {
        "width_ft": round(width.to(LengthUnit.FEET).value, 2),
        "width_in": round(width.to(LengthUnit.INCHES).value, 2),
        "length_ft": round(length.to(LengthUnit.FEET).value, 2),
        "length_in": round(length.to(LengthUnit.INCHES).value, 2),
        "area_ft2": round(area_m2 * 10.7639, 2),  # 1 m² = 10.7639 ft²
    }

    if height_m is not None:
        height = Measurement.meters(height_m)
        conversions["height_ft"] = round(height.to(LengthUnit.FEET).value, 2)
        conversions["height_in"] = round(height.to(LengthUnit.INCHES).value, 2)

    return conversions

