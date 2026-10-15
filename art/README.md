# Waterline's art

The recipes for the game's models, built by [kiln](../pipeline/README.md) into `godot/assets/`.
Edit a recipe here, never the built file, then from the repository root:

```sh
uv run --project pipeline kiln build      # builds what changed; previews go to build/kiln/
```

Commit the recipe, the built files (and the `.import` files Godot writes for them) and
`kiln.lock.json` together. Recipes are in game space: metres, +X right, +Y up, -Z forward.
Shared code goes in files or folders whose names start with `_`.
