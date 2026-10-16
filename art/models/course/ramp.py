"""A floating jump ramp: a wedge whose slope rises from under the water to a lip, in orange
and white bands edged in white, with ribbed blue sides striped in white, a white trim along
the lip and two posts under it.

The wedge is exactly course/ramp.gd's default collision shape: 7 m wide, its slope rising
from 2 m under the water's rest level at the front (+Z) to a 1.8 m lip 12 m back (-Z), its
underside 0.4 m below the front edge. course/ramp.gd stretches the model to a ramp of
another size; stretching a wedge keeps its slope flat, so the slope still lies on the
collision shape.
"""
import math

from kiln import geometry, model

WIDTH = 7.0
LENGTH = 12.0
BOTTOM = -2.0
TOP = 1.8
BASE = BOTTOM - 0.4
STRIPES = 6
# How far the posts reach under the ramp, below its underside.
POST_DEPTH = 4.0


def slope_y(z: float) -> float:
    """The slope's height at z (the front edge is at +LENGTH / 2)."""
    return BOTTOM + (LENGTH / 2 - z) / LENGTH * (TOP - BOTTOM)


@model(max_triangles=1500, size=(WIDTH + 0.12, TOP + 0.02 - (BASE - POST_DEPTH), LENGTH), markers=[])
def build(k):
    stripe_a = k.material("StripeA", "#f5520c", roughness=0.6)
    stripe_b = k.material("StripeB", "#f4f2ea", roughness=0.6)
    side = k.material("Side", "#1e4790", roughness=0.7)
    end = k.material("SideDark", "#163568", roughness=0.75)
    post = k.material("Post", "#10203e", roughness=0.8)
    hw, hl = WIDTH / 2, LENGTH / 2
    # Cross-sections from the front edge to the lip: left base, left top, right top, right base.
    sections = []
    for i in range(STRIPES + 1):
        z = hl - LENGTH * i / STRIPES
        y = slope_y(z)
        sections.append([(-hw, BASE, z), (-hw, y, z), (hw, y, z), (hw, BASE, z)])
    wedge = geometry.loft(sections, bands=[2, 0, 2, 2], cap_slot=3)
    # Strip i of section pair k is face k * 4 + i; the slope (strip 1) alternates its bands.
    slots = list(wedge.slots())
    for band in range(STRIPES):
        slots[band * 4 + 1] = 0 if band % 2 == 0 else 1
    wedge = geometry.Mesh(wedge.vertices, wedge.faces, tuple(slots))
    k.mesh("Wedge", wedge, material=[stripe_a, stripe_b, side, end])
    # A white trim along the lip, lying on the slope so it doesn't stick up into a craft's way.
    angle = math.degrees(math.atan2(TOP - BOTTOM, LENGTH))
    trim_length = 0.5
    along = (0.0, math.sin(math.radians(angle)), -math.cos(math.radians(angle)))
    lip = (0.0, TOP, -hl)
    centre = tuple(lip[i] - along[i] * trim_length / 2 for i in range(3))
    normal = (0.0, math.cos(math.radians(angle)), math.sin(math.radians(angle)))
    centre = tuple(centre[i] + normal[i] * 0.02 for i in range(3))
    trim = geometry.box((WIDTH, 0.04, trim_length)).rotated("x", angle)
    k.mesh("LipTrim", trim, material=stripe_b, position=centre)
    # White edges down both sides of the slope, lying on it.
    slope_length = math.hypot(LENGTH, TOP - BOTTOM)
    middle = (0.0, (TOP + BOTTOM) / 2, 0.0)
    edges = geometry.Mesh((), ())
    for x in (-hw + 0.15, hw - 0.15):
        edges = edges.merged(geometry.box((0.3, 0.04, slope_length), (x, 0.02, 0.0)).rotated("x", angle))
    k.mesh("SlopeEdges", edges, material=stripe_b, position=middle)
    # Ribs down the sides every 2 m, and a white band along the top of each side.
    ribs = geometry.Mesh((), ())
    for x in (-hw - 0.04, hw + 0.04):
        for i in range(1, int(LENGTH / 2)):
            z = hl - 2.0 * i
            height = slope_y(z) - 0.32 - BASE
            ribs = ribs.merged(geometry.box((0.08, height, 0.12), (x, BASE + height / 2, z)))
    k.mesh("Ribs", ribs, material=end)
    bands = geometry.Mesh((), ())
    for x in (-hw - 0.02, hw + 0.02):
        bands = bands.merged(geometry.box((0.04, 0.22, slope_length), (x, -0.16, 0.0)).rotated("x", angle))
    k.mesh("SideBands", bands, material=stripe_b, position=middle)
    for name, x in (("PostLeft", -hw + 0.3), ("PostRight", hw - 0.3)):
        k.mesh(name, geometry.lathe([(0, BASE - POST_DEPTH), (0.18, BASE - POST_DEPTH), (0.18, BASE), (0, BASE)], 8),
               material=post, position=(x, 0, -hl + 0.45))
