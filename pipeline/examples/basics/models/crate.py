"""A wooden crate with iron corners and a marker where its lid opens: a box with bevels,
a material per part and a marker."""
from kiln import model


@model(max_triangles=2000, size=(0.82, 0.82, 0.82), markers=["Lid"])
def build(k):
    wood = k.material("Wood", "#9a6a3a", roughness=0.8)
    iron = k.material("Iron", "#2b2d30", roughness=0.4, metallic=0.8)
    k.box("Body", (0.8, 0.8, 0.8), center=(0, 0.4, 0), bevel=0.02, material=wood)
    for side, x in (("Left", -0.39), ("Right", 0.39)):
        for end, z in (("Front", -0.39), ("Back", 0.39)):
            k.box(f"Corner{end}{side}", (0.04, 0.82, 0.04), center=(x, 0.41, z), bevel=0.008, material=iron)
    k.marker("Lid", (0, 0.8, 0.4))
