"""Weathered grey-brown rock for the rocks, pillars and cliffs: mottled stone with faint
strata, wandering cracks, pits and patches of lichen; dirt down in the cracks and pits,
the edges worn paler, and the hollows shaded by the stone round them."""
from kiln import texture


@texture(size=1024, tile=4.0, relief=0.05, maps=("albedo", "normal", "orm"))
def build(t):
    lumps = t.noise(scale=1.2, detail=6, roughness=0.62, seed=1)
    strata = t.stripes(4, along="v", warp=t.noise(scale=0.5, detail=4, seed=2) * 2.5)
    # Cracks follow where a noise crosses its middle, fading in and out along their length.
    crack_noise = t.noise(scale=0.9, detail=3, roughness=0.55, seed=3)
    cracks = 1 - abs(crack_noise - 0.5).smoothstep(0.004, 0.02)
    cracks = cracks * t.noise(scale=0.7, detail=2, seed=4).smoothstep(0.42, 0.6)
    pits = t.noise(scale=25, detail=3, seed=5).smoothstep(0.62, 0.75)
    speckle = t.noise(scale=90, detail=2, seed=6)
    height = (lumps * 0.8 + strata * 0.1 + speckle * 0.1) * (1 - cracks * 0.5) - pits * 0.08
    stone = t.ramp(lumps * 0.82 + strata * 0.08 + speckle * 0.1,
                   [(0.3, "#5d574f"), (0.5, "#7a7368"), (0.7, "#958c7e")])
    lichen = t.noise(scale=2.0, detail=5, seed=7).smoothstep(0.6, 0.68)
    stone = t.mix(stone, "#8d8a58", lichen * 0.55)
    stone = stone * (1 - cracks * 0.55 - pits * 0.2)
    # From the height as baked: grime in the hollows, the crests worn pale, and light kept
    # out of the hollows by the stone round them.
    baked = t.bake(height.clamp())
    grime = t.hollows(baked, 0.04)
    worn = t.ridges(baked, 0.08)
    shade = t.occlusion(baked, 0.12)
    stone = t.mix(stone, "#3e382f", grime * 0.35)
    stone = t.mix(stone, "#a79f92", worn * 0.18)
    stone = stone * (0.7 + shade * 0.3)
    t.output(albedo=stone, roughness=0.88 - lichen * 0.08 + grime * 0.05, height=height.clamp(), occlusion=shade)
