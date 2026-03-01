"""
DesignMirror AI — Unit Safety Module
======================================

MENTOR MOMENT: Why a dedicated Unit class?
──────────────────────────────────────────
In 1999, NASA lost a $125 million Mars orbiter because one team used
metric units and another used imperial. The software didn't crash —
it just silently gave wrong answers.

In DesignMirror, we deal with room dimensions and furniture sizes.
If a sofa is "72 inches" and a wall is "1.8 meters", a naive comparison
(72 > 1.8 → "it fits!") would be catastrophically wrong.

This module prevents that by:
  1. Wrapping every measurement in a `Measurement` class that knows its unit.
  2. Automatically converting to a common unit (meters) for all comparisons.
  3. Raising errors if you try to mix incompatible measurements.

PATTERN: Value Object
────────────────────
A Value Object is an immutable object defined by its value, not its identity.
Two Measurements of "6 feet" are equal, regardless of when they were created.
This is the same pattern used for `datetime`, `Decimal`, etc.
"""

from __future__ import annotations

from enum import Enum
from typing import Union


class LengthUnit(str, Enum):
    """Supported length units."""
    METERS = "m"
    FEET = "ft"
    INCHES = "in"
    CENTIMETERS = "cm"


# Conversion factors TO meters (our canonical unit)
_TO_METERS: dict[LengthUnit, float] = {
    LengthUnit.METERS: 1.0,
    LengthUnit.FEET: 0.3048,
    LengthUnit.INCHES: 0.0254,
    LengthUnit.CENTIMETERS: 0.01,
}


class Measurement:
    """
    A type-safe length measurement.

    Usage:
        >>> sofa_width = Measurement(72, LengthUnit.INCHES)
        >>> wall_width = Measurement(1.8, LengthUnit.METERS)
        >>> sofa_width.to(LengthUnit.METERS)
        Measurement(1.8288, LengthUnit.METERS)
        >>> sofa_width <= wall_width
        True  # 72 inches (1.83m) fits in 1.8m wall? Actually False!
        >>> sofa_width > wall_width
        True  # Correct — 72" = 1.83m > 1.8m
    """

    __slots__ = ("_value", "_unit")

    def __init__(self, value: Union[int, float], unit: LengthUnit) -> None:
        if value < 0:
            raise ValueError(f"Measurement cannot be negative: {value}")
        self._value = float(value)
        self._unit = unit

    # ── Properties ─────────────────────────────

    @property
    def value(self) -> float:
        """The numeric value in the original unit."""
        return self._value

    @property
    def unit(self) -> LengthUnit:
        """The unit of measurement."""
        return self._unit

    # ── Conversion ─────────────────────────────

    def to_meters(self) -> float:
        """Convert to meters (our canonical comparison unit)."""
        return self._value * _TO_METERS[self._unit]

    def to(self, target_unit: LengthUnit) -> Measurement:
        """
        Convert this measurement to a different unit.

        HOW IT WORKS:
          1. Convert current value → meters (using _TO_METERS)
          2. Convert meters → target unit (dividing by target's factor)
        """
        meters = self.to_meters()
        target_value = meters / _TO_METERS[target_unit]
        return Measurement(target_value, target_unit)

    # ── Comparison Operators ───────────────────
    # All comparisons convert to meters first, ensuring apples-to-apples.

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Measurement):
            return NotImplemented
        return abs(self.to_meters() - other.to_meters()) < 1e-9

    def __lt__(self, other: Measurement) -> bool:
        return self.to_meters() < other.to_meters()

    def __le__(self, other: Measurement) -> bool:
        return self.to_meters() <= other.to_meters()

    def __gt__(self, other: Measurement) -> bool:
        return self.to_meters() > other.to_meters()

    def __ge__(self, other: Measurement) -> bool:
        return self.to_meters() >= other.to_meters()

    # ── Arithmetic ─────────────────────────────

    def __add__(self, other: Measurement) -> Measurement:
        """Add two measurements (result in meters)."""
        total_meters = self.to_meters() + other.to_meters()
        return Measurement(total_meters, LengthUnit.METERS)

    def __sub__(self, other: Measurement) -> Measurement:
        """Subtract two measurements (result in meters)."""
        diff_meters = self.to_meters() - other.to_meters()
        if diff_meters < 0:
            raise ValueError(
                f"Subtraction would result in negative measurement: "
                f"{self} - {other} = {diff_meters:.4f}m"
            )
        return Measurement(diff_meters, LengthUnit.METERS)

    # ── Display ────────────────────────────────

    def __repr__(self) -> str:
        return f"Measurement({self._value:.4f}, {self._unit.value})"

    def __str__(self) -> str:
        return f"{self._value:.2f} {self._unit.value}"

    # ── Factory Methods ────────────────────────

    @classmethod
    def feet(cls, value: float) -> Measurement:
        """Shorthand: Measurement.feet(6)"""
        return cls(value, LengthUnit.FEET)

    @classmethod
    def inches(cls, value: float) -> Measurement:
        """Shorthand: Measurement.inches(72)"""
        return cls(value, LengthUnit.INCHES)

    @classmethod
    def meters(cls, value: float) -> Measurement:
        """Shorthand: Measurement.meters(1.8)"""
        return cls(value, LengthUnit.METERS)

    @classmethod
    def cm(cls, value: float) -> Measurement:
        """Shorthand: Measurement.cm(180)"""
        return cls(value, LengthUnit.CENTIMETERS)

