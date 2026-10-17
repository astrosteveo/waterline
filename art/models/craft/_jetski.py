"""The jet ski every craft is built from: one shape with the proportions as parameters.

Model space as the game uses it: -Z forward, +Y up, the origin on the keel at mid-length.
The parts:

- Hull: lofted cross-sections from the transom to a pointed bow, a vee bottom with a chine
  lip, flared sides, a black rub rail and a dark deck. The light parts are painted in the
  rider's colours in the game: the bottom colour below the BottomLine marker, the trim colour
  up to the TrimLine marker, the hull colour above.
- Hood: a rounded cowl on the bow deck, painted the hull colour.
- Console and seat: the seat's pedestal between the footwells, and the seat on it.
- Footwell mats either side of the console, a jet nozzle at the stern.
- Handlebar: the bar and grips under the Handlebar marker, which the game turns with the
  steering; the steering column below it stays put.

The craft's Seat marker is in its craft scene (godot/craft/<id>.tscn), because the physics
reads it: put it at `JetSki.seat_marker()`. The model has a SeatMarker there, which the
riders_kiln scenario checks the craft scene's against; running this file prints it for each
craft (see the bottom of the file).
"""
from __future__ import annotations

import math
from dataclasses import dataclass

from kiln import geometry

# Paint, deck and trim colours. White and light grey parts take the rider's colours in the
# game (jetski/model/hull_paint.gdshader); dark parts keep their own.
PAINT = "#f2f3f5"
DECK = "#3b3f47"
MAT = "#262930"
RAIL = "#18191c"
SEAT = "#14161b"
BAR = "#1d1f24"
GRIP = "#0c0d0f"
NOZZLE = "#4a4d52"

# How far the jet nozzle sticks out behind the transom.
NOZZLE_OUT = 0.12

# How far the rider's pelvis (the hip joints) sits above the top of the seat: the flesh under
# a seated person's hip joints.
SEAT_CLEARANCE = 0.1
# How far either side of the handlebar pivot the hands hold the bar (JetSkiModel.GRIP_SPREAD).
GRIP_SPREAD = 0.33


