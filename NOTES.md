# Waterline: project notes

A jet ski racer in Godot 4.7 (Forward+, typed GDScript, Jolt physics), a spiritual successor to a
1996 jet ski racer. All names, art, sound and courses are original.

## Status

| Milestone | State |
|---|---|
| 1. Water | Done (session 1) |
| 2. Jet ski on open water | In progress (session 1) |
| 3–8 | Not started |

Run the game: `godot --path /home/astrosteveo/Projects/waterline` (or open the project in the
editor and press F5). The main scene is `res://levels/water_test.tscn` until milestone 2 is done.

Checks use `gdh`, a command-line harness that runs the game off-screen on the GPU, steps it frame
by frame with scripted input, takes screenshots and evaluates expressions in the running game.
While gdh holds the game between commands, the scene tree is paused.

## Layout

```
water/          WaveSet + GerstnerWave resources, the CPU wave math, the Ocean autoload,
                OceanSurface (the drawn water) and the water shader
water/presets/  WaveSet presets (open_sea.tres)
environment/    sky shader, day environment, Sun, Terrain (seabed + islands), Rock
cameras/        FreeCamera
debug/          WaterProbe (test marker placed by the CPU wave function)
levels/         playable scenes (water_test.tscn)
test/           water_match.tscn (GPU/CPU height comparison), wave_bench.gd
docs/screenshots/  evidence screenshots for finished milestones
captures/       gdh output, git-ignored and hidden from Godot (.gdignore)
```

## How the water works

- **One set of numbers.** A `WaveSet` resource (`water/wave_set.gd`) holds up to 16
  `GerstnerWave`s (direction, wavelength, amplitude, sharpness, phase, speed). `OceanSurface` packs
  them into shader uniforms; the `Ocean` autoload uses the same resource for physics queries.
- **The wave formula.** A surface point resting at `p` moves to
  `p + D * sharpness * A * cos(f)` horizontally and `A * sin(f)` vertically, with
  `f = k * dot(D, p) - omega * t + phase`, `k = TAU / wavelength`, `omega = sqrt(g * k)`. The GPU
  copy is `water/gerstner.gdshaderinc`; the CPU copy is `WaveSet.surface_point()` / `sample()`.
  Keep them in step.
- **Height at a world position.** Because points move sideways, the CPU finds the rest position
  whose displaced point lies above (x, z) with up to 4 Newton iterations on the 2×2 Jacobian
  (`WaveSet.find_rest_position`), then evaluates the height and normal there. Measured residual:
  0.015 mm worst case over 2000 random points.
- **Cost.** `Ocean.height_at()` takes about 5.4 µs and `Ocean.sample()` (height, normal, water
  velocity, fold) about 6.7 µs in GDScript with the 8-wave `open_sea` preset.
- **Phases are computed on the CPU** in double precision and passed per wave (`wave_phase[]`), so
  the shader's 32-bit floats never see a large time value.
- **Time.** `Ocean.time` advances once per physics tick, before every other node
  (`process_physics_priority = -1000`). Rigid bodies read `Ocean.time` in `_integrate_forces`
  (start of step); nodes placed in `_physics_process` read `Ocean.end_time`; the shader draws at
  `Ocean.render_time()`, which follows physics interpolation. Never use the shader's `TIME` for
  waves: it keeps running while the game is paused, including while gdh holds it.
- **The mesh.** `OceanSurface` uses a 1024×1024-cell `PlaneMesh` (about 1M vertices). The vertex
  shader maps it so the middle quarter keeps 0.3 m spacing (±38 m around the camera) and the outer
  rings spread exponentially to 6 km. The mesh follows the camera in whole 0.3 m steps, so the fine
  vertices stay on a fixed world lattice and the waves don't shift or shimmer as the camera moves. Waves are faded only where the vertex
  spacing exceeds 1/8 of their wavelength, which never happens within 38 m of the camera, so the
  physics and the picture agree wherever a jet ski can be seen up close. Normals are computed per
  pixel from the same waves, faded where a wave is shorter than a few pixels.
