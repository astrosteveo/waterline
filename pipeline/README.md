# kiln

Kiln builds game assets from Python recipes. A recipe says how to make one model, texture or
set of sounds; kiln runs it, checks the result against what the recipe promises, exports it (a
model as a binary glTF, `.glb`; a texture as PNG maps that tile; sounds as WAV files) and
renders a preview sheet. Recipes live in the game's repository, so assets are rebuilt,
reviewed and changed like code.

It needs [uv](https://docs.astral.sh/uv/), and Blender (5.2 is what it's developed with) for
models and textures; sounds are made in plain Python with numpy and scipy, and ffmpeg writes
the ones kept as Ogg Vorbis.

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
Blender binary, which only a build with a model or texture in it starts. A failed check or a recipe error fails the build (exit code 1) and nothing is
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
  audio/
    bell.py            the asset audio/bell -> <output>/audio/bell.wav (or bell_<name>.wav, ...)
```

Recipes import shared code by its path from the project folder
(`from models.craft._hull import hull_sections`). An asset is rebuilt when anything it is
built from changes: its recipe, the shared code it imports (and what that imports), the parts
of kiln that build its kind, and the Blender version (for a sound, numpy's and scipy's).
Kiln finds the imports by reading the code, so import shared code with `import` or `from`,
not `importlib`. `kiln.lock.json` keeps the fingerprint of each build, the files it made, and
what a game using them may check against: a model's size and triangles, a texture's size,
maps and `tile`, a sound's lengths. Builds are deterministic: the same inputs give the same
files.

## A model recipe

```python
from kiln import model


@model(max_triangles=2000, size=(0.82, 0.82, 0.82), markers=["Lid"], materials=["Wood"])
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
| `k.material(name, color, roughness, metallic, double_sided, emission, emission_strength, alpha)` | a flat-colour material (`"#rrggbb"` or sRGB floats); imports as a StandardMaterial3D that draws only front faces, unless `double_sided`. With `emission` it glows in that colour (`emission_strength` times as bright); with `alpha` below 1 it is see-through, blended |
| `k.box(name, size, center, bevel, bevel_segments, material, parent)` | a box, its edges rounded by `bevel` metres |
| `k.loft(name, sections, caps, material, parent, smooth_angle, bands, cap_slot)` | a surface through rings of points (hulls, tubes); `bands` gives each strip round the rings a material slot |
| `k.lathe(name, profile, segments, material, parent, smooth_angle)` | a solid of revolution about Y from (radius, height) points |
| `k.mesh(name, mesh, material, parent, smooth_angle, position)` | an object from any `kiln.geometry.Mesh`, its origin at `position`; `material` is one material or a list, one per slot |
| `k.marker(name, position, rotation, parent)` | a named empty; the game finds it by name (imports as a Node3D) |
| `k.parent(child, parent)` | makes `child` move with `parent`, where it is now |
| `k.armature(name, bones)` | a skeleton of bones from `{name: (head, tail)}`, none parented to another; imports as a Skeleton3D |
| `k.skin(obj, armature, weights)` | fixes `obj` to the armature's bones: wholly to one (a bone's name), or by a function from a vertex's position to `{bone: weight}`; `obj` becomes the armature's child |
| `k.bevel(obj, width, segments, angle)` | rounds an object's sharp edges, and projects its UVs afresh (`project_uvs`) |
| `k.project_uvs(obj)` | UVs projected onto each face from the axis it faces most (box mapping) |
| `k.unwrap(obj, angle)` | UVs for an object made with `bpy`, by Blender's Smart UV Project, scaled to metres |

Every object needs a name of its own: the game finds parts and markers by name, so where Blender
would rename a second `Seat` to `Seat.001`, kiln fails the build.

Recipes can also use `bpy` directly for anything the kit lacks. `kiln.geometry` builds meshes
as plain data, and is tested without Blender:

- shapes: `box`, `loft` (through rings of points, from `ring` and `mirrored_ring`), `lathe`,
  `sweep` (a round tube along a path of points, a radius at each, its rings following the
  path without twisting), `icosphere`, and `symmetric` (a half joined to its mirror image);
- changes: `translated`, `rotated`, `scaled`, `merged`, `inset` (a face shrunk in, framed by
  new faces) and `extruded` (a face moved out or in, with walls);
- material slots (`materials`, `with_material`, `with_materials`), UVs (`uvs`,
  `projected`) and colours (`colors`, `with_colors`): a colour for each face corner from a
  function of its position, exported as the mesh's vertex colours (`COLOR_0`), as data for a
  game's shaders (Godot doesn't draw them unless a material asks);