@dataclass(frozen=True)
class JetSki:
    """A jet ski's proportions, in metres and degrees."""

    length: float = 2.95
    # The hull's widest, at the gunwale.
    beam: float = 1.14
    # The bottom's vee: the angle between the bottom and the horizontal.
    deadrise: float = 18.0
    # Where along the hull it is widest, from the stern (0) to the bow (1).
    widest_at: float = 0.45
    # How wide the transom is, as a share of the beam.
    transom_width: float = 0.9
    # How the bow narrows: higher is blunter.
    bow_fullness: float = 2.2
    # How high the keel rises at the bow tip.
    bow_rise: float = 0.42
    # Where along the hull the keel starts rising (0 stern, 1 bow).
    rocker_from: float = 0.55
    # Deck height at the stern, amidships (the footwells) and at the bow.
    deck_stern: float = 0.44
    deck_mid: float = 0.48
    deck_bow: float = 0.62
    # The chine lip's width, as a share of the half beam: wider grips harder.
    chine_lip: float = 0.06
    # How much the sides flare out above the chine, as a share of the half beam.
    flare: float = 0.12
    # The hood: where it starts and ends along the hull (0 stern, 1 bow), its height above
    # the deck, where along it its peak is (0 back, 1 front), and its width at the back as a
    # share of the hull's.
    hood_from: float = 0.55
    hood_to: float = 0.985
    hood_height: float = 0.36
    hood_peak: float = 0.18
    hood_width: float = 0.62
    # The seat: its front and back (0 stern, 1 bow), width and top height.
    seat_from: float = 0.1
    seat_to: float = 0.57
    seat_width: float = 0.44
    seat_top: float = 0.8
    # The handlebar pivot: height and position along the hull (0 stern, 1 bow).
    bar_height: float = 1.04
    bar_at: float = 0.6
    # Sections along the hull: more is smoother.
    sections: int = 26

    # --- Positions -------------------------------------------------------------------

    def z(self, t: float) -> float:
        """The z of a point `t` of the way from the stern (0) to the bow (1)."""
        return self.length / 2 - t * self.length

    def half_width(self, t: float) -> float:
        b = self.beam / 2
        if t <= self.widest_at:
            u = t / self.widest_at
            return b * (self.transom_width + (1 - self.transom_width) * math.sin(u * math.pi / 2))
        u = (t - self.widest_at) / (1 - self.widest_at)
        return b * (1 - u ** self.bow_fullness) ** 0.5

    def keel(self, t: float) -> float:
        if t <= self.rocker_from:
            return 0.0
        u = (t - self.rocker_from) / (1 - self.rocker_from)
        return self.bow_rise * u * u

    def deck(self, t: float) -> float:
        """The deck's height at its edge: rising from the stern to the footwells, then to
        the bow."""
        if t <= 0.5:
            return self.deck_stern + (self.deck_mid - self.deck_stern) * _smooth(t / 0.5)
        return self.deck_mid + (self.deck_bow - self.deck_mid) * _smooth((t - 0.5) / 0.5)

    def pelvis_t(self) -> float:
        """Where along the hull the rider's pelvis sits: a little behind the seat's middle."""
        return self.seat_from + (self.seat_to - self.seat_from) * 0.55

    def seat_marker(self) -> tuple[float, float, float]:
        """Where the craft scene's Seat marker goes: the rider's pelvis."""
        return (0.0, round(self.seat_top + SEAT_CLEARANCE, 3), round(self.z(self.pelvis_t()), 3))

    def footrest(self) -> tuple[float, float]:
        """The footrests' (x, z): in the footwells, a little ahead of the pelvis."""
        t = self.pelvis_t() + 0.06
        return self.half_width(t) * 0.58, self.z(t)

    # --- Cross-sections --------------------------------------------------------------

    def hull_section(self, t: float) -> list[tuple[float, float, float]]:
        """The hull's cross-section at `t`, all the way round (see BANDS)."""
        w = self.half_width(t)
        keel = self.keel(t)
        deck = self.deck(t)
        chine_w = w * (1 - self.flare - self.chine_lip)
        chine_y = keel + chine_w * math.tan(math.radians(self.deadrise))
        # Near the bow the deck closes down onto the bottom; keep the sides in order.
        chine_y = min(chine_y, keel + (deck - keel) * 0.5)
        rail_bottom = deck - 0.07
        half = [
            (0.0, keel),
            (chine_w * 0.5, keel + (chine_y - keel) * 0.45),
            (chine_w, chine_y),
            (chine_w + w * self.chine_lip, chine_y + 0.005),
            (w, rail_bottom),
            (w, rail_bottom + 0.045),
            (w * 0.9, deck),
            (0.0, deck + 0.02),
        ]
        return geometry.mirrored_ring(half, self.z(t))

    def hull_mesh(self) -> geometry.Mesh:
        ts = [i / self.sections for i in range(self.sections)]
        sections = [self.hull_section(t) for t in ts]
        tip = self.keel(1.0) + (self.deck(1.0) - self.keel(1.0)) * 0.45
        sections.append([(0.0, tip, self.z(1.0))])
        return geometry.loft(sections, bands=HULL_BANDS, cap_slot=0)

    def hood_mesh(self) -> geometry.Mesh:
        """The cowl over the front half: from a steep back face at the seat, up to its peak
        under the handlebar, then sloping down and widening to cover the bow deck."""
        sections = []
        steps = 16
        for i in range(steps + 1):
            u = i / steps
            t = self.hood_from + (self.hood_to - self.hood_from) * u
            base = self.deck(t) - 0.04
            if u < self.hood_peak:
                h = self.hood_height * (0.72 + 0.28 * _smooth(u / self.hood_peak))
            else:
                h = self.hood_height * (1 - 0.85 * ((u - self.hood_peak) / (1 - self.hood_peak)) ** 1.4)
            hw = self.half_width(t) * (self.hood_width + (0.9 - self.hood_width) * u) * (1 - 0.5 * u ** 6)
            half = [(0.0, base), (hw, base), (hw * 0.97, base + h * 0.45),
                    (hw * 0.82, base + h * 0.82), (hw * 0.45, base + h * 0.98), (0.0, base + h)]
            sections.append(geometry.mirrored_ring(half, self.z(t)))
        return geometry.loft(sections)

    def hood_top(self) -> float:
        """The hood's highest point, at its peak."""
        t = self.hood_from + (self.hood_to - self.hood_from) * self.hood_peak
        return self.deck(t) - 0.04 + self.hood_height

    def console_mesh(self) -> geometry.Mesh:
        """The seat's pedestal between the footwells, its sides sloping in to the seat."""
        sections = []
        t_from, t_to = max(self.seat_from - 0.05, 0.03), self.hood_from + 0.03
        steps = 10
        for i in range(steps + 1):
            t = t_from + (t_to - t_from) * i / steps
            base = self.deck(t) - 0.03
            # The back end slopes down to the rear deck.
            top = base + (self.seat_top - 0.12 - base) * (0.35 + 0.65 * _smooth(i / steps / 0.25))
            hw = self.seat_width / 2
            half = [(0.0, base), (hw * 1.25, base), (hw * 1.1, base + (top - base) * 0.6),
                    (hw * 0.92, top), (0.0, top)]
            sections.append(geometry.mirrored_ring(half, self.z(t)))
        return geometry.loft(sections)

    def seat_mesh(self) -> geometry.Mesh:
        """A padded seat: rounded edges, narrowing and sloping down at the front."""
        sections = []
        steps = 10
        for i in range(steps + 1):
            u = i / steps
            t = self.seat_from + (self.seat_to - self.seat_from) * u
            base = self.seat_top - 0.16
            # The front fifth rounds down toward the hood; the back end rounds off too.
            front = _smooth(max(0.0, (u - 0.8) / 0.2))
            back = _smooth(max(0.0, (0.2 - u) / 0.2))
            top = self.seat_top - 0.07 * front - 0.09 * back
            hw = self.seat_width / 2 * (1 - 0.25 * front - 0.15 * back)
            rise = top - base
            half = [(0.0, base), (hw * 0.9, base), (hw, base + rise * 0.35), (hw * 0.9, base + rise * 0.78),
                    (hw * 0.55, top - 0.01), (0.0, top + 0.02)]
            sections.append(geometry.mirrored_ring(half, self.z(t)))
        return geometry.loft(sections)


