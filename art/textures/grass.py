"""Island grass: tufts of green over patches of drier yellow-green and bare earth. Its
roughness is the same everywhere, so it is a number (in kiln.lock.json) the terrain's
material takes, not a map."""
from kiln import texture


@texture(size=1024, tile=4.0, relief=0.02, maps=("albedo", "normal"))
def build(t):
    patches = t.noise(scale=0.5, detail=4, seed=1)
    tufts = t.voronoi(scale=30, output="smooth", smoothness=0.4, seed=2)
    blades = t.noise(scale=80, detail=2, stretch=(1, 3), seed=3)
    bare = t.noise(scale=0.8, detail=5, seed=4).smoothstep(0.66, 0.74)
    height = (1 - tufts) * 0.6 + blades * 0.4
    green = t.ramp(patches * 0.7 + blades * 0.3, [(0.3, "#4c7a2e"), (0.55, "#5f8f35"), (0.8, "#94a24a")])
    green = green * (0.75 + (1 - tufts) * 0.35)
    colour = t.mix(green, "#8a7350", bare * 0.8)
    t.output(albedo=colour, roughness=0.9, height=height * (1 - bare * 0.6))
