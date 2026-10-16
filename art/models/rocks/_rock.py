"""Rocks: a sphere pushed in and out by noise, then split along a few planes into the flat
faces of broken stone, fitted to a box and drawn flat-shaded. Every step moves points along
their ray from the centre, so the surface never folds through itself.

Each rock fills the box from -1 to 1 across (X and Z) and from -`half_height` to
`half_height` up, around the origin, so environment/rock.gd can stretch it to any rock's
radius and height. The material is named Rock: the game draws it in kiln's rock texture.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass

from kiln import geometry


@dataclass(frozen=True)
class Rock:
    # Half the rock's height, where its half width is 1: below 1 a slab, above 1 a pillar.
    half_height: float = 1.0
    # How lumpy it is, as a share of its radius.
    lumps: float = 0.18
    # How many flat faces split it, and how deep they cut (a share of its radius).
    cuts: int = 7
    cut_depth: float = 0.16
    # True: a flat top, as a sea stack's.
    flat_top: bool = False
    # 2 starts from a sphere; higher starts from a cylinder with rounded edges (straight sides
    # for pillars, square edges for slabs).
    squareness: float = 2.0
    # How far the faces may tilt from upright, from 0 (all upright, as columnar rock) to 1.
    tilt: float = 0.8
    # How much narrower the top is than the foot, as a share: a sea stack wears thinner.
    taper: float = 0.0
    seed: int = 1


def mesh(rock: Rock) -> geometry.Mesh:
    rng = random.Random(rock.seed)
    vertices, faces = icosphere(3)
    if rock.squareness != 2.0:
        vertices = [_squared(v, rock.squareness) for v in vertices]
    offsets = [tuple(rng.uniform(-50, 50) for _ in range(3)) for _ in range(3)]
    points = []
    for v in vertices:
        lump = sum(_noise(tuple(v[i] * (1.6 * 2 ** o) + offsets[o][i] for i in range(3))) * 0.5 ** o
                   for o in range(3))
        r = 1.0 + lump * rock.lumps
        points.append((v[0] * r, v[1] * r, v[2] * r))
    planes = []
    for _ in range(rock.cuts):
        # Mostly sideways faces, some tilted, so the rock reads as split stone, not a gem.
        yaw = rng.uniform(0, math.tau)
        tilt = rng.uniform(-0.7, 0.9) * rock.tilt
        normal = (math.cos(yaw) * math.cos(tilt), math.sin(tilt), math.sin(yaw) * math.cos(tilt))
        planes.append((normal, 1.0 - rock.cut_depth * rng.uniform(0.6, 1.4)))
    if rock.flat_top:
        planes.append(((0.0, 1.0, 0.0), 1.0 - rock.cut_depth * 1.5))
    # A point beyond a plane moves in along its own ray from the centre to the plane, so the
    # faces come out flat and the rock stays one surface round its centre, with no folds.
    for normal, offset in planes:
        for i, p in enumerate(points):
            d = p[0] * normal[0] + p[1] * normal[1] + p[2] * normal[2]
            if d > offset:
                points[i] = tuple(c * offset / d for c in p)
    if rock.taper:
        bottom = min(p[1] for p in points)
        top = max(p[1] for p in points)
        points = [(p[0] * (1 - rock.taper * (p[1] - bottom) / (top - bottom)), p[1],
                   p[2] * (1 - rock.taper * (p[1] - bottom) / (top - bottom))) for p in points]
    # Fit the box: -1 to 1 across, -half_height to half_height up.
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    half = (1.0, rock.half_height, 1.0)
    fitted = tuple(tuple((p[i] - (low[i] + high[i]) / 2) / ((high[i] - low[i]) / 2) * half[i] for i in range(3))
                   for p in points)
    return geometry.Mesh(fitted, faces).outward()


def build(k, rock: Rock) -> None:
    stone = k.material("Rock", "#8a8378", roughness=0.9)
    k.mesh("Rock", mesh(rock), material=stone)


def icosphere(levels: int) -> tuple[list[tuple[float, float, float]], list[tuple[int, int, int]]]:
    """A unit sphere of triangles: an icosahedron split `levels` times."""
    t = (1 + 5 ** 0.5) / 2
    vertices = [_unit(v) for v in [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t),
                                   (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2),
             (10, 7, 6), (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5),
             (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    for _ in range(levels):
        middles: dict[tuple[int, int], int] = {}

        def middle(a: int, b: int) -> int:
            key = (min(a, b), max(a, b))
            if key not in middles:
                va, vb = vertices[a], vertices[b]
                vertices.append(_unit(((va[0] + vb[0]) / 2, (va[1] + vb[1]) / 2, (va[2] + vb[2]) / 2)))
                middles[key] = len(vertices) - 1
            return middles[key]

        split = []
        for a, b, c in faces:
            ab, bc, ca = middle(a, b), middle(b, c), middle(c, a)
            split += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        faces = split
    return vertices, faces


def _squared(v, power: float):
    """The point in direction `v` on the surface where (horizontal distance)^power +
    |height|^power = 1: a cylinder with rounded edges for a high power."""
    across = math.hypot(v[0], v[2])
    t = (across ** power + abs(v[1]) ** power) ** (-1 / power)
    return (v[0] * t, v[1] * t, v[2] * t)


def _unit(v):
    n = math.sqrt(v[0] ** 2 + v[1] ** 2 + v[2] ** 2)
    return (v[0] / n, v[1] / n, v[2] / n)


def _hash(x: int, y: int, z: int) -> float:
    h = (x * 374761393 + y * 668265263 + z * 2147483647) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 32767.5 - 1.0


def _noise(p) -> float:
    """Smooth value noise from -1 to 1."""
    cell = [math.floor(c) for c in p]
    f = [c - math.floor(c) for c in p]
    s = [t * t * (3 - 2 * t) for t in f]
    total = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (s[0] if dx else 1 - s[0]) * (s[1] if dy else 1 - s[1]) * (s[2] if dz else 1 - s[2])
                total += w * _hash(cell[0] + dx, cell[1] + dy, cell[2] + dz)
    return total
