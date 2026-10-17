# Waterline: notes for agents

A jet ski racer in Godot 4.7 (typed GDScript, Jolt physics). The [README](README.md) says how to run
it; the [wiki](https://github.com/astrosteveo/waterline/wiki), checked out in `.wiki/`, explains
how each part works and why; the issues are the backlog. The Godot project is in `godot/` (where
`res://` points); the README lists the other top-level folders. Read the wiki page for the part
you're changing first.

The game aims for a sim feel, though a 1996 arcade racer inspired it: design mechanics, controls
and tuning from how a real jet ski behaves, and say so when realism would cost fun or clarity.

## Things that are easy to break

- **The waves exist twice:** `water/gerstner.gdshaderinc` (GPU) and `WaveSet.surface_point()` /
  `sample()` (CPU). Change both or the craft floats off the drawn water; `res://test/water_match.tscn`
  checks they agree. Wave time is `Ocean.time` / `Ocean.render_time()`, never the shader's `TIME`,
  which runs on while the game is paused or held by gdh.
- **Races must replay exactly from a seed.** Don't draw from the global random generator in race
  code (a `GPUParticles3D` does when it's made); use a seeded `RandomNumberGenerator`, as
  `Race._mistake_rng` does.
- **Courses, models, textures and sounds are built, not edited.** Courses come from
  `tools/courses/*.json` (`python3 tools/courses/course_tool.py SPEC --scene --thumb`); models,
  textures and sounds from the recipes in `art/` (`uv run --project pipeline kiln build`;
  `art/README.md` says what to commit). Look at kiln's preview sheet in
  `build/kiln/<id>/preview.png`, then at the model in the game; for a sound, a `gdh movie`'s
  `audio.png`. You can't hear the sounds, so ask the user to listen. The announcer's lines are
  recorded by `tools/voice/voice_tool.py` with VoiceStudio (`--check` hears them back).
  `pipeline/` must stay free of anything Waterline-specific, so it can become its own repository.
- **Write `.tres`/`.tscn` by hand** rather than resaving through the headless editor, which adds
  `shader_parameter/x = null` lines to materials.

## Checking your work

Check the thing you're changing while you change it, not with long batches of scenarios at the end.

- While working, run the narrowest check of it often: `gdh capture` for a scene or shader, a short
  `gdh live` session, or the scenario that covers it.
- Before calling it done, run the scenarios in `godot/test/scenarios/` that reach the changed code
  (grep them for the scene, node or feature; `gdh scenario run --project godot FILES`), add one for
  new behaviour, and say which ran and why.
- Only a change that could break racing (physics, collision, computer riders, courses, waves) needs
  the every-course race on a few seeds (the wiki's Testing page; about 3 minutes a seed): no
  crashes, at most 3 misses a rider. Skip the full `gdh test` otherwise, and runs whose result is
  already known; if a check's worth is doubtful, ask.
- CI checks that everything loads and runs kiln's tests, skipping those that need Blender; the
  scenarios need the GPU and run locally.
- Builds need `godot-mono` (only the `.mono` export templates are installed):
  `GODOT=/usr/bin/godot-mono gdh export --project godot --preset Linux --smoke 10`, or `Windows`.

## Style

Match the code around you: typed GDScript, `##` doc comments in plain full sentences on every
class, export and public function, explaining why where it isn't obvious. Tuning numbers live in
resources (`JetSkiTuning`, `RaceRules`, the `.tres` files), not in code.

## Working with GitHub

- Small or docs-only changes go straight to `main`. Anything that changes how the game runs gets
  an issue, a branch `<number>-<slug>` and a pull request with "Closes #N", squash-merged after CI
  passes. GitHub deletes the merged branch; delete the local one with `git branch -D`.
- Ask before merging, closing issues or milestones, or deleting branches. Commit and push only
  when asked or as part of agreed work. No AI attribution lines in commits or pull requests.
- `git -C .wiki pull` before reading the wiki (if it's missing,
  `git clone https://github.com/astrosteveo/waterline.wiki.git .wiki`). When a change alters how
  something works, update its page there, then commit and push inside `.wiki/`.
- A bug you won't fix now: say so and offer to file an issue, labelled bug or enhancement plus
  priority:high, medium or low.
