"""Weathered planks: bands with a tone each, grain along them and dark gaps between, baked
into albedo, normal, roughness and height maps that tile."""
from kiln import texture


@texture(size=256, tile=1.2, relief=0.006, maps=("albedo", "normal", "roughness", "height"), samples=4)
def build(t):
    plank = t.bands(6, along="v")
    tone = t.random(plank, seed=3)
    grain = t.noise(scale=6, detail=5, stretch=(12, 1), seed=1)
    gap = 1 - t.stripes(6, along="v", phase=1.5708).smoothstep(0.93, 0.99)
    height = (grain * 0.4 + 0.5) * gap
    wood = t.ramp(grain * 0.6 + tone * 0.4, [(0.25, "#6b4a2b"), (0.75, "#a87b4f")])
    t.output(albedo=wood * gap, roughness=0.8 - grain * 0.2, height=height)
