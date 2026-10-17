"""The harbour buildings: one builder, with the size, floors, roof and door as parameters.

Model space: the origin at the middle of the ground floor, the long walls facing +Z and -Z,
the front (with the door) +Z. The parts:

- Wall: the walls and the gable ends, painted the building's wall colour in the game.
- Roof: a gable roof along X with eaves, or a flat roof behind a parapet, painted its roof
  colour.
- Trim, Plinth: corner boards, the eave band and window sills, and a stone plinth.
- Window and WindowDark: the panes. Window panes glow at night in the game; WindowDark
  panes stay dark, so some rooms are lit and some aren't.
- Door: a door, or a warehouse's roller door.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass

from kiln import geometry

PANE = (1.0, 1.2)
# The materials the game paints: the walls and roof in the building's colours, and the panes
# that glow at night.
MATERIALS = ["Wall", "Roof", "Window"]


@dataclass(frozen=True)
class Building:
    width: float
    height: float
    depth: float
    floors: int
    # "gable" or "flat".
    roof: str = "gable"
    # "door" or "roller" (a warehouse door).
    door: str = "door"
    # The share of panes lit at night, and the seed that picks which.
    lit: float = 0.55
    seed: int = 1

    @property
    def roof_height(self) -> float:
        return self.height * 0.35 if self.roof == "gable" else 0.0

    @property
    def outer_width(self) -> float:
        """The width over the eaves (a gable roof) or the parapet (a flat one)."""
        return self.width + (0.8 if self.roof == "gable" else 0.25)


def build(k, b: Building) -> None:
    wall = k.material("Wall", "#f1efe9", roughness=0.85)
    roof = k.material("Roof", "#e6e6e6", roughness=0.75)
    trim = k.material("Trim", "#ebe6dc", roughness=0.7)
    plinth = k.material("Plinth", "#5c5953", roughness=0.9)
    lit = k.material("Window", "#28323f", roughness=0.15)
    dark = k.material("WindowDark", "#141a22", roughness=0.15)
    door = k.material("Door", "#3d2c20" if b.door == "door" else "#56606a", roughness=0.6)
    w, h, d = b.width, b.height, b.depth
    k.box("Walls", (w, h, d), center=(0, h / 2, 0), material=wall)
    k.box("Plinth", (w + 0.12, 0.6, d + 0.12), center=(0, 0.3, 0), material=plinth)
    trims = geometry.box((w + 0.12, 0.28, d + 0.12), (0, h - 0.14, 0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            trims = trims.merged(geometry.box((0.22, h - 0.6, 0.22), (sx * w / 2, h / 2 + 0.3, sz * d / 2)))
    if b.roof == "gable":
        _gable(k, b, wall, roof)
    else:
        _flat(k, b, roof, trim)
    panes, sills, slots = geometry.Mesh((), ()), geometry.Mesh((), ()), []
    rng = random.Random(b.seed)
    storey = (h - 0.4) / b.floors
    door_x = -w * 0.18
    door_size = (1.2, 2.2) if b.door == "door" else (min(w * 0.3, 4.2), min(h * 0.62, 3.8))
    for face, normal in (("front", 1), ("back", -1)):
        columns = max(int(w / 2.5), 1)
        for floor in range(b.floors):
            y = 0.6 + storey * floor + storey * 0.55
            if b.floors == 1:
                y = h - 1.3
            for c in range(columns):
                x = (c + 0.5) / columns * w - w / 2
                if face == "front" and abs(x - door_x) < door_size[0] / 2 + 0.7 and y - 0.6 < door_size[1] + 0.6:
                    continue
                panes = panes.merged(geometry.box((*PANE, 0.1), (x, y, normal * (d / 2 + 0.03))))
                slots.append(0 if rng.random() < b.lit else 1)
                sills = sills.merged(geometry.box((1.2, 0.08, 0.16), (x, y - PANE[1] / 2 - 0.06, normal * (d / 2 + 0.05))))
    if d >= 8 and b.floors > 1:
        for normal in (-1, 1):
            for floor in range(b.floors):
                y = 0.6 + storey * floor + storey * 0.55
                panes = panes.merged(geometry.box((0.1, PANE[1], PANE[0]), (normal * (w / 2 + 0.03), y, 0)))
                slots.append(0 if rng.random() < b.lit else 1)
    # Each pane is a box of six faces; give each box its slot.
    k.mesh("Windows", panes.with_materials([s for s in slots for _ in range(6)]), material=[lit, dark])
    trims = trims.merged(sills)
    k.mesh("Trim", trims, material=trim)
    k.box("Door", (door_size[0], door_size[1], 0.12), center=(door_x, 0.6 + door_size[1] / 2 - 0.3, d / 2 + 0.03),
          material=door)


def _gable(k, b: Building, wall, roof) -> None:
    w, h, d = b.width, b.height, b.depth
    rise = b.roof_height
    # The gable ends: a triangular prism the size of the walls, under the roof.
    ends = geometry.loft([[(x, h, -d / 2), (x, h, d / 2), (x, h + rise, 0)] for x in (-w / 2, w / 2)])
    k.mesh("Gables", ends, material=wall)
    eave = 0.45
    slope = math.hypot(d / 2 + eave, rise + eave * rise / (d / 2))
    angle = math.degrees(math.atan2(rise, d / 2))
    thickness = 0.18
    halves = geometry.Mesh((), ())
    for side in (-1, 1):
        # Each half of the roof is a slab lying on its slope, its top edge at the ridge.
        slab = geometry.box((w + 0.7, thickness, slope), (0, thickness / 2, side * slope / 2))
        slab = slab.rotated("x", side * angle)
        halves = halves.merged(slab.translated((0, h + rise, 0)))
    ridge = geometry.box((w + 0.8, 0.22, 0.34), (0, h + rise + 0.1, 0))
    k.mesh("Roof", halves.merged(ridge), material=roof)


def _flat(k, b: Building, roof, trim) -> None:
    w, h, d = b.width, b.height, b.depth
    parts = geometry.box((w, 0.2, d), (0, h + 0.1, 0))
    for sx in (-1, 1):
        parts = parts.merged(geometry.box((0.25, 0.7, d + 0.25), (sx * (w / 2), h + 0.35, 0)))
    for sz in (-1, 1):
        parts = parts.merged(geometry.box((w + 0.25, 0.7, 0.25), (0, h + 0.35, sz * (d / 2))))
    parts = parts.merged(geometry.box((w * 0.3, 2.2, d * 0.3), (w * 0.2, h + 1.1, -d * 0.15)))
    k.mesh("Roof", parts, material=roof)
