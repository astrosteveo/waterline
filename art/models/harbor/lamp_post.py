"""A harbour lamp post: a cast plinth, a tapering post and a six-sided lantern with a roof
and finial. 4.5 m to the top of the post (the PostTop marker), as environment/lamp_post.gd's
default height; the game scales it to other heights by that marker.

The lantern's glass is named Lamp: the game makes it glow in the lamp's colour. The Light
marker is where the light goes.
"""
from kiln import model

HEIGHT = 4.5
LIGHT = HEIGHT + 0.08


@model(max_triangles=800, size=(0.54, 5.1, None), markers=["Light", "PostTop"], materials=["Lamp"])
def build(k):
    iron = k.material("Iron", "#1d2026", roughness=0.55, metallic=0.6)
    glass = k.material("Lamp", "#fff1d2", roughness=0.2)
    k.lathe("Plinth", [(0, 0), (0.24, 0), (0.24, 0.1), (0.17, 0.18), (0.13, 0.5), (0, 0.5)], segments=8, material=iron)
    k.lathe("Post", [(0, 0.45), (0.085, 0.45), (0.06, HEIGHT - 0.25), (0, HEIGHT - 0.25)], segments=8, material=iron)
    k.lathe("Holder", [(0, HEIGHT - 0.3), (0.08, HEIGHT - 0.3), (0.09, HEIGHT - 0.2), (0.2, HEIGHT - 0.14),
                       (0.2, HEIGHT - 0.1), (0, HEIGHT - 0.1)], segments=6, material=iron)
    k.lathe("Lamp", [(0, HEIGHT - 0.11), (0.17, HEIGHT - 0.11), (0.21, HEIGHT + 0.28), (0, HEIGHT + 0.28)],
            segments=6, material=glass)
    k.lathe("Roof", [(0, HEIGHT + 0.26), (0.27, HEIGHT + 0.26), (0.27, HEIGHT + 0.31), (0.06, HEIGHT + 0.5),
                     (0, HEIGHT + 0.5)], segments=6, material=iron)
    k.lathe("Finial", [(0, HEIGHT + 0.49), (0.045, HEIGHT + 0.49), (0.03, HEIGHT + 0.56), (0, HEIGHT + 0.6)],
            segments=6, material=iron)
    k.marker("Light", (0, LIGHT, 0))
    k.marker("PostTop", (0, HEIGHT, 0))
