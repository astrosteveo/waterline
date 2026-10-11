# Waterline: project notes

A jet ski racer in Godot 4.7 (Forward+, typed GDScript, Jolt physics), a spiritual successor to a
1996 jet ski racer. All names, art, sound and courses are original.

## Status

| Milestone | State |
|---|---|
| 1. Water | Done (session 1) |
| 2. Jet ski on open water | Done (session 1) |
| 3–8 | Not started |

Run the game: `godot --path /home/astrosteveo/Projects/waterline` (or open the project in the
editor and press F5). The main scene is `res://levels/open_water.tscn`: one jet ski on open water
with rolling swells, islands, rocks and floating crates. `godot --path . -- --demo` rides a fixed
sequence of controls by itself. `res://levels/water_test.tscn` is the milestone-1 water scene with
a free camera.

Checks use `gdh`, a command-line harness that runs the game off-screen on the GPU, steps it frame
by frame with scripted input, takes screenshots and evaluates expressions in the running game.
While gdh holds the game between commands, the scene tree is paused.

## Layout

```
water/          WaveSet + GerstnerWave resources, the CPU wave math, the Ocean autoload,
                OceanSurface (the drawn water), the water shader, Floater (floating props),
                ShoreMap (static scenery heights for shoreline foam)
water/presets/  WaveSet presets: open_sea.tres (choppy), rolling_swell.tres (open-water level)
environment/    sky shader, day environment, Sun, Terrain (seabed + islands), Rock
jetski/         JetSki (RigidBody3D physics), JetSkiTuning (every tuning number),
                RiderControls, PlayerInput; tuning/default.tres; model/ (placeholder craft
                and rider, swappable)
cameras/        ChaseCamera, FreeCamera, CameraSwitcher
props/          crate.tscn (a Floater)
debug/          WaterProbe, DebugHud (F3 readout), RideRecorder (ride statistics),
                DemoDriver (scripted ride, --demo)
levels/         open_water.tscn (main), water_test.tscn
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
  (SPECULAR 0.25, which is water's 2% reflectance). Detail too fine to draw at a distance turns
  into roughness, so far water doesn't become a mirror.
- **Refraction near objects.** The refracted lookup is skipped when any of 4 neighbouring depth
  texels is in front of the water. With 4× MSAA, an edge pixel's colour blends the object with
  what's behind it while its depth holds only one of them; refracting those pixels drew a
  broken cyan outline of the craft and rider, shifted sideways.
- **Shoreline foam only on scenery.** The shallow-water foam comes from the depth buffer, so it
  used to also coat anything floating just under the surface: a white block behind the jet ski's
  stern. `ShoreMap` (one per level) now renders the static scenery's heights from straight above
  once at load (a SubViewport with an orthographic camera and a full-screen pass that turns
  depth into height, two 8-bit channels, 0.78 m texels over 800 m). The water gives a point under
  it shoreline foam only if that point lies at most 0.5 m above the highest scenery in the 3×3
  texels around it. Rocks and beaches keep their foam; hulls, crates and buoys get none.
- **Visual layers.** 1 = static scenery (terrain, rocks, ramps, anything that should get
  shoreline foam), 2 = moving things (`JetSkiModel` and `Floater` set it on their meshes), 3 =
  water, 20 = the ShoreMap capture pass, which the game cameras exclude (it also discards itself
  for any other camera).

## How the jet ski works

`JetSki` (`jetski/jetski.gd`) is a `RigidBody3D` whose forces are all added in
`_integrate_forces`, with its own damping (Godot's default damping is replaced with 0). Local
frame: -Z forward, +X right, origin on the keel at mid-length. Each tick:

1. **Hull points.** The 8 `Marker3D` children of `HullPoints` (bow, three pairs along the sides,
   stern) each sample the water. A submerged point pushes along the wave normal with
   `buoyancy_stiffness * depth` (capped at `max_point_depth`), and the water resists the point's
   motion through the surface: `water_damping * speed + slam_damping * speed²` pressing in,
   `water_damping * release_share * speed` coming out. Damping fades in over the first
   `wet_depth` of depth. Pushing along the normal is what lets a wave face push the craft
   sideways or back.
2. **The frame on the water.** Forward and right are the hull's axes projected onto the average
   wet normal; speeds are measured relative to the water's orbital velocity, so waves carry the
   craft.
3. **Thrust** along that forward direction, scaled by how deep the rear (intake) points are: no
   water at the intake, no thrust. It also lifts the bow a little (`thrust_pitch_lever`).
4. **Drag** along the hull (linear + quadratic), more when the hull is deep, and **planing lift**
   that grows with speed².
5. **Grip:** a sideways force that cancels sideways speed at `grip_rate`, capped at `grip_g`. Past
   the cap the craft slides (`sliding`).
6. **Steering** drives the yaw rate toward `steer * turn rate` (the turn rate falls from
   `turn_rate_low` to `turn_rate_high` with speed; with the throttle off only `coast_steer` of it is
   left). A slip limit stops the nose rotating further once the slip angle passes `slip_limit`, so
   a slide can't become a spin. A roll torque banks the craft into the turn.
7. **Lean** pitches the craft on the water, fading out at `lean_forward_max_pitch` /
   `lean_back_max_pitch` relative to the water, with a stiff push back past them so it can't
   stand on its tail. Forward lean multiplies grip, turn rate and drag up (nose dug in); back lean
   multiplies them down. Full steer + forward lean at speed is **carving**: more turn and grip,
   more drag (`carving` flag, for spray later).
8. **Air:** with no hull point wet, lean sets a pitch rate (fading in over the first
   `air_control_delay` of air time, and stopping at `air_pitch_limit` from the horizon), steer sets
   a yaw rate about the vertical, and the roll levels out toward a small bank into the turn. Water
   and air control blend by how much of the hull is wet.
9. **Capsize:** upside down in the water for `capsize_reset_time` seconds puts the craft upright
   where it is (a stand-in until milestone 4's crash and remount).

Controls come in through `JetSki.controls` (`RiderControls`: throttle, steer, lean). `PlayerInput`
fills them from the Input Map (keyboard steer and lean ease in over 0.12–0.15 s); a computer rider
can fill them the same way. The model (`jetski/model/jetski_model.tscn`) is only visual: the
physics never reads it, and any Node3D scene can replace it. If it has
`set_pose(steer, lean, throttle, airborne)`, the craft calls it every frame.

`ChaseCamera` follows from 6.4 m behind and 2.4 m above, turning toward a heading that blends the
nose with the direction of travel, with separate lags for yaw (3.5/s), height (2.5/s, or 0.8/s
while the craft is in the air, so a jump shows as the craft rising in the frame) and position
(12/s). After smoothing it enforces two hard limits: at least 0.9 m above the water under it, and
high enough that the line of sight to the craft clears the water by 0.3 m at three points. A ray
cast pulls it in front of islands and rocks. FOV widens from 70° to 79° with speed.

## Jet ski tuning (jetski/jetski_tuning.gd, values in jetski/tuning/default.tres)

| Group | Values | Why |
|---|---|---|
| Body | mass 300 kg, centre of mass (0, 0.32, 0.12), inertia (170, 190, 50) kg m² | A craft plus rider; inertia of a 3 m × 1.1 m × 1 m box with the mass near the middle. |
| Buoyancy | stiffness 3100 N/m per point, max depth 0.45 m | Floats the hull about 12 cm deep at rest; bob frequency about 1.4 Hz. |
| Water damping | 600 N/(m/s) both ways (×0.7 coming out), slam 45 N/(m/s)² | With damping only on the way in, landings bounced like a trampoline (−4 m/s in, +3 m/s out, airborne 33% of a crossing run). Damping both ways (close to critical) fixed it: airborne 9%. |
| Planing lift | 2.5 N/(m/s)² | 4.5 lifted the hull so high that it skipped off every crest. |
| Engine | thrust 2400 N, response 6/s | 0 to 49 km/h in 4 s; top speed about 57–59 km/h on the rolling swell. |
| Drag | 30 N/(m/s) + 6.1 N/(m/s)², ×1.6 when deep | Sets the top speed with the thrust; off the throttle the craft slows from 42 to 7 km/h in 3 s. |
| Turn rate | 1.6 rad/s low speed, 1.15 rad/s at 17.5 m/s | A U-turn at full speed takes about 2.5 s, as in the original. 1.3 rad/s turned too fast. |
| Grip | rate 12/s, limit 1.9 g, slip limit 28° | A neutral full-lock turn at speed sits right at the limit with 6–10° of slip; back lean slides (up to 26°). |
| Bank | 20° target, 9000 N m/rad, roll damping 600 | Lower stiffness only reached 5–8° against the buoyancy's roll resistance; now 10–15° in hard turns, with no wobble. |
| Lean | 900 N m, limits 10° nose-down / 15° nose-up | Without limits, holding lean back stood the craft on its tail (66°) and lean forward buried the nose. |
| Lean effects | forward: grip ×1.35, turn ×1.3, drag ×1.15; back: ×0.75, ×0.8, ×0.95 | Forward lean turns tighter and costs speed; back lean lifts the nose and slides more. |
| Carving | steer ≥ 0.8, lean ≥ 0.5, ≥ 7 m/s: turn ×1.25, grip ×1.2, drag ×1.2 | About 125°/s; a carved U-turn takes about 1.5 s and costs about 30% of the speed. |
| Air | pitch 1.4 rad/s (limit 50°), yaw 0.6 rad/s about the vertical, response 4/s | Enough to level the nose for a landing; 2 rad/s let a held lean flip the nose to −64°. |
| Air control delay | 0.35 s | The lean's air pitch fades in over this much air time, so a hop while carving with a forward lean keeps the nose above −16° (it dived to −38°). |
| Air roll | level toward 10° × steer, stiffness 12/s², damping 5/s | Without it, a turn that launched off a swell kept rolling to 46–80° and landed on its side; now under 26° in the air and 14° at touchdown. |

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

### Milestone 2 (jet ski on open water)

Measured with gdh on `open_water.tscn` (seed 1, rolling swell), 20 s runs at full throttle:

| Run | Average / top speed | Airborne | Jumps (≥ 0.4 s) | Longest air | Highest |
|---|---|---|---|---|---|
| Across the swells (yaw 0) | 52.8 / 59.9 km/h | 11% | 8 (0) | 0.33 s | 0.24 m |
| Head-on into the steep swell (yaw 2.008) | 46.2 / 51.2 km/h | 30% | 14 (7) | 0.83 s | 1.17 m |
| With the swells (yaw −1.134) | 50.0 / 58.9 km/h | 0% | 0 | | |

Full-lock turns from 54 km/h over 2.5 s: neutral 68°/s (171°, path radius about 12 m, ends at
43 km/h, slides at the grip limit with up to 22° slip); forward lean carves at 122°/s (304°,
radius about 5 m, ends at 26 km/h); back lean 64°/s with the most sliding (26° slip). Steering
changes the yaw rate within 1 frame of the input. The bank settles at 10–15° in a hard turn.

- **Camera.** Lowest height above the water: 1.58–1.98 m on the rolling swell, and exactly the
  0.9 m limit on waves scaled ×2, where the limit held. Tracking the craft's screen position
  through straights, turns and jumps: median movement under 1 px a frame, frame-to-frame change
  0.03 px median, 0.2 px at the 95th percentile.
- **Landings.** On waves ×1.5, touchdowns at up to −8 m/s sink the hull about 0.45 m and it rides
  on up the next face; no rebound. Waves ×2 (3.5 m swells) stayed stable, with jumps up to 5.4 m.
- **Playtester agent.** Passed all 8 goals (floating, throttle, riding swells, air, steering,
  lean, camera, no engine errors), and the gamepad (right trigger, left stick) rode identically to
  the keyboard. It found air roll, nose dives on short hops, a crate in the start line, a drop
  after respawn, stale telemetry on the respawn frame, the craft under the water on the first
  frame and the craft's shadow showing on the seabed 16 m down; all are fixed and re-measured.
- **Cost.** Game scripts take 1.2 ms a frame (median), mostly the wave solver (about 7 µs per
  water sample); the jet ski's physics is 0.08 ms a tick. GPU 0.59 ms a frame.
- **Regression scenarios** in `test/scenarios/` (floating, throttle, air, steering, water match):
  `gdh scenario run test/scenarios/*.scenario.json` or `gdh test --project .`. All 5 pass. They
  check ranges, not exact values, so small tuning changes don't break them.
- Screenshots: `docs/screenshots/m2_*.png` (turn with bank over the sandbar, airborne, model, rock
  pass, a contact sheet of the 20 s demo ride).

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
- **Wave preset `rolling_swell`** (open-water level): a 64 m, 0.9 m swell, a steeper 26 m,
  0.55 m swell and little chop. At full speed the steep swell's crests curve down faster than
  gravity (about 12 m/s² at 17 m/s), so the craft catches air off them head-on but rides smoothly
  with them or across them. The choppier `open_sea` made it hop off nearly every crest.
- **Physics tick 60 Hz with physics interpolation on.** The camera and the water follow the
  interpolated transforms, so motion is smooth on high-refresh screens.

## Known issues and rough edges

- The terrain is flat-shaded with 4 m cells, so the edges of shallow areas show straight facets
  through the water. A finer grid near shores would smooth this.
- Eight waves repeat visibly when seen from high above; at riding height it isn't noticeable.
- Holding a turn through a long jump yaws the craft in the air, so it can land with 40–50° of slip
  and slide. That's the air steering doing what it's asked; milestone 6 should judge such
  landings.
- Off the throttle the craft slows quickly (42 to 7 km/h in 3 s). Real jet skis do, but it may
  feel abrupt; lower `linear_drag` if so.
- The craft beaches itself on island sand and can't reverse; R resets it. Courses (milestone 3)
  need walls or rocks around islands.
- A replay of a gdh session reaches the same state, but screenshots differ in about 0.5% of
  pixels around the rider (the pose eases in `_process`), so screenshot baselines need a tolerance.
- No spray, wake or sound yet (milestone 8). `JetSki.carving` and `JetSki.airborne` are there for
  them.

## For the next session (milestones 3–5)

- Courses: build them as scenes like `open_water.tscn`. `Terrain.islands` makes islands and
  shoals; `Rock` makes rocks and pillars (set `height_scale` above 1). Buoys should be `Floater`s
  (or kinematic nodes placed with `Ocean.height_at_time(pos, Ocean.end_time)` in
  `_physics_process`). Each course needs a `ShoreMap` covering it; keep static scenery on visual
  layer 1 and anything that moves on layer 2, or it will get shoreline foam.
- Ramps: the craft has a box collider (1.0 × 0.55 × 2.7 m) and no thrust out of the water, so it
  coasts up a ramp on its speed. Start ramps below the waterline.
- Power meter: raise `JetSki.power_multiplier` (thrust). Top speed grows with its square root, so
  +44% thrust is +20% top speed; lowering drag is the other lever.
- Opponents: fill `JetSki.controls` from an AI node instead of `PlayerInput`; the physics is the
  same.
- Crashes: `JetSki.respawn_here()` is the current capsize recovery; replace it with the rider
  falling off and remounting.
