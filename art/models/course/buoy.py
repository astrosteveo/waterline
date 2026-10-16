"""A course buoy: a fat float riding half under the water, a fender round its waterline, a
tapered mast with a white band, and a lamp on top. The origin is at the water line.

The white parts named Paint take the buoy's colour in the game (red or yellow, see
course/buoy.gd), and flash when a racer passes. The Lamp glows in the buoy's colour on night
courses; its node's position is where the light goes.
"""
import math

from kiln import geometry, model

# Height of the lamp's centre above the water line, and the float's radius at the water line,
# as course/buoy.gd's defaults.
HEIGHT = 2.3
RADIUS = 0.75


@model(max_triangles=1500, size=(1.62, 3.16, 1.62), markers=["Lamp"])
def build(k):
    paint = k.material("Paint", "#f4f4f4", roughness=0.45)
    stripe = k.material("Stripe", "#f7f7f2", roughness=0.4)
    dark = k.material("Dark", "#1f2126", roughness=0.7)
    lamp = k.material("Lamp", "#f7f7f2", roughness=0.25)
    r = RADIUS
    # The float: a drum with rounded shoulders, its bottom a dark ballast plate.
    k.lathe("Float", [(0, -0.6), (r * 0.82, -0.6), (r * 0.94, -0.52), (r, -0.38), (r, 0.1),
                      (r * 0.93, 0.22), (r * 0.72, 0.29), (0, 0.3)], segments=20, material=paint)
    k.lathe("Ballast", [(0, -0.66), (r * 0.7, -0.66), (r * 0.78, -0.58), (0, -0.58)], segments=20, material=dark)
    k.lathe("Fender", [(0, 0.03), (r * 1.06, 0.03), (r * 1.08, 0.08), (r * 1.06, 0.14), (0, 0.14)],
            segments=20, material=dark)
    # The mast, tapering to the lamp, with a white band a third of the way up.
    top = HEIGHT - 0.2
    k.lathe("Mast", [(0, 0.28), (r * 0.62, 0.28), (r * 0.2, top), (0, top)], segments=16, material=paint)
    band_low, band_high = 0.28 + (top - 0.28) * 0.36, 0.28 + (top - 0.28) * 0.52

    def mast_radius(y):
        return r * 0.62 + (r * 0.2 - r * 0.62) * (y - 0.28) / (top - 0.28)

    k.lathe("Band", [(0, band_low), (mast_radius(band_low) + 0.012, band_low),
                     (mast_radius(band_high) + 0.012, band_high), (0, band_high)], segments=16, material=stripe)
    k.lathe("Cap", [(0, top - 0.04), (r * 0.24, top - 0.04), (r * 0.24, top + 0.02), (0, top + 0.02)],
            segments=12, material=dark)
    ball = 0.2
    rings = 6
    profile = [(ball * math.sin(math.pi * i / rings), -ball * math.cos(math.pi * i / rings)) for i in range(rings + 1)]
    k.mesh("Lamp", geometry.lathe([(x if x > 1e-9 else 0.0, y) for x, y in profile], 12), material=lamp,
           smooth_angle=60, position=(0, HEIGHT, 0))
