"""A racing buoy: a lathed body, smooth shaded, with a band and a lamp marker on top."""
from kiln import model


@model(max_triangles=3000, size=(0.604, 1.2, 0.604), markers=["Lamp"])
def build(k):
    red = k.material("Red", "#d8322a", roughness=0.35)
    white = k.material("White", "#f2f2ee", roughness=0.35)
    k.lathe("Body", [(0, 0), (0.28, 0.02), (0.3, 0.3), (0.3, 0.9), (0.22, 1.15), (0, 1.2)],
            segments=24, material=red)
    k.lathe("Band", [(0.302, 0.5), (0.302, 0.7)], segments=24, material=white)
    k.marker("Lamp", (0, 1.25, 0))
