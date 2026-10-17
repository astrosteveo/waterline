"""Beach sand for the islands' shores and the seabed: pale grains with darker specks, soft
wind ripples and damp patches."""
from kiln import texture


@texture(size=1024, tile=4.0, relief=0.015, maps=("albedo", "normal", "orm"))
def build(t):
    drift = t.noise(scale=0.6, detail=3, seed=1)
    ripples = t.stripes(14, along="v", warp=t.noise(scale=0.5, detail=2, seed=2) * 3)
    ripples = ripples * (drift * 1.6 - 0.3).clamp()
    grains = t.noise(scale=120, detail=2, roughness=0.7, seed=3)
    specks = t.voronoi(scale=60, output="random", seed=4).smoothstep(0.93, 0.97)
    damp = t.noise(scale=0.35, detail=4, seed=5).smoothstep(0.52, 0.66)
    height = ripples * 0.6 + grains * 0.4
    colour = t.ramp(grains * 0.5 + ripples * 0.3 + drift * 0.3, [(0.35, "#d8c08e"), (0.75, "#efe0b6")])
    colour = t.mix(colour, "#8a7a62", specks * 0.6)
    colour = colour * (1 - damp * 0.18)
    t.output(albedo=colour, roughness=0.95 - damp * 0.25, height=height, occlusion=t.occlusion(t.bake(height), 0.1))
