"""Meshes as plain data, and the shapes kiln builds them from.

Everything here is plain Python, so it runs and is tested without Blender. Coordinates are in
game space (metres, +Y up, -Z forward). `kiln.blender.Kit` turns a `Mesh` into a Blender
object.

UVs are in metres along the surface, so a texture that tiles every metre of UV keeps its size
on every model (a texture `tile` metres across is drawn at a UV scale of 1 / `tile`). Each
shape gives its own: a box projected onto each face, a loft or lathe round its rings and along
them. A mesh made from bare vertices and faces has none until `projected` gives it some, and
`kiln.blender.Kit.mesh` projects any mesh that has none. A face's UVs run counter-clockwise
seen from outside, as its corners do, so a texture reads the right way round.
"""
from __future__ import annotations

import math
from collections import Counter
from dataclasses import dataclass
from typing import Iterable, Sequence

Vec3 = tuple[float, float, float]
UV = tuple[float, float]

# The directions u and v run across a face, by the axis and side it faces most (box mapping).
# Seen from outside, u runs to the right and v up; on the top and bottom, v runs forward (-Z).
_PROJECTIONS: dict[tuple[int, bool], tuple[Vec3, Vec3]] = {
    (0, True): ((0.0, 0.0, -1.0), (0.0, 1.0, 0.0)),
    (0, False): ((0.0, 0.0, 1.0), (0.0, 1.0, 0.0)),
    (1, True): ((1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
    (1, False): ((-1.0, 0.0, 0.0), (0.0, 0.0, -1.0)),
    (2, True): ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
    (2, False): ((-1.0, 0.0, 0.0), (0.0, 1.0, 0.0)),
}


@dataclass(frozen=True)
class Mesh:
    """Vertices and faces. Each face lists vertex indices counter-clockwise seen from outside.

    `materials`, when given, holds a material slot for each face (0, 1, ...), so one mesh
    can have several materials; `kiln.blender.Kit.mesh` takes a material per slot.

    `uvs`, when given, holds a (u, v) for each corner of each face, in metres (see the module's
    notes). Moving, turning and scaling a mesh keeps its UVs, so its texture moves and
    stretches with it.
    """

    vertices: tuple[Vec3, ...]
    faces: tuple[tuple[int, ...], ...]
    materials: tuple[int, ...] | None = None
    uvs: tuple[tuple[UV, ...], ...] | None = None

    def __post_init__(self) -> None:
        if self.materials is not None and len(self.materials) != len(self.faces):
            raise ValueError(f"{len(self.materials)} material slots for {len(self.faces)} faces")
        if self.uvs is not None and (len(self.uvs) != len(self.faces)
                                     or any(len(uv) != len(face) for uv, face in zip(self.uvs, self.faces))):
            raise ValueError("a mesh's uvs need a (u, v) for each corner of each face")

    def slots(self) -> tuple[int, ...]:
        """Each face's material slot (all 0 without `materials`)."""
        return self.materials if self.materials is not None else (0,) * len(self.faces)

    def with_material(self, slot: int) -> "Mesh":
        """The mesh with every face in material slot `slot`."""
        return self.with_materials((slot,) * len(self.faces))

    def with_materials(self, slots: Sequence[int]) -> "Mesh":
        """The mesh with a material slot for each face."""
        return Mesh(self.vertices, self.faces, tuple(slots), self.uvs)

    def projected(self) -> "Mesh":
        """The mesh with UVs projected onto each face from the axis it faces most (box
        mapping), in metres. Neighbouring faces that face the same way join without a seam."""
        uvs = []
        for face in self.faces:
            points = [self.vertices[i] for i in face]
            normal = _newell(points)
            uvs.append(tuple(projected_uv(p, normal) for p in points))
        return Mesh(self.vertices, self.faces, self.materials, tuple(uvs))

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
        """The same mesh with every face turned the other way. Each corner keeps its UV, so the
        texture stays where it was and reads mirrored from the new outside."""
        uvs = None if self.uvs is None else tuple(tuple(reversed(uv)) for uv in self.uvs)
        return Mesh(self.vertices, tuple(tuple(reversed(face)) for face in self.faces), self.materials, uvs)

    def outward(self) -> "Mesh":
        """The mesh with its faces turned outward, judged by the sign of its volume."""
        return self.flipped() if self.signed_volume() < 0 else self

    def translated(self, offset: Vec3) -> "Mesh":
        return Mesh(tuple(_add(v, offset) for v in self.vertices), self.faces, self.materials, self.uvs)

    def scaled(self, factor: Vec3) -> "Mesh":
        """Scaled per axis. A negative factor mirrors the mesh, and its faces are turned back
        outward."""
        mesh = Mesh(tuple((v[0] * factor[0], v[1] * factor[1], v[2] * factor[2])
                          for v in self.vertices), self.faces, self.materials, self.uvs)
        return mesh.flipped() if factor[0] * factor[1] * factor[2] < 0 else mesh

    def rotated(self, axis: str, degrees: float) -> "Mesh":
        """Turned about the X, Y or Z axis through the origin (counter-clockwise looking down
        the axis toward the origin, as Godot turns)."""
        a = math.radians(degrees)
        c, s = math.cos(a), math.sin(a)
        if axis == "x":
            turn = lambda v: (v[0], v[1] * c - v[2] * s, v[1] * s + v[2] * c)  # noqa: E731
        elif axis == "y":
            turn = lambda v: (v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c)  # noqa: E731
        elif axis == "z":
            turn = lambda v: (v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2])  # noqa: E731
        else:
            raise ValueError(f"axis {axis!r} isn't x, y or z")
        return Mesh(tuple(turn(v) for v in self.vertices), self.faces, self.materials, self.uvs)

    def merged(self, other: "Mesh") -> "Mesh":
        """Both meshes as one (their vertices aren't joined). When either has UVs, one without
        is projected (see `projected`) where it is now."""
        shift = len(self.vertices)
        materials = None
        if self.materials is not None or other.materials is not None:
            materials = self.slots() + other.slots()
        uvs = None
        if self.uvs is not None or other.uvs is not None:
            uvs = _uvs(self) + _uvs(other)
        return Mesh(self.vertices + other.vertices,
                    self.faces + tuple(tuple(i + shift for i in face) for face in other.faces), materials, uvs)


def projected_uv(point: Vec3, normal: Vec3) -> UV:
    """Where `point` lands in UV space, in metres, projected from the axis `normal` points
    along most (box mapping)."""
    axis = max(range(3), key=lambda i: abs(normal[i]))
    u_axis, v_axis = _PROJECTIONS[(axis, normal[axis] >= 0)]
    return _dot(point, u_axis), _dot(point, v_axis)


def box(size: Vec3, center: Vec3 = (0.0, 0.0, 0.0)) -> Mesh:
    """A box of `size` around `center`. Its UVs are projected (see `Mesh.projected`), so each
    face is a rectangle of its own size in metres."""
    hx, hy, hz = (s / 2 for s in size)
    vertices = tuple(_add(center, (sx * hx, sy * hy, sz * hz))
                     for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1))
    # Index = 4 * (x > 0) + 2 * (y > 0) + (z > 0).
    faces = ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3))
    return Mesh(vertices, faces).outward().projected()


