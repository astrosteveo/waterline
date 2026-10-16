# kiln

Kiln builds game assets from Python recipes in headless Blender. A recipe says how to make one
model or texture; kiln runs it, checks the result against what the recipe promises, exports
it (a model as a binary glTF, `.glb`; a texture as PNG maps that tile) and renders a preview
sheet. Recipes live in the game's repository, so assets are rebuilt, reviewed and changed like
code.

It needs Blender (5.2 is what it's developed with) and [uv](https://docs.astral.sh/uv/).

## Use

```sh
uv run --project pipeline kiln build                 # build every asset whose recipe changed
uv run --project pipeline kiln build models/craft    # only these (an id or a folder of ids)
uv run --project pipeline kiln build --force ID      # build even if it's up to date
uv run --project pipeline kiln check                 # run the recipes and checks, write nothing
uv run --project pipeline kiln preview ID            # render preview sheets only
uv run --project pipeline kiln status                # what is up to date
```

Kiln finds the project's `kiln.toml` in the current folder, an `art` folder in it, or a
folder above it; `--project DIR` names it. `--blender PATH` (or `KILN_BLENDER`) picks the
Blender binary. A failed check or a recipe error fails the build (exit code 1) and nothing is
written for that asset.

## A project

```
art/
  kiln.toml            output = "../godot/assets", reports = "../build/kiln"
  kiln.lock.json       what each asset was last built from (commit it)
  models/
    props/crate.py     the asset models/props/crate -> <output>/models/props/crate.glb
    craft/_hull.py     shared code: names starting with _ aren't assets
  textures/
    sand.py            the asset textures/sand -> <output>/textures/sand_albedo.png, ...
```

Recipes import shared code by its path from the project folder
(`from models.craft._hull import hull_sections`). An asset is rebuilt when its recipe, any
shared `_` file, kiln's build code or the Blender version changes; `kiln.lock.json` keeps the
fingerprint of each build and the files it made. Builds are deterministic: the same inputs
give the same files.

## A model recipe

```python
from kiln import model


@model(max_triangles=2000, size=(0.82, 0.82, 0.82), markers=["Lid"])
def build(k):
    wood = k.material("Wood", "#9a6a3a", roughness=0.8)
    k.box("Body", (0.8, 0.8, 0.8), center=(0, 0.4, 0), bevel=0.02, material=wood)
    k.marker("Lid", (0, 0.8, 0.4))
```

Coordinates are in **game space**: metres, +X right, +Y up, -Z forward, as Godot uses them.
Kiln turns them into Blender's axes, and the export turns them back, so a point a recipe puts
at (0, 0.8, 0.4) is at (0, 0.8, 0.4) in the game.

`k` (`kiln.blender.kit.Kit`) has:

| Call | Makes |
|---|---|
| `k.material(name, color, roughness, metallic, double_sided)` | a flat-colour material (`"#rrggbb"` or sRGB floats); imports as a StandardMaterial3D that draws only front faces, unless `double_sided` |
| `k.box(name, size, center, bevel, bevel_segments, material, parent)` | a box, its edges rounded by `bevel` metres |
| `k.loft(name, sections, caps, material, parent, smooth_angle, bands, cap_slot)` | a surface through rings of points (hulls, tubes); `bands` gives each strip round the rings a material slot |
| `k.lathe(name, profile, segments, material, parent, smooth_angle)` | a solid of revolution about Y from (radius, height) points |
| `k.mesh(name, mesh, material, parent, smooth_angle, position)` | an object from any `kiln.geometry.Mesh`, its origin at `position`; `material` is one material or a list, one per slot |
| `k.marker(name, position, rotation, parent)` | a named empty; the game finds it by name (imports as a Node3D) |
| `k.parent(child, parent)` | makes `child` move with `parent`, where it is now |
| `k.bevel(obj, width, segments, angle)` | rounds an object's sharp edges |

Recipes can also use `bpy` directly for anything the kit lacks. `kiln.geometry` builds meshes
as plain data (`box`, `loft`, `lathe`, `ring`, `mirrored_ring`), moves them (`translated`,
`rotated`, `scaled`, `merged`), gives faces material slots (`materials`, `with_material`) and
is tested without Blender.

## A texture recipe

```python
from kiln import texture


@texture(size=1024, tile=4.0, relief=0.015, maps=("albedo", "normal", "roughness"))
def build(t):
    ripples = t.stripes(14, along="v", warp=t.noise(scale=0.5, seed=2) * 3)
    grains = t.noise(scale=120, detail=2, seed=3)
    height = ripples * 0.6 + grains * 0.4
    sand = t.ramp(grains * 0.6 + ripples * 0.4, [(0.35, "#d8c08e"), (0.75, "#efe0b6")])
    t.output(albedo=sand, roughness=0.95, height=height)
```

A texture recipe builds a material from Blender's procedural textures, and kiln bakes it in
Cycles (on the CPU, with a fixed seed, so every build gives the same pixels) into
`<output>/<id>_<map>.png`: `albedo` (sRGB), `normal` (tangent space, OpenGL convention: green
points up the image, as Godot expects), `roughness` and `height` (16-bit). The normal map is
worked out from the height, `relief` metres between height 0 and 1. Every map tiles: noise and
Voronoi are sampled on a torus in four dimensions, so the left edge meets the right and the
top the bottom, and stripes and bands come in whole numbers per tile. Scales are per metre of
the game's surface, `tile` metres to a tile.

`t` (`kiln.blender.shading.TextureKit`) gives values and colours, which combine with numbers
and each other through `+ - * / **`:

| Call | Gives |
|---|---|
| `t.u`, `t.v` | where a pixel is across the tile, 0 to 1 |
| `t.noise(scale, detail, roughness, lacunarity, distortion, stretch, seed, kind)` | Blender's Noise texture (fbm, multifractal, ridged, hybrid or hetero); `stretch` (u, v) makes features longer one way, as wood grain |
| `t.voronoi(scale, output, randomness, smoothness, stretch, seed)` | Blender's Voronoi: the distance to a cell's centre, to the second nearest, smoothed, to the nearest edge, or a random number per cell |
| `t.stripes(count, along, warp, phase)` | soft stripes, a whole number of them, bent by `warp` |
| `t.bands(count, along, warp)`, `t.random(value, seed)` | which band a pixel is in, and a random number per band (planks) |
| `value.clamp()`, `.min()`, `.max()`, `.floor()`, `.fract()`, `.wrap()`, `.sin()`, `.cos()`, `.remap()`, `.smoothstep()` | maths on a value |
| `t.color(colour)`, `t.ramp(value, stops)`, `t.mix(a, b, factor)` | flat colours, colour ramps, and mixes of colours or values |
| `t.output(albedo, roughness, height)` | which colour and values become the maps |

## Checks

`@model(...)` takes what the build must meet. Every check runs on every build:

| Field | Checks |
|---|---|
| `max_triangles` | the total triangle count is within budget |
| `size`, `size_tolerance` | the bounding box (x, y, z; None skips an axis) is within the tolerance (2%) |
| `markers` | an object with each name exists |
| `closed` (default True) | every mesh is closed: each edge shared by exactly two faces |
| `allow_self_intersections` (default False) | no mesh cuts through itself (separate objects may overlap) |

Faces with no area always fail.

A texture always gets two checks: every map tiles (its wrap-round edges differ no more than
neighbouring pixels do inside it, within 1.5 times), and every value lies between 0 and 1.

## Preview sheets

Each build renders `<reports>/<id>/preview.png`. A model's shows the front, side, top and
three-quarter views in the materials' colours, with markers as small magenta diamonds; a
texture's shows each map tiled two by two, so a seam would show as a cross. `report.json`
beside it holds the measurements and problems.

## Tests

```sh
uv run --project pipeline pytest pipeline/tests
```

Tests that need Blender are skipped when it isn't installed. `examples/basics` is a small
project the tests build.