- `value_noise`, smooth noise from -1 to 1 for moving points about (a rock's lumps).

### UVs

Every mesh kiln exports has UVs (glTF's `TEXCOORD_0`), in metres along the surface, so a
texture that repeats every UV unit is drawn a metre to a tile on every model (one `tile`
metres across takes a UV scale of 1 / `tile`). Each shape gives its own:

- `box` is projected onto each face from the axis it faces (`projected`), each face a
  rectangle of its own size.
- `loft` and `lathe` run u round the rings from their first point and v along the loft. u is
  the share of the way round a ring times the rings' mean length round, so a texture is
  squeezed round a narrow ring rather than sheared; v is the mean distance from one ring to
  the next, the length along a lathe's profile. Caps are projected.
- A `Mesh` made from bare vertices and faces has none until `projected` gives it some, and
  `k.mesh` projects one that has none. `merged` projects either part that lacks them.

Moving, turning and scaling a mesh keeps its UVs, so its texture moves and stretches with
it. A face's UVs run counter-clockwise, as its corners do seen from outside, so a texture
isn't mirrored; seen from outside, a side's v runs up, and on the top and bottom v runs
forward (-Z).

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
points up the image, as Godot expects), `roughness`, `height` (16-bit), `occlusion`,
`metallic`, and `orm`: occlusion, roughness and metallic packed in red, green and blue, as
Godot's ORMMaterial3D reads them (no occlusion counts as 1, no metallic as 0). The normal map
is worked out from the height, `relief` metres between height 0 and 1. Every map
tiles: noise and Voronoi are sampled on a torus in four dimensions, so the left edge meets
the right and the top the bottom, and stripes and bands come in whole numbers per tile.
Scales are per metre of the game's surface, `tile` metres to a tile.

A node graph is worked out one pixel at a time, so it can't see the pixels round each one:
to put dirt in cracks or wear on edges, `t.bake` bakes a value (the height) partway through,
and the masks from it (`kiln.masks`, in numpy, wrapping round the edges so they tile) come
back into the graph as values. Each bake takes as long as a map's.

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
| `t.bake(value)` | the value baked into the tile's pixels now (usually the height), for the masks below |
| `t.blurred(baked, radius)`, `t.ridges(baked, radius)`, `t.hollows(baked, radius)` | values worked out from a baked height, looking `radius` metres round each point: it blurred; how far each point stands above the height round it (crests, where a surface wears) or below it (cracks and gaps, where dirt gathers), 0 to 1 |
| `t.occlusion(baked, radius, relief)` | ambient occlusion from a baked height: 1 open to the sky, toward 0 deep in a hollow |
| `t.output(albedo, roughness, height, occlusion, metallic)` | which colour and values become the maps. A value given as a number isn't baked, and `kiln.lock.json` keeps it (the texture's `values`), so a recipe can leave its map out and the material take the number |

## A sound recipe

```python
from kiln import sound


@sound(seconds=(0.5, 2.0))
def build(s):
    strike = s.impulses(1.5, [0.002])
    bell = sum(s.resonator(strike, 660.0 * ratio, 0.6 / ratio) for ratio in (1.0, 1.18, 1.5, 2.0))
    return s.fade(bell, 0.0, 0.3)
```

A sound recipe returns its samples as a numpy array, about -1 to 1 (shape `(n,)` for mono,
`(2, n)` for stereo), or a dict of them by name, and kiln writes `<stem>.wav` or one
`<stem>_<name>.wav` for each: 16-bit PCM at the spec's `rate`. Kiln scales all of a recipe's
sounds by one factor so the loudest peak is at `peak` dB (-1 by default), so their levels stay
as the recipe set them against each other: an engine's loops at different revs, a small splash
and a big one. With `loop=True` every sound loops, and its WAV file carries the loop (a `smpl`
chunk), which Godot's importer reads. With `format="ogg"` the sounds are written as Ogg Vorbis
instead (quality 6, by ffmpeg, the same bytes every build), about a tenth the size, for music;
an Ogg file has no loop points, so a looping one is marked to loop in the game (in Godot,
`loop=true` in its `.import` file).

`s` (`kiln.audio.SoundKit`) makes and shapes signals. A setting that changes over time (a
cutoff, a frequency) can be a number or an array with a value for each sample.

