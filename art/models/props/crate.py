"""A floating cargo crate, 1 m on a side: a board box in a darker frame, with a diagonal brace
across each side. The material named Wood is drawn in kiln's wood texture in the game, and
WoodDark in a darker one. The origin is at the crate's centre, as props/crate.tscn's
collision box.
"""
import math

from kiln import geometry, model

SIZE = 1.0
FRAME = 0.09


@model(max_triangles=800, size=(SIZE, SIZE, SIZE),
       materials=["Wood", "WoodDark"])
def build(k):
    wood = k.material("Wood", "#a07a52", roughness=0.85)
    dark = k.material("WoodDark", "#5b432d", roughness=0.9)
    h = SIZE / 2
    k.box("Boards", (SIZE - 0.04, SIZE - 0.04, SIZE - 0.04), material=wood)
    frame = geometry.Mesh((), ())
    inner = h - FRAME / 2
    for a in (-1, 1):
        for b in (-1, 1):
            frame = frame.merged(geometry.box((SIZE, FRAME, FRAME), (0, a * inner, b * inner)))
            frame = frame.merged(geometry.box((FRAME, SIZE, FRAME), (a * inner, 0, b * inner)))
            frame = frame.merged(geometry.box((FRAME, FRAME, SIZE), (a * inner, b * inner, 0)))
    # A brace corner to corner across each side, lying on it.
    reach = SIZE - 2 * FRAME
    length = reach * math.sqrt(2)
    brace = geometry.box((length, FRAME * 0.9, 0.04))
    for normal in (-1, 1):
        frame = frame.merged(brace.rotated("z", 45 * normal).translated((0, 0, normal * (h - 0.03))))
        frame = frame.merged(brace.rotated("z", -45 * normal).rotated("y", 90).translated((normal * (h - 0.03), 0, 0)))
        frame = frame.merged(brace.rotated("z", 45 * normal).rotated("x", 90).translated((0, normal * (h - 0.03), 0)))
    k.mesh("Frame", frame, material=dark)