def loft(sections: Sequence[Sequence[Vec3]], caps: bool = True, bands: Sequence[int] | None = None,
         cap_slot: int = 0) -> Mesh:
    """A surface through closed rings of points, each joined to the next with quads.

    Every ring has the same number of points, in the same order around it. With `caps`, the
    first and last ring are closed with a fan around their centre, so the mesh is closed;
    a ring of one point is a tip and needs no cap. The faces are turned outward.

    `bands` gives a material slot for each strip along the loft: strip i runs between ring
    points i and i + 1 (the last between the last point and the first). The caps take
    `cap_slot`.

    The UVs run round each ring from its first point (u) and along the loft (v). u is the
    share of the way round the ring times the rings' mean length round, so a texture is
    squeezed round a narrower ring rather than sheared across the faces; v is the mean
    distance between one ring's points and the next's, so a lathe's v is the length along its
    profile. The caps are projected (see `projected_uv`) about their centres.
    """
    if bands is not None and len(bands) != max(len(ring) for ring in sections):
        raise ValueError("loft needs one band slot per ring point")
    if len(sections) < 2:
        raise ValueError("loft needs at least two sections")
    count = max(len(ring) for ring in sections)
    if any(len(ring) not in (1, count) for ring in sections) or count < 3:
        raise ValueError("loft sections need the same number of points (3 or more), or one for a tip")
    rings = [[tuple(map(float, p)) for p in ring] for ring in sections]
    around = [_lengths_round(ring) for ring in rings]
    perimeters = [lengths[-1] for lengths in around if lengths]
    mean = sum(perimeters) / len(perimeters)
    around = [None if lengths is None else [length / lengths[-1] * mean if lengths[-1] else 0.0
                                            for length in lengths] for lengths in around]
    along = [0.0]
    for k in range(len(rings) - 1):
        pairs = [(rings[k][i % len(rings[k])], rings[k + 1][i % len(rings[k + 1])]) for i in range(count)]
        along.append(along[-1] + sum(_distance(p, q) for p, q in pairs) / count)
    vertices: list[Vec3] = []
    starts: list[int] = []
    for ring in rings:
        starts.append(len(vertices))
        vertices.extend(ring)
    faces: list[tuple[int, ...]] = []
    slots: list[int] = []
    uvs: list[tuple[UV, ...]] = []
    for k in range(len(rings) - 1):
        a, b = starts[k], starts[k + 1]
        a_tip, b_tip = len(rings[k]) == 1, len(rings[k + 1]) == 1
        if a_tip and b_tip:
            raise ValueError("loft can't join two tips")
        for i in range(count):
            j = (i + 1) % count
            if a_tip:
                # A tip's corner sits halfway along the edge of the ring it joins.
                ring = around[k + 1]
                faces.append((a, b + j, b + i))
                uvs.append((((ring[i] + ring[i + 1]) / 2, along[k]), (ring[i + 1], along[k + 1]),
                            (ring[i], along[k + 1])))
            elif b_tip:
                ring = around[k]
                faces.append((a + i, a + j, b))
                uvs.append(((ring[i], along[k]), (ring[i + 1], along[k]),
                            ((ring[i] + ring[i + 1]) / 2, along[k + 1])))
            else:
                faces.append((a + i, a + j, b + j, b + i))
                uvs.append(((around[k][i], along[k]), (around[k][i + 1], along[k]),
                            (around[k + 1][i + 1], along[k + 1]), (around[k + 1][i], along[k + 1])))
            slots.append(bands[i] if bands is not None else 0)
    # Each cap face's normal and centre, to project its UVs from once the faces' way round is known.
    cap_planes: list[tuple[Vec3, Vec3]] = []
    if caps:
        for k in (0, len(rings) - 1):
            if len(rings[k]) == count:
                c = len(vertices)
                centre = _centroid(rings[k])
                vertices.append(centre)
                s = starts[k]
                # Each cap runs its ring's edges the other way from the side faces next to it.
                if k == 0:
                    faces.extend((c, s + (i + 1) % count, s + i) for i in range(count))
                else:
                    faces.extend((c, s + i, s + (i + 1) % count) for i in range(count))
                slots.extend([cap_slot] * count)
                # The whole cap is projected one way, from the normal of its ring.
                cap_planes.extend([(_newell(rings[k] if k else rings[k][::-1]), centre)] * count)
    materials = tuple(slots) if bands is not None or cap_slot else None
    flip = Mesh(tuple(vertices), tuple(faces)).signed_volume() < 0
    # Turned outward, the faces run the other way round: u runs the other way with them, and
    # the caps face the other way, so the texture still reads the right way round.
    sign = -1.0 if flip else 1.0
    uvs = [tuple((sign * u, v) for u, v in uv) for uv in uvs]
    for face, (normal, centre) in zip(faces[len(uvs):], cap_planes):
        outward = (sign * normal[0], sign * normal[1], sign * normal[2])
        uvs.append(tuple(projected_uv(_sub(vertices[i], centre), outward) for i in face))
    mesh = Mesh(tuple(vertices), tuple(faces), materials, tuple(uvs))
    return mesh.flipped() if flip else mesh


