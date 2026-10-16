# Waterline: notes for agents

A jet ski racer in Godot 4.7 (typed GDScript, Jolt physics). The [README](README.md) says how to run
it; the [wiki](https://github.com/astrosteveo/waterline/wiki) explains how each part works and why;
the issues are the backlog. The Godot project is in `godot/` (where `res://` points); the README
lists the other top-level folders. Read the wiki page for the part you're changing first.

## Things that are easy to break

- **The waves exist twice:** `water/gerstner.gdshaderinc` (GPU) and `WaveSet.surface_point()` /
  `sample()` (CPU). Change both or the craft floats off the drawn water. `res://test/water_match.tscn`
  checks they agree.
- **Wave time is `Ocean.time` / `Ocean.render_time()`, never the shader's `TIME`**, which runs on
  while the game is paused or held by gdh.
- **Races must replay exactly from a seed.** Don't draw from the global random generator in race
  code (a `GPUParticles3D` does when it's made); use a seeded `RandomNumberGenerator`, as
  `Race._mistake_rng` does.
- **Courses come from `tools/courses/*.json`.** Edit the spec and rerun
  `python3 tools/courses/course_tool.py SPEC --scene --thumb`; the tool overwrites the course scene
  and its `.course.tres`.
- **Write `.tres`/`.tscn` by hand** rather than resaving through the headless editor, which adds
  `shader_parameter/x = null` lines to materials.
- **Models and textures built by kiln come from `art/`.** Edit the recipe and run
  `uv run --project pipeline kiln build`, never the `.glb` or `.png` in `godot/assets/`; commit
  the recipe, the built files, their `.import` files and `art/kiln.lock.json` together. Look at
  the preview sheet in `build/kiln/<id>/preview.png`, then at the model in the game. `pipeline/`
  must stay free of anything Waterline-specific, so it can become its own repository.
- New courses, cups and weathers are found by file name (`*.course.tres`, `*.cup.tres`,
  `*.weather.tres`); no list to update.

## Checking your work

- CI (`godot/test/check_project.sh`) only checks that everything loads. Gameplay is checked by the gdh
  scenarios in `godot/test/scenarios/`, which need the GPU and run locally: `gdh test --project godot`
  (or `gdh scenario run --project godot FILES`). Run the ones for what you changed before calling it
  done, and add a scenario for new behaviour.
- After a change to physics, computer riders, courses or waves, run the every-course race on a few
  seeds (`gdh live start --project godot --scene res://test/every_course.tscn --seed N`, optionally
  `-- --courses id,id`; about 3 minutes a seed): no crashes, at most 3 misses a rider.
- Look at what you changed: `gdh capture` for a scene or shader, `gdh live` to drive it.
- gdh quirks: `eval` takes no lambdas, ternaries or class names (call statics through an
  instance); gdh holds the game with `SceneTree.paused`, so it can't show that pausing stops a
  race; `gdh live reload` doesn't hook up a newly added `_input`, so restart instead.
- Builds need `godot-mono` (only the `.mono` export templates are installed):
  `GODOT=/usr/bin/godot-mono gdh export --project godot --preset Linux --smoke 10`, and `--preset Windows`.

## Style

Match the code around you: typed GDScript, `##` doc comments in plain full sentences on every
class, export and public function, explaining why where it isn't obvious. Tuning numbers live in
resources (`JetSkiTuning`, `RaceRules`, the `.tres` files), not in code.

## Working with GitHub

- Small or docs-only changes go straight to `main`. Anything that changes how the game runs gets
  an issue, a branch `<number>-<slug>` and a pull request with "Closes #N", merged after CI passes.
- Ask before merging, closing issues or milestones, or deleting branches. Commit and push only
  when asked or as part of agreed work. No AI attribution lines in commits or pull requests.
- When a change alters how something works, update its wiki page
  (`git clone https://github.com/astrosteveo/waterline.wiki.git` outside the repo, edit, push).
- A bug you won't fix now: say so and offer to file an issue, labelled bug or enhancement plus
  priority:high, medium or low.
