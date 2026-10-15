# kiln

Kiln builds game assets from Python recipes in headless Blender. A recipe says how to make one
model; kiln runs it, checks the result against what the recipe promises, exports it as a
binary glTF (`.glb`) and renders a preview sheet. Recipes live in the game's repository, so
models are rebuilt, reviewed and changed like code.

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
```

Recipes import shared code by its path from the project folder
(`from models.craft._hull import hull_sections`). An asset is rebuilt when its recipe, any
shared `_` file, kiln's build code or the Blender version changes; `kiln.lock.json` keeps the
fingerprint of each build. Builds are deterministic: the same inputs give the same file.

## A recipe

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
| `k.material(name, color, roughness, metallic)` | a flat-colour material (`"#rrggbb"` or sRGB floats); imports as a StandardMaterial3D |
| `k.box(name, size, center, bevel, bevel_segments, material, parent)` | a box, its edges rounded by `bevel` metres |
| `k.loft(name, sections, caps, material, parent, smooth_angle)` | a surface through rings of points (hulls, tubes) |
| `k.lathe(name, profile, segments, material, parent, smooth_angle)` | a solid of revolution about Y from (radius, height) points |
| `k.mesh(name, mesh, material, parent, smooth_angle)` | an object from any `kiln.geometry.Mesh` |
| `k.marker(name, position, rotation, parent)` | a named empty; the game finds it by name (imports as a Node3D) |
| `k.parent(child, parent)` | makes `child` move with `parent`, where it is now |
| `k.bevel(obj, width, segments, angle)` | rounds an object's sharp edges |

Recipes can also use `bpy` directly for anything the kit lacks. `kiln.geometry` builds meshes
as plain data (`box`, `loft`, `lathe`, `ring`, `mirrored_ring`) and is tested without Blender.

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

## Preview sheets

Each build renders `<reports>/<id>/preview.png`: front, side, top and three-quarter views in
the materials' colours, with markers as small magenta diamonds. `report.json` beside it holds
the measurements and problems.

## Tests

```sh
uv run --project pipeline pytest pipeline/tests
```

Tests that need Blender are skipped when it isn't installed. `examples/basics` is a small
project the tests build.
