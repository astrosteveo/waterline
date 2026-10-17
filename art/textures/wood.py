"""Weathered timber for piers and crates: grain along u with knots, sun-bleached in streaks
along the grain, with grime down in the grain's grooves."""
from kiln import texture


@texture(size=1024, tile=2.0, relief=0.004, maps=("albedo", "normal", "roughness"))
def build(t):
    warp = t.noise(scale=1.0, detail=3, stretch=(8, 1), seed=1)
    knot = t.noise(scale=2.5, detail=1, stretch=(2.5, 1), seed=3).smoothstep(0.7, 0.76)
    # Rings bend round the knots.
    rings = t.stripes(36, along="v", warp=warp * 2.5 + knot * 0.8)
    grain = t.noise(scale=24, detail=4, stretch=(16, 1), seed=2)
    bleach = t.noise(scale=1.2, detail=3, stretch=(10, 1), seed=4).smoothstep(0.48, 0.66)
    height = rings * 0.3 + grain * 0.5 + (1 - knot) * 0.2
    timber = t.ramp(rings * 0.45 + grain * 0.55, [(0.3, "#6a482c"), (0.72, "#9c7550")])
    timber = t.mix(timber, "#a89f8f", bleach * 0.55)
    timber = t.mix(timber, "#3b2718", knot * 0.85)
    # Grime gathers in the grain's grooves, found from the height as baked.
    grooves = t.hollows(t.bake(height), 0.006)
    timber = t.mix(timber, "#2a1c12", grooves * 0.3)
    t.output(albedo=timber, roughness=0.86 - grain * 0.1, height=height)