# Material slots of the hull's bands, strip by strip round the section from the keel:
# bottom, bottom, chine lip, side (paint), rub rail, deck edge, deck, then the same back
# down the other side.
PAINT_SLOT, DECK_SLOT, RAIL_SLOT = 0, 1, 2
_HALF_BANDS = [PAINT_SLOT, PAINT_SLOT, PAINT_SLOT, PAINT_SLOT, RAIL_SLOT, DECK_SLOT, DECK_SLOT]
HULL_BANDS = _HALF_BANDS + list(reversed(_HALF_BANDS))


def build(k, ski: JetSki) -> None:
    """Builds the jet ski `ski` describes into the kit `k`."""
    paint = k.material("Paint", PAINT, roughness=0.35)
    deck = k.material("Deck", DECK, roughness=0.7)
    rail = k.material("RubRail", RAIL, roughness=0.6)
    mat = k.material("FootwellMat", MAT, roughness=0.9)
    seat = k.material("Seat", SEAT, roughness=0.75)
    bar = k.material("Handlebar", BAR, roughness=0.4, metallic=0.3)
    grip = k.material("Grip", GRIP, roughness=0.9)
    nozzle = k.material("Nozzle", NOZZLE, roughness=0.35, metallic=0.7)

    k.mesh("Hull", ski.hull_mesh(), [paint, deck, rail], smooth_angle=40)
    k.mesh("Hood", ski.hood_mesh(), paint, smooth_angle=50)
    k.mesh("Console", ski.console_mesh(), deck, smooth_angle=50)
    k.mesh("Seat", ski.seat_mesh(), seat, smooth_angle=55)

    # Footwell mats: thin pads on the deck either side of the console.
    mat_from, mat_to = ski.seat_from + 0.02, ski.hood_from - 0.01
    mat_z = (ski.z(mat_from) + ski.z(mat_to)) / 2
    mat_len = ski.z(mat_from) - ski.z(mat_to)
    mat_x = (ski.seat_width / 2 + 0.04 + ski.half_width(0.4) * 0.86) / 2
    mat_w = ski.half_width(0.4) * 0.86 - ski.seat_width / 2 - 0.06
    for side, x in (("Left", -mat_x), ("Right", mat_x)):
        k.box(f"Mat{side}", (mat_w, 0.02, mat_len), center=(x, ski.deck(0.5) + 0.012, mat_z),
              bevel=0.006, bevel_segments=1, material=mat)

    # The jet nozzle, out of the transom low down.
    k.mesh("Nozzle", geometry.lathe([(0, 0), (0.09, 0), (0.08, 0.16), (0.065, 0.2), (0, 0.2)], 14)
           .rotated("x", 90).translated((0, 0.14, ski.length / 2 + NOZZLE_OUT - 0.2)), nozzle, smooth_angle=45)

    # Steering column: out of the hood up to just under the pivot, leaning back.
    pivot = (0.0, ski.bar_height, ski.z(ski.bar_at))
    column_base = (0.0, ski.hood_top() - 0.06, pivot[2] - 0.08)
    column_len = math.dist(column_base, (0.0, pivot[1] - 0.05, pivot[2]))
    lean = math.degrees(math.atan2(pivot[2] - column_base[2], pivot[1] - 0.05 - column_base[1]))
    column = geometry.lathe([(0, 0), (0.045, 0), (0.035, column_len), (0, column_len)], 10).rotated("x", lean)
    k.mesh("Column", column.translated(column_base), bar, smooth_angle=45)

    # The handlebar: turns with the steering, with everything under its marker.
    handlebar = k.marker("Handlebar", pivot)
    head = geometry.box((0.12, 0.07, 0.1))
    k.mesh("BarClamp", head, bar, parent=handlebar, position=(0.0, pivot[1] - 0.02, pivot[2]))
    tube = geometry.lathe([(0, -0.35), (0.016, -0.35), (0.016, 0.35), (0, 0.35)], 10).rotated("z", -90)
    k.mesh("Bar", tube, bar, parent=handlebar, smooth_angle=45, position=pivot)
    for side, x in (("Left", -GRIP_SPREAD), ("Right", GRIP_SPREAD)):
        sleeve = geometry.lathe([(0, -0.065), (0.024, -0.065), (0.024, 0.065), (0, 0.065)], 10).rotated("z", -90)
        k.mesh(f"Grip{side}", sleeve, grip, parent=handlebar, smooth_angle=45,
               position=(x, pivot[1], pivot[2]))

    # Where the rider's feet rest, and the paint lines.
    fx, fz = ski.footrest()
    foot_y = ski.deck(0.5) + 0.03
    k.marker("FootLeft", (-fx, foot_y, fz))
    k.marker("FootRight", (fx, foot_y, fz))
    chine_mid = ski.hull_section(0.4)[2][1]
    k.marker("BottomLine", (0.0, chine_mid + 0.03, 0.0))
    k.marker("TrimLine", (0.0, ski.deck(0.4) - 0.17, 0.0))
    # Where the craft scene's Seat marker must be (the game reads that one, not this).
    k.marker("SeatMarker", ski.seat_marker())


def spec_size(ski: JetSki) -> tuple[float, None, float]:
    """The size a recipe expects: the beam, and the hull's length plus the nozzle behind it
    (the height is left to the parts)."""
    return (ski.beam, None, ski.length + NOZZLE_OUT)


MARKERS = ["Handlebar", "FootLeft", "FootRight", "BottomLine", "TrimLine", "SeatMarker"]


def _smooth(u: float) -> float:
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


if __name__ == "__main__":
    # Prints each craft's Seat marker for its craft scene. Run it from the repository root:
    #   uv run --project pipeline python art/models/craft/_jetski.py
    import importlib
    import pathlib
    import sys

    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[2]))
    for path in sorted(pathlib.Path(__file__).parent.glob("[!_]*.py")):
        module = importlib.import_module(f"models.craft.{path.stem}")
        ski = next(v for v in vars(module).values() if hasattr(v, "seat_marker") and not isinstance(v, type))
        x, y, z = ski.seat_marker()
        print(f"{path.stem:10} Seat ({x}, {y}, {z}), length {ski.length}, beam {ski.beam}")
