"""Palm trees: a curved, ringed trunk with a flared foot, a crown of drooping fronds, a few
dry fronds hanging under it and a cluster of coconuts.

Everything is one mesh with a material per part (Trunk, Frond, FrondDry, Coconut), so the
game can draw a whole grove of one palm at once (environment/terrain.gd). The origin is at
the foot of the trunk; the game sinks it a little into the ground.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass

from kiln import geometry

TRUNK, FROND, DRY, COCONUT = range(4)


@dataclass(frozen=True)
class Palm:
    height: float = 7.0
    # How far the crown leans out from over the foot, in metres.
    lean: float = 1.2
    trunk_base: float = 0.22
    trunk_top: float = 0.14
    fronds: int = 11
    frond_length: float = 3.4
    # How far a frond's tip hangs below where a straight frond would reach, in metres.
    droop: float = 1.6
    dry_fronds: int = 3
    coconuts: int = 4
    seed: int = 1


def mesh(palm: Palm) -> geometry.Mesh:
    rng = random.Random(palm.seed)
    lean_dir = rng.uniform(0, math.tau)
    lean = (math.cos(lean_dir) * palm.lean, math.sin(lean_dir) * palm.lean)
    curve = [(0.0, 0.0, 0.0), (lean[0] * 0.85, palm.height * 0.45, lean[1] * 0.85), (lean[0], palm.height, lean[1])]
    out = _trunk(palm, curve)
    crown = curve[2]
    for i in range(palm.fronds):
        azimuth = i * 2.39996 + rng.uniform(-0.2, 0.2)
        rise = rng.uniform(0.25, 0.75)
        length = palm.frond_length * rng.uniform(0.85, 1.1)
        out = out.merged(_frond(crown, azimuth, rise, length, palm.droop * rng.uniform(0.8, 1.2), 0.5, FROND))
    for i in range(palm.dry_fronds):
        azimuth = rng.uniform(0, math.tau)
        out = out.merged(_frond((crown[0], crown[1] - 0.35, crown[2]), azimuth, -0.9, palm.frond_length * 0.7,
                                0.3, 0.32, DRY))
    nut = geometry.lathe([(0, -0.11), (0.09, -0.07), (0.11, 0.0), (0.09, 0.07), (0, 0.11)], 6).with_material(COCONUT)
    for i in range(palm.coconuts):
        angle = i * math.tau / palm.coconuts + rng.uniform(-0.3, 0.3)
        out = out.merged(nut.translated((crown[0] + math.cos(angle) * 0.2, crown[1] - 0.3 - rng.uniform(0, 0.12),
                                         crown[2] + math.sin(angle) * 0.2)))
    return out


def build(k, palm: Palm) -> None:
    trunk = k.material("Trunk", "#7d6a55", roughness=0.9)
    frond = k.material("Frond", "#4c7a2a", roughness=0.7)
    dry = k.material("FrondDry", "#8d6e3e", roughness=0.85)
    coconut = k.material("Coconut", "#5b4a2b", roughness=0.7)
    k.mesh("Palm", mesh(palm), material=[trunk, frond, dry, coconut])


def _bezier(curve, t: float):
    a, b, c = curve
    return tuple((1 - t) ** 2 * a[i] + 2 * (1 - t) * t * b[i] + t ** 2 * c[i] for i in range(3))


def _trunk(palm: Palm, curve) -> geometry.Mesh:
    rings, sides = 16, 7
    sections = []
    for r in range(rings + 1):
        t = r / rings
        centre = _bezier(curve, t)
        ahead = _bezier(curve, min(t + 0.01, 1.0))
        behind = _bezier(curve, max(t - 0.01, 0.0))
        tangent = _unit(tuple(ahead[i] - behind[i] for i in range(3)))
        side = _unit(_cross(tangent, (0.0, 0.0, 1.0)))
        other = _cross(side, tangent)
        radius = palm.trunk_base + (palm.trunk_top - palm.trunk_base) * t
        radius *= 1.0 + 0.5 * (1 - t) ** 8 + (0.05 if r % 2 else 0.0)
        sections.append([tuple(centre[i] + radius * (math.cos(a) * side[i] + math.sin(a) * other[i]) for i in range(3))
                         for a in (math.tau * s / sides for s in range(sides))])
    return geometry.loft(sections).with_material(TRUNK)


def _frond(crown, azimuth: float, rise: float, length: float, droop: float, width: float, slot: int) -> geometry.Mesh:
    """A frond from the crown: its rib rises at `rise` radians and bends down under its own
    weight; its leaflets hang either side of the rib, `width` metres at the widest."""
    out = (math.cos(azimuth), 0.0, math.sin(azimuth))
    across = (-out[2], 0.0, out[0])
    sections = []
    steps = 7
    for s in range(steps):
        f = s / steps
        along = length * f
        rib = tuple(crown[i] + out[i] * along * math.cos(rise) for i in range(3))
        rib = (rib[0], rib[1] + along * math.sin(rise) - droop * f * f, rib[2])
        half = width * max(math.sin(math.pi * (0.08 + 0.92 * f)) ** 0.7, 0.08)
        hang = half * 0.45
        sections.append([tuple(rib[i] - across[i] * half for i in range(3))[:1] + (rib[1] - hang,)
                         + tuple(rib[i] - across[i] * half for i in range(3))[2:],
                         (rib[0], rib[1] + 0.04, rib[2]),
                         tuple(rib[i] + across[i] * half for i in range(3))[:1] + (rib[1] - hang,)
                         + tuple(rib[i] + across[i] * half for i in range(3))[2:]])
    tip_rib = tuple(crown[i] + out[i] * length * math.cos(rise) for i in range(3))
    sections.append([(tip_rib[0], tip_rib[1] + length * math.sin(rise) - droop, tip_rib[2])])
    return geometry.loft(sections).with_material(slot)


def _unit(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
