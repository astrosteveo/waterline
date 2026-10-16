# Waterline's art

The recipes for the game's models and textures, built by [kiln](../pipeline/README.md) into
`godot/assets/`: the craft, the riders, the course scenery (`models/course`, `harbor`, `rocks`,
`plants`, `props`) and the textures the terrain, rocks and wood are drawn in (`textures/`).
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