def lathe(profile: Sequence[tuple[float, float]], segments: int = 16) -> Mesh:
    """A solid of revolution about the Y axis from (radius, height) points, bottom to top.

    A point with radius 0 is a pole, so a profile from (0, y0) to (0, y1) makes a closed
    mesh. Otherwise the open ends are capped. The UVs run round from +X (u) and up the
    profile (v), as a loft's.
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


def _uvs(mesh: Mesh) -> tuple[tuple[UV, ...], ...]:
    return mesh.uvs if mesh.uvs is not None else mesh.projected().uvs


def _lengths_round(ring: Sequence[Vec3]) -> list[float] | None:
    """The length round a ring from its first point to each point, and back to the first
    (one more than the ring has points); None for a tip."""
    if len(ring) == 1:
        return None
    lengths = [0.0]
    for i in range(len(ring)):
        lengths.append(lengths[-1] + _distance(ring[i], ring[(i + 1) % len(ring)]))
    return lengths


def _newell(points: Sequence[Vec3]) -> Vec3:
    """A polygon's normal, its length twice the polygon's area (Newell's method), so it works
    for faces that aren't quite flat."""
    x = y = z = 0.0
    for i, a in enumerate(points):
        b = points[(i + 1) % len(points)]
        x += (a[1] - b[1]) * (a[2] + b[2])
        y += (a[2] - b[2]) * (a[0] + b[0])
        z += (a[0] - b[0]) * (a[1] + b[1])
    return x, y, z


def _edge(a: int, b: int) -> tuple[int, int]:
    return (a, b) if a < b else (b, a)


def _add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _distance(a: Vec3, b: Vec3) -> float:
    return math.dist(a, b)


def _dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a: Vec3, b: Vec3) -> Vec3:
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _centroid(points: Sequence[Vec3]) -> Vec3:
    n = len(points)
    return (sum(p[0] for p in points) / n, sum(p[1] for p in points) / n, sum(p[2] for p in points) / n)
