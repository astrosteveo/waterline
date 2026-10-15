"""Meshes as plain data, and the shapes kiln builds them from.

Everything here is plain Python, so it runs and is tested without Blender. Coordinates are in
game space (metres, +Y up, -Z forward). `kiln.blender.Kit` turns a `Mesh` into a Blender
object.
"""
from __future__ import annotations

import math
from collections import Counter
from dataclasses import dataclass
from typing import Iterable, Sequence

Vec3 = tuple[float, float, float]


@dataclass(frozen=True)
class Mesh:
    """Vertices and faces. Each face lists vertex indices counter-clockwise seen from outside."""

    vertices: tuple[Vec3, ...]
    faces: tuple[tuple[int, ...], ...]

    def triangle_count(self) -> int:
        """Triangles once every face is split into a fan."""
        return sum(len(face) - 2 for face in self.faces)

    def bounds(self) -> tuple[Vec3, Vec3]:
        """The lowest and highest corner of the bounding box."""
        xs, ys, zs = zip(*self.vertices)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def signed_volume(self) -> float:
        """The enclosed volume, positive when the faces point outward. Only meaningful for a
        closed mesh."""
        total = 0.0
        for face in self.faces:
            a = self.vertices[face[0]]
            for i in range(1, len(face) - 1):
                b, c = self.vertices[face[i]], self.vertices[face[i + 1]]
                total += _dot(a, _cross(b, c))
        return total / 6.0

    def open_edges(self) -> list[tuple[int, int]]:
        """Edges not shared by exactly two faces: empty for a closed mesh."""
        counts = Counter(_edge(face[i], face[(i + 1) % len(face)])
                         for face in self.faces for i in range(len(face)))
        return sorted(edge for edge, count in counts.items() if count != 2)

    def inconsistent_edges(self) -> list[tuple[int, int]]:
        """Edges two faces run the same way, where one face is turned the other way from its
        neighbour: empty when the faces agree."""
        counts = Counter((face[i], face[(i + 1) % len(face)])
                         for face in self.faces for i in range(len(face)))
        return sorted(edge for edge, count in counts.items() if count > 1)

    def flipped(self) -> "Mesh":
        """The same mesh with every face turned the other way."""
        return Mesh(self.vertices, tuple(tuple(reversed(face)) for face in self.faces))

    def outward(self) -> "Mesh":
        """The mesh with its faces turned outward, judged by the sign of its volume."""
        return self.flipped() if self.signed_volume() < 0 else self

    def translated(self, offset: Vec3) -> "Mesh":
        return Mesh(tuple(_add(v, offset) for v in self.vertices), self.faces)

    def scaled(self, factor: Vec3) -> "Mesh":
        """Scaled per axis. A negative factor mirrors the mesh, and its faces are turned back
        outward."""
        mesh = Mesh(tuple((v[0] * factor[0], v[1] * factor[1], v[2] * factor[2])
                          for v in self.vertices), self.faces)
        return mesh.flipped() if factor[0] * factor[1] * factor[2] < 0 else mesh

    def merged(self, other: "Mesh") -> "Mesh":
        """Both meshes as one (their vertices aren't joined)."""
        shift = len(self.vertices)
        return Mesh(self.vertices + other.vertices,
                    self.faces + tuple(tuple(i + shift for i in face) for face in other.faces))


def box(size: Vec3, center: Vec3 = (0.0, 0.0, 0.0)) -> Mesh:
    """A box of `size` around `center`."""
    hx, hy, hz = (s / 2 for s in size)
    vertices = tuple(_add(center, (sx * hx, sy * hy, sz * hz))
                     for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1))
    # Index = 4 * (x > 0) + 2 * (y > 0) + (z > 0).
    faces = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))
    return Mesh(vertices, faces).outward()


def loft(sections: Sequence[Sequence[Vec3]], caps: bool = True) -> Mesh:
    """A surface through closed rings of points, each joined to the next with quads.

    Every ring has the same number of points, in the same order around it. With `caps`, the
    first and last ring are closed with a fan around their centre, so the mesh is closed;
    a ring of one point is a tip and needs no cap. The faces are turned outward.
    """
    if len(sections) < 2:
        raise ValueError("loft needs at least two sections")
    count = max(len(ring) for ring in sections)
    if any(len(ring) not in (1, count) for ring in sections) or count < 3:
        raise ValueError("loft sections need the same number of points (3 or more), or one for a tip")
    vertices: list[Vec3] = []
    starts: list[int] = []
    for ring in sections:
        starts.append(len(vertices))
        vertices.extend(tuple(map(float, p)) for p in ring)
    faces: list[tuple[int, ...]] = []
    for k in range(len(sections) - 1):
        a, b = starts[k], starts[k + 1]
        a_tip, b_tip = len(sections[k]) == 1, len(sections[k + 1]) == 1
        if a_tip and b_tip:
            raise ValueError("loft can't join two tips")
        for i in range(count):
            j = (i + 1) % count
            if a_tip:
                faces.append((a, b + j, b + i))
            elif b_tip:
                faces.append((a + i, a + j, b))
            else:
                faces.append((a + i, a + j, b + j, b + i))
    if caps:
        for k in (0, len(sections) - 1):
            if len(sections[k]) == count:
                c = len(vertices)
                vertices.append(_centroid(sections[k]))
                s = starts[k]
                # Each cap runs its ring's edges the other way from the side faces next to it.
                if k == 0:
                    faces.extend((c, s + (i + 1) % count, s + i) for i in range(count))
                else:
                    faces.extend((c, s + i, s + (i + 1) % count) for i in range(count))
    return Mesh(tuple(vertices), tuple(faces)).outward()


def lathe(profile: Sequence[tuple[float, float]], segments: int = 16) -> Mesh:
    """A solid of revolution about the Y axis from (radius, height) points, bottom to top.

    A point with radius 0 is a pole, so a profile from (0, y0) to (0, y1) makes a closed
    mesh. Otherwise the open ends are capped.
    """
    if segments < 3:
        raise ValueError("lathe needs at least 3 segments")
    sections = []
    for radius, height in profile:
        if radius <= 0:
            sections.append([(0.0, float(height), 0.0)])
        else:
            sections.append([(radius * math.cos(a), float(height), -radius * math.sin(a))
                             for a in (math.tau * i / segments for i in range(segments))])
    return loft(sections)


def ring(points: Iterable[tuple[float, float]], z: float) -> list[Vec3]:
    """A loft section in the plane at `z` from (x, y) points."""
    return [(float(x), float(y), float(z)) for x, y in points]


def mirrored_ring(half: Sequence[tuple[float, float]], z: float) -> list[Vec3]:
    """A loft section symmetric about x = 0 from the points of its right half (x >= 0),
    listed from the bottom centre up to the top centre. Points on the centre line aren't
    repeated."""
    left = [(-x, y) for x, y in reversed(half) if x != 0]
    return ring(list(half) + left, z)


def _edge(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


def _add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _centroid(points: Sequence[Vec3]) -> Vec3:
    n = len(points)
    return (sum(p[0] for p in points) / n, sum(p[1] for p in points) / n, sum(p[2] for p in points) / n)