| Call | Gives |
|---|---|
| `s.samples(seconds)`, `s.time(seconds)`, `s.silence(seconds)`, `s.length(x)` | sample counts, each sample's time, silence, a sound's length |
| `s.line(seconds, points)`, `s.decay(seconds, time, attack)`, `s.adsr(seconds, attack, decay, sustain, release)` | envelopes: straight lines through (time, value) points, an exponential decay, a held note's |
| `s.phase(freq)`, `s.sine(freq, seconds, phase)`, `s.saw`, `s.square(freq, seconds, width)`, `s.triangle` | oscillators that don't alias; `phase` (in cycles) also frequency-modulates |
| `s.noise(seconds, seed, color)` | white, pink or brown noise, the same for the same seed |
| `s.impulses(seconds, times, amps)`, `s.dust(seconds, density, seed)` | clicks at exact times (between samples too) or at random ones, to ring resonators and filters with |
| `s.lowpass`, `s.highpass(x, cutoff, q, order)`, `s.bandpass`, `s.notch(x, centre, q)`, `s.eq(x, freq, gain_db, q)`, `s.lowshelf`, `s.highshelf(x, freq, gain_db)`, `s.smooth(x, cutoff)` | filters (from the Audio EQ Cookbook) |
| `s.resonator(x, freq, decay, gain)`, `s.formants(x, bands)` | a mode that rings like a struck bar or a bubble; band-passes side by side, as a pipe or a body colours a sound |
| `s.gain(x, db)`, `s.db(value)`, `s.saturate(x, drive)`, `s.fade(x, fade_in, fade_out)` | levels, soft clipping, fades |
| `s.compress(x, threshold_db, ratio, time, makeup_db)` | evens out a part or a mix: what is louder than the threshold is turned down by the ratio |
| `s.delay(x, seconds, feedback)`, `s.reverb(x, seconds, damping, mix, predelay, seed, stereo)`, `s.convolve(x, response)` | echoes and combs, a room's or the open air's tail, any impulse response |
| `s.varispeed(x, speed)` | a sound played faster or slower, as a tape is |
| `s.pad`, `s.mix(*sounds)`, `s.arrange(seconds, events)`, `s.pan(x, position)` | putting sounds together and in time, and in stereo |
| `s.rng(seed)` | a numpy random generator for the recipe's own choices |

In a looping recipe the kit makes everything wrap round: oscillators hold whole cycles, noise
is made over its own length, filters, resonators, delays and reverbs run on from the end into
the start, and what `arrange` places past the end comes in again at the start.

## Checks

`@model(...)` takes what the build must meet. Every check runs on every build:

| Field | Checks |
|---|---|
| `max_triangles` | the total triangle count is within budget |
| `size`, `size_tolerance` | the bounding box (x, y, z; None skips an axis) is within the tolerance (2%) |
| `markers` | an object with each name exists |
| `materials` | each material is on at least one face (for those the game finds by name) |
| `bones` | a bone with each name exists (and no bone has an object's name: glTF makes a node of each) |
| `closed` (default True) | every mesh is closed: each edge shared by exactly two faces |
| `allow_self_intersections` (default False) | no connected part of a mesh cuts through itself (separate parts and objects may overlap) |

Faces with no area always fail, and so do a skinned mesh's vertices whose weights on the
bones don't add up to 1 (posed, they would be left behind), and faces whose UVs cover no area (a texture would smear
across them). `report.json` gives each mesh's surface area and its UVs' (`area`, `uv_area`):
the two match where the UVs are in metres.

A texture always gets two checks: every map tiles (its wrap-round edges differ no more than
neighbouring pixels do inside it, within 1.5 times), and every value lies between 0 and 1.
A map of one value (within an 8-bit step) gets a note in the build's output: the material
could take the number instead.

Every sound is checked too:

| Check | Fails when |
|---|---|
| numbers | a sample isn't a number, or every sound is silent |
| `seconds` | a sound is shorter or longer than `(shortest, longest)` |
| offset | a sound's mean is more than 0.01 off zero (a high-pass takes a DC offset out) |
| seam (loops) | the step from the last sample to the first is over 1.5 times the biggest steps inside (the 99.9th percentile) |
| ends (others) | the first or last sample is more than 0.02 from zero, or the last millisecond peaks above 0.12 of the sound's peak: it would click on or stop short |
| clipping | with `peak=None`, a sample goes past full scale |

## Preview sheets

Each build renders `<reports>/<id>/preview.png`. A sound recipe's has a row for each sound:
its name, length, peak and RMS, its waveform, its spectrogram (log frequency from 30 Hz) and,
for a loop, its last and first few milliseconds joined at the seam. A texture's shows each
map tiled two by two, so a seam would show as a cross. A model's has four rows:

- the front, side, top and three-quarter views, with markers as small magenta diamonds, each
  material drawn as the game will where `kiln.toml` says how (below), in its own colour
  elsewhere;
- the front and back three-quarter views in a checker on the UVs, so stretched or sheared
  UVs show: squares about a sixteenth of the model across, red rising along u and green
  along v;
- the same two views of its triangles, as the game gets them, over the model in grey.

`report.json` beside it holds the measurements and problems. When an asset is built again
and its sheet differs, `changes.png` beside it shows the sheet before, the sheet now, and
the pixels that changed in red, and the build's output says how much of the sheet changed.

A game textures or paints some materials itself, by name; `[preview.materials]` in
`kiln.toml` says how the sheet should draw them: in a texture the project builds (its albedo
map, at its `tile`), or in a colour times the material's own (as the game paints a light
grey part a darker shade), or both. A name ending in `*` matches the start of a name.

```toml
[preview.materials]
Rock = { texture = "textures/rock" }
WoodDark = { texture = "textures/wood", color = "#8c8075" }
"Suit*" = { color = "#d91f24" }
```

## Tests

```sh
uv run --project pipeline pytest pipeline/tests
```

Tests that need Blender are skipped when it isn't installed; the sound tests don't need it. `examples/basics` is a small
project the tests build.
