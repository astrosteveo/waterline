# Waterline's art

The recipes for the game's models, textures and sounds, built by [kiln](../pipeline/README.md)
into `godot/assets/`: the craft, the riders, the course scenery (`models/course`, `harbor`,
`rocks`, `plants`, `props`), the textures the terrain, rocks and wood are drawn in
(`textures/`), and every sound (`audio/`): each craft's engine, the water and the race's own.
Edit a recipe here, never the built file, then from the repository root:

```sh
uv run --project pipeline kiln build      # builds what changed; previews go to build/kiln/
```

Commit the recipe, the built files (and the `.import` files Godot writes for them) and
`kiln.lock.json` together. Recipes are in game space: metres, +X right, +Y up, -Z forward.
Shared code goes in files or folders whose names start with `_`.

The game draws a model's Rock, Wood and WoodDark materials in these textures through its
import settings: the model's `.glb.import` remaps them to `godot/environment/materials/`.
A new model with one of those materials needs the same lines in its `.import` file (copy them
from `godot/assets/models/rocks/boulder_a.glb.import`).

The music (`audio/music/`) is written as Ogg Vorbis, which carries no loop points: each
track's `.ogg.import` has `loop=true`. For a new track, set it after Godot first imports the
file, then delete the track's files in `godot/.godot/imported/` so Godot imports it again
(it doesn't notice a changed `.import` file on its own).