- **Look.** Depth-based colour from the depth buffer (shallow turquoise to deep blue), refraction
  of what is below, absorption per colour channel, crest glow toward the sun, foam where the
  Jacobian determinant ("fold") shows crests squeezed together and in water shallower than 0.35 m,
  two scrolling noise normal maps for ripples, and Godot's own specular and sky reflection
  (SPECULAR 0.25, which is water's 2% reflectance).

## Verification done

- **GPU vs CPU height, numerically.** `res://test/water_match.tscn` draws the water from straight
  above with `test/ocean_height_debug.gdshader`, which encodes the drawn height in the red and
  green channels. `scene.check()` reads the frame back and compares 14,400 pixels with
  `Ocean.height_at_time()`. Results at three wave times (0.48 s, 10.00 s, 10.02 s): mean error
  0.63 mm, RMS 0.80 mm, worst 3.4 mm (at the edge of the fine region, where the shortest waves
  start to fade). Run it again with:
  `gdh live start --project . --session wm --scene res://test/water_match.tscn`, then
  `gdh live step 30 --session wm` and `gdh live eval "scene.check()" --session wm`.
- **GPU vs CPU height, visually.** Five `WaterProbe` poles in `water_test.tscn` are placed every
  physics tick at the CPU height; each turns from yellow to magenta exactly at that height, with
  black rings every 5 cm. In `docs/screenshots/m1_probe_waterline.png` (foam turned off) the water
  meets every pole at the colour change: no yellow under the surface, no magenta above it.
- **Frame time.** `gdh live bench 600` on the RTX 5080 at 1920×1080: GPU median 0.61 ms, p99
  0.86 ms; CPU median 0.08 ms.
- **Free camera.** Scripted input: `cam_forward` for 60 frames moved it 13.6 m, `cam_up` with
  `cam_fast` raised it 21 m in 30 frames, and `cam_look` plus a mouse move turned it.

## Controls (Input Map actions)

| Action | Keyboard | Gamepad |
|---|---|---|
| throttle | Space, J | A, right trigger |
| steer_left / steer_right | A / D, Left / Right | left stick X, D-pad |
| lean_forward / lean_back | W / S, Up / Down | left stick Y (up = forward), D-pad |
| reset_craft | R | Back |
| toggle_camera | C | Y |
| toggle_debug | F3 | |
| cam_forward/back/left/right | W S A D (free camera only) | |
| cam_up / cam_down | E / Q | |
| cam_fast | Shift | |
| cam_look | hold right mouse button | right stick (cam_look_*) |
| cam_speed_up / down | mouse wheel | |

## Decisions and why

- **PlaneMesh plus a shader mapping instead of a hand-built clipmap.** One continuous grid has no
  T-junction cracks, Godot builds it in C++ quickly, and the shader knows the spacing everywhere,
  which the wave fade needs.
- **Newton's method for the inverse.** Fixed-point iteration would shrink the error by only about
  0.4 per step with these waves (the fold). Newton's method shrinks it quadratically, so 4
  iterations reach 0.015 mm.
- **Wave preset `open_sea`:** a 42 m main swell (0.7 m amplitude), a 27 m cross swell, a 19 m
  third swell and five short chop waves down to 3.1 m. Sum of amplitudes 1.66 m, fold 0.38 (the
  surface can't fold over below 1.0). The swells are steeper than real ocean swells so the jet ski
  can catch air off them.
- **Foam threshold** (`crest_foam_start` 0.11, `crest_foam_full` 0.42): lower values covered the
  sea in evenly spaced blobs that made the repeating wave pattern obvious from above.
- **The headless gdh editor writes `shader_parameter/x = null` lines** into materials when it
  resaves them, and dropped the water material's textures once when a global shader uniform was
  missing. Prefer writing `.tres`/`.tscn` files by hand (without a uid if unknown) and leave the
  bridge stopped unless needed.

## Known issues and rough edges

- The terrain is flat-shaded with 4 m cells, so the edges of shallow areas show straight facets
  through the water. A finer grid near shores would smooth this.
- Eight waves repeat visibly when seen from high above; at riding height it isn't noticeable.
