"""Turning game space (+Y up, -Z forward, as Godot) into Blender's space (+Z up) and back.

The glTF exporter turns Blender's +Z up into glTF's +Y up as (x, y, z) -> (x, z, -y), so
building in Blender at (x, -z, y) exports exactly the game-space coordinates a recipe gave.
"""
from __future__ import annotations

import math

from mathutils import Euler, Matrix, Vector

# Game space to Blender space, a rotation of 90 degrees about X.
TO_BLENDER = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
TO_GAME = TO_BLENDER.transposed()


def to_blender(p) -> Vector:
    return Vector((p[0], -p[2], p[1]))


def to_game(p) -> tuple[float, float, float]:
    return (p[0], p[2], -p[1])


def rotation_to_blender(degrees) -> Matrix:
    """A game-space rotation given as Euler angles in degrees, applied as Godot applies them
    (Z, then X, then Y), as a Blender-space rotation matrix."""
    x, y, z = (math.radians(d) for d in degrees)
    # Blender names an order by the axis applied first: "ZXY" is Godot's YXZ (Y * X * Z).
    game = Euler((x, y, z), "ZXY").to_matrix()
    return TO_BLENDER @ game @ TO_GAME
