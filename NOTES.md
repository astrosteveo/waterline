# Waterline: project notes

A jet ski racer in Godot 4.7 (Forward+, typed GDScript, Jolt physics), a spiritual successor to a
1996 jet ski racer. All names, art, sound and courses are original.

## Status

| Milestone | State |
|---|---|
| 1. Water | Done (session 1) |
| 2. Jet ski on open water | Done (session 1) |
| 3. A course | Done (session 2) |
| 4. The race rules | Done (session 2) |
| 5. Opponents | Done (session 2) |
| 6. Stunts and riders | Done (session 3) |
| 7. Game modes and courses | Done (session 3) |
| 8. Polish | Not started |

Run the game: `godot --path /home/astrosteveo/Projects/waterline` (or open the project in the
editor and press F5). The game opens on the main menu (`res://menus/main_menu.tscn`):
championship, quick race, time trial, stunt mode. The race scene also runs on its own
(`--scene res://race/race.tscn`: a quick race on Gull Cove as Marina; `-- --rider koa`,
`--course whitecap_point`, `--mode time_trial` (or `stunt`, `championship`) and `--laps 1` choose
the rest) (`-- --no-opponents` races alone; `-- --watch` lets the
computer ride the player's craft too, and Tab or the right shoulder button moves the camera
from rider to rider, with the HUD and buoy arrow following that rider). `res://levels/open_water.tscn` is the milestone-2 free ride (one jet ski on open water
with rolling swells, islands, rocks and floating crates; `godot --path . --scene
res://levels/open_water.tscn -- --demo` rides a fixed sequence of controls by itself).
`res://levels/water_test.tscn` is the milestone-1 water scene with a free camera.

Checks use `gdh`, a command-line harness that runs the game off-screen on the GPU, steps it frame
by frame with scripted input, takes screenshots and evaluates expressions in the running game.
While gdh holds the game between commands, the scene tree is paused.

## Layout

```
water/          WaveSet + GerstnerWave resources, the CPU wave math, the Ocean autoload,
                OceanSurface (the drawn water), the water shader, Floater (floating props),
                ShoreMap (static scenery heights for shoreline foam)
water/presets/  WaveSet presets: open_sea.tres (choppy), rolling_swell.tres (open-water level)
environment/    sky shader (with stars), day and night environments, Sun, Terrain (seabed +
                islands), Rock, Pier, LampPost, HarborBuilding
jetski/         JetSki (RigidBody3D physics), JetSkiTuning (every tuning number),
                RiderControls, PlayerInput; tuning/default.tres; model/ (placeholder craft
                and rider, swappable)
cameras/        ChaseCamera, FreeCamera, CameraSwitcher
props/          crate.tscn (a Floater)
debug/          WaterProbe, DebugHud (F3 readout), RideRecorder (ride statistics),
                DemoDriver (scripted ride, --demo)
course/         Course (centre line, walls, gates, progress, tide), CourseGate, CourseProgress,
                CourseInfo, Buoy (with an optional lamp), Ramp, StartGate, StuntRing (all
                code-built and swappable), wall_float.gdshader
game/           Game autoload (riders, courses, modes, scene flow), Championship, Records
menus/          MainMenu (main_menu.tscn, the main scene), RiderSelect, CourseSelect, Standings,
                MenuBackdrop (a course behind a menu), MenuStyle (shared look), StatBar
race/           Race (race.tscn), StuntMode, TimeTrial, GhostRecorder, GhostRider, SoloResults,
                RacerState, RaceRules (rules/default_rules.tres),
                RaceHud, PowerMeter (HUD widget), GateMarker, ResultsScreen, RacingLine, AIDriver
riders/         RiderProfile (colours, craft stats, computer skill) and the four riders (.tres)
levels/         the four courses (<id>.tscn, <id>.course.tres = CourseInfo, <id>_map.png = menu map),
                open_water.tscn (free ride), water_test.tscn
physics_layers.gd  the physics layer bits (PhysicsLayers.SCENERY and so on)
tools/courses/  course_tool.py and one JSON spec per course (hidden from Godot)
test/           water_match.tscn (GPU/CPU height comparison), wave_bench.gd,
                scenarios/ (regression scenarios), tools/autodrive.py (test driver)
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
9. **Crashes** (milestone 4, below) replace the old capsize reset.
10. **Stunts and landings** (milestone 6, below).

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

## How a course works

A course is a scene whose root is a `Course` node (`course/course.gd`), with the water, sun,
terrain and scenery as children. `levels/gull_cove.tscn` is the first one. `Race`
(`race/race.tscn`, the main scene) instantiates the course scene named in its `course_scene`,
spawns the racers on the starting grid and runs the race, so one race scene serves every course.

- **Centre line.** `Course.control_points` (world x, z) and `half_widths` (one per point) define
  a closed centripetal Catmull-Rom curve, sampled every 1 m and turned so that sample 0 lies on the
  `StartLine` marker. Offsets along it (0 at the start line, up to `Course.length`) are how the
  game measures progress, places things and draws the racing line. Keep the course node at the
  origin, unrotated: everything is in world space.
- **Walls.** Invisible `StaticBody3D` boxes (physics layer 3, no friction, slight bounce) stand
  `half_width` either side of the centre line. On the inside of a turn tighter than the half
  width, the offset line would cross itself; those loops are cut out where the line crosses
  (`Course._remove_loops`), so the wall follows the inside of the turn. The walls reach from 6 m
  under the water to 18 m above it, above any jump.
- **Progress.** `Course.track()` finds the nearest centre-line sample, searching only ±24 samples
  around the last one, so a racer can't jump to another part of the course that lies close by
  (the legs either side of the hairpin spit are 45 m apart). It refines between samples and keeps
  `distance`, which grows by one course length per lap; race positions sort by it.
  `Course.relocate()` searches the whole line after a teleport and keeps `distance` continuous.
- **Gates.** Each `Buoy` under the course's `Buoys` node (in order of travel) becomes a
  `CourseGate`: a line through the buoy, square to the centre line there, reaching to both walls
  plus 6 m. A racer passes it when its movement between two physics ticks crosses the line going
  forward; the crossing point says which side it passed on. Red buoys are kept on the racer's
  right (pass to their left), yellow buoys on the left. The race checks the next three gates, so
  crossing a later gate first counts the skipped ones as missed; a gate left 30 m behind without
  a crossing (after a teleport) is missed too. The finish line is a gate at offset 0; a lap counts
  when the racer crosses it forward having travelled at least one course length minus 60 m since
  the last lap, so crossing it at the start, backwards, or back and forth never counts.
- **Timing.** The race clock counts physics ticks from "go", and a crossing is placed inside its
  tick by interpolating the movement, so lap times don't depend on the frame rate.
- **Buoys** are `AnimatableBody3D`s (physics layer 4) placed at the water height and tilted 60%
  toward the wave normal every physics tick, so racers bump into them where they are drawn. They
  flash white when the player passes them and dark on a miss. `GateMarker` floats an arrow in
  the buoy's colour over the player's next buoy, pointing to the side to pass on.
- **Ramps** (`course/ramp.gd`) are code-built wedges (physics layer 1, friction 0.05) from 2 m
  under the water's rest level to a 1.8 m lip over 12 m (17.6°), so a craft always meets the
  slope even in a 1.36 m trough. The jet has no water on the ramp, so the craft coasts up it.
- **Physics layers:** 1 scenery (terrain, rocks, ramps, gate pylons; the chase camera's ray
  stops at these), 2 craft, 3 course walls, 4 floating things (buoys, crates). Jet skis collide
  with all four.

## Gull Cove

A 636 m clockwise loop around a central island, laid out on a top-down map with a design script
before building it (start straight north, a sweeping right, a three-buoy slalom east, a 155°
right hairpin around a rock spit, two rock pillars on a narrow leg, a left kink, the ramp leg
south, a right, the second ramp on the bottom leg, a right onto the start straight). Nine buoys
a lap (5 red, 4 yellow); the slalom buoys sit 4 m either side of the centre line, so the
racing line has to weave. Corridor half widths 16–22 m. The hairpin's centre line has a 10.8 m
radius, about the craft's full-lock radius at top speed, so it needs a lift or a carve.

Islands, sandbars and rocks fill the inside of the loop; every wall point is at least 2.5 m
deep even with the islands' random coastline variation at its largest (`coast_noise`,
checked on the map), so the walls, not the seabed,
stop a craft. Since milestone 7 the water is `water/presets/cove_calm.tres` (the calm course):
`cove_swell.tres` (the open-water swell at 75%, troughs to −1.36 m) at half height. The
milestone 3–5 measurements below were made on `cove_swell`.

Measured with the test driver (`test/tools/autodrive.py`, below), which steers with the gamepad
stick through each buoy's passing side: one lap in 44.8 s, 9 of 9 buoys passed. Holding a
lateral line over ramp 1 at 54 km/h: the craft leaves the lip at 17.5° nose up, rises 2.8 m above
the water, flies 1.4 s and lands at 45 km/h. Steering into the start straight's wall at 52 km/h:
the craft stops 0.6 m inside the wall line (half the hull's width) and slides along it at
35 km/h.

## How a race works

`Race` (`race/race.gd`) loads the course, spawns the player's craft (with a `PlayerInput`) in a
grid slot, holds it there during a 3 s countdown (`JetSki.hold()`: a spring to the slot, engine
idle) and then, every physics tick (priority 50, after the riders' input), tracks each racer,
judges gate crossings, counts laps and sorts the racers by distance travelled into places.
`RacerState` holds a racer's progress, laps and lap times, buoys passed and missed and its place.

- **Reset (R)** calls `Race.rescue()` through `JetSki.reset_handler`: the craft goes back on the
  course at its current offset, facing along the course, stopped, at the first spot with nothing
  solid (scenery, buoys, other craft) within 3 m: where it was across the course, else the centre
  line, else either side, else up to 30 m further on. Gate checks pause for two ticks so the jump
  isn't read as a crossing.
- **Wrong way:** moving against the course faster than 1.5 m/s for 1 s shows WRONG WAY.
- **HUD** (`RaceHud`, built in code): place (1st/4), lap, race time and each lap's time (best
  marked), speed, the power meter (`PowerMeter`: slanted segments filling yellow to red, flashing
  as a level is gained, pulsing at max), missed buoys out of five, the countdown, and short calls
  (NICE, MAX POWER, MISSED BUOY with "2 LEFT" near disqualification, LAP 2, FINAL LAP, FINISH,
  DISQUALIFIED) in the upper third, clear of the rider. `GateMarker` floats an arrow over the player's next buoy pointing to its
  passing side, in the buoy's colour.
- **`Race.place_racer(racer, offset, lateral, speed, backwards)`** puts a racer anywhere on the
  course with a given speed, for tests; its distance is set to that offset in its current lap.
- **The test driver** `test/tools/autodrive.py` rides the player's craft through gdh with real
  input (gamepad stick, or `--keyboard` for the digital steer actions): every few frames it reads
  the craft's position and steers toward a point ahead on a line through each buoy's passing side.
  `--laps`, `--shots OFFSETS`, `--start-offset/--start-lateral/--start-speed`, `--lateral` and
  `--wrong-side INDEX` set up tests; `--out` saves a log of position, speed, airborne and lateral.

## Crashes and remounting

`JetSki` detects crashes in `_integrate_forces` while the rider is aboard and in control, and
throws the rider off on the next tick. The reasons (`JetSki.last_crash_reason`):

- **impact:** a contact whose impulse changes the craft's speed by more than
  `crash_impact_speed` (7 m/s) against scenery, or `crash_craft_impact_speed` (9 m/s) against
  another craft. Contacts with walls and floating things (buoys, crates) never count, nor do
  contacts on the hull's underside (contact normal within 45° of the craft's up: riding up a ramp
  or a beach). A head-on pillar hit at 54 km/h measures 15.8 m/s.
- **nose_dive / landed_on_side / landed_sideways:** judged at the first touchdown after at least
  0.3 s in the air (`JetSki.last_landing` keeps the numbers): nose more than
  `crash_landing_pitch` (25°) below the water surface, rolled over 55° or upside down, or moving
  over 75° away from where the nose points above 8 m/s. Clean ramp landings come in 12–23° nose
  up; holding a full forward lean through a ramp jump lands 27–35° nose down and crashes. The
  milestone-2 tuning keeps a carving hop above −16°, so normal riding stays clear.
- **capsized:** upside down in the water for 0.35 s.

The rider then goes through `JetSki.rider_state`: THROWN (flies on at 65% of the craft's speed
from before the impact, plus 3 m/s up and 4 m/s sideways, tumbling; a ray stops the rider at
rocks and walls), SWIMMING (comes up for 0.6 s, then swims at 2 m/s to the nearest boarding
point: either side of the seat or behind the stern), MOUNTING (0.9 s climb; an upturned craft is
turned upright), then ABOARD. Without its rider the craft's engine cuts out, it brakes at 1.1/s
and drifts gently toward the swimmer. After 7 s in the water the rider climbs on wherever the
craft is. Every number is in the Crashes and Remount groups of `JetSkiTuning`.

A crash at 55 km/h on open water costs 4.7 s (71 m less in 12 s at full throttle; control returns
3.45 s after the crash); the playtester measured 4.65 s for a pillar hit on the course. A hit that
drops the rider beside the craft costs less (control back in 1.4–2 s, but the craft is stopped).
Reset (R) is ignored while the rider is off the craft, so it can't cut the penalty short.

The model (`JetSkiModel`) keeps the rider's parts under their own node; `set_rider(mode, pelvis,
blend)` places the rider's pelvis in the world while off the craft, with tumbling, swimming
(crawl strokes) and climbing poses blended from joint positions. The chase camera looks between
the craft and the rider while the rider is off it (`JetSki.camera_focus()`).

## Computer riders

`Race` spawns the player (`player_rider`) and one computer rider per entry in `opponents`, each
on its own grid slot, all on `jetski/jetski.tscn` with the same physics. A computer rider's craft
gets an `AIDriver` (`race/ai_driver.gd`) instead of a `PlayerInput`; it writes the same
`RiderControls` every physics tick. `-- --no-opponents` on the command line races the player
alone.

- **Riders** (`riders/*.tres`, `RiderProfile`): Marina (the player), Koa (skill 0.9), Ines (0.8)
  and Dax (0.7), each with its own hull, trim, suit, vest and helmet colours. Milestone 6 adds their
  top speed, acceleration, handling and grip and the rider select screen.
- **The racing line** (`RacingLine`, built once per race from the course) is a sideways offset
  from the centre line at every sample. Each buoy gives a key point 4 m past it on its marked side;
  real turns without a buoy (radius under 30 m, 35° or more) give a key point on the inside. The
  line holds each key from 12 m before to 6 m after and eases between them, then is fitted round
  the rocks (`Course.obstacles()`: every `Rock`, radius grown by its lumps, plus 2.2 m): ten
  rounds of averaging each sample with its neighbours 6 m either side, then pushing it back out
  of the rocks' way, so the line bends round each rock over several meters instead of jumping
  sideways at its edge. It also keeps a free gap per sample
  (walls, rocks, and at least 2.6 m on each buoy's passing side) that bounds every sideways shift a
  rider makes. Its curvature gives the speed it can be taken at. On Gull Cove it passes every buoy
  2.6–3.9 m on its marked side and runs over both ramps.
- **Steering:** pure pursuit toward the line 6 m + 0.45 s ahead, never past the next buoy (so the
  rider passes it before turning for the next). Any sideways shift from the line is kept inside the
  narrowest free gap all the way from the craft to that point, not only at the point, so a move
  round another craft can't cut across a rock. The needed yaw rate is turned into a steer value
  with the craft's own turn rate; the rider carves (leans forward) when full lock isn't enough.
- **Speed:** looking 2 s ahead, the rider lifts off the throttle (and leans forward to drag more)
  if the line's curvature needs a lower speed than it could brake to, at 3.5 m/s², counting on the
  craft's turn rate and on 15 m/s² of sideways grip. Without the grip limit the riders entered the
  hairpin too fast, ran wide and hit the pillar after it.
- **In the air** the rider levels the nose to 4° up for a flat landing.
- **Skill** (0 to 1): the throttle cap (80% at 0, full at 1), the grip it counts on (80–100%), how
  late it reacts (0.16 s at 0, 0.04 s at 1), a slow wander off the line (up to 3 m at 0), and how
  boldly it takes the turns each lap (cautious on the whole at low skill, but sometimes overcooking
  a lap and running wide).
- **Mistakes:** once per lap, with a chance of 80% × (1 − skill), the rider picks one buoy to take
  on the wrong side (aiming for the wrong side of that buoy ignores the 2.6 m it otherwise
  keeps from buoys, but still keeps clear of rocks). Crashes come from the
  physics, as for the player: running wide into a rock, bumping in a pack.
  The mistakes are seeded from the rider's seed plus `randi()` at the start of each race, so
  every race differs but a gdh replay with the same `--seed` repeats.
- **Traffic:** a craft within 14 m ahead and 2.5 m to the side moves the rider's target 3.5 m to
  the other side to pass it, shrinking to nothing in turns tighter than about 25 m. A craft
  alongside (within 3 m back to 4 m ahead) moves it 2.4 m away. Alongside a craft that is further
  round the course, with a buoy within 30 m or a tight turn, the rider eases to 60% throttle and
  drops in behind it; closing more than 2 m/s faster on a craft right in front, to 30%. Without
  these, four riders reached the slalom side by side and missed five buoys in three seconds, and
  the pack pushed riders wide into the rock after the hairpin.
- **Stuck:** under 1.5 m/s or going the wrong way for 1.8 s, with the rider aboard, it resets
  itself (`Race.rescue`).
- **Catch-up:** a computer rider gets up to 5% more thrust when 120 m or more behind the player
  and 5% less when that far ahead (`RaceRules.catch_up`), so races stay close.
- After finishing (or being disqualified) a computer rider rides on at 70% throttle. When the
  player finishes, the computer takes the player's craft round at the same easy pace.
  `Race.autopilot(racer, skill)` puts the computer in charge of any racer, for tests and demos.

## Results

`ResultsScreen` opens 3.3 s after the player finishes or is disqualified (after the FINISH call
has faded): each rider by place with total time and best lap, the player's row in yellow; riders
still out show RACING and fill in as they finish; DQ for disqualified riders. RACE AGAIN reloads
the race scene; QUIT quits (milestone 7 adds a main menu). The focused button takes ui_accept, so
a gamepad works.

## Race rules (race/race_rules.gd, values in race/rules/default_rules.tres)

| Rule | Value | Why |
|---|---|---|
| Power levels | 5 | As in the original. Each buoy passed on its marked side adds one; a miss (wrong side or skipped) empties the meter. Crashes leave it as it is (the brief doesn't say). |
| Thrust per level | 1.00, 1.07, 1.14, 1.22, 1.30, 1.38 | Top speed grows with about the square root of the thrust: 59 km/h at level 0, 69 km/h at level 5 (+17%) on open water; 57 and 68 km/h on Gull Cove's start straight. Enough to matter, not so much that the hairpin becomes impossible at full power. |
| Disqualification | 5 misses in a race | As in the original. The race ends for the player (results come up), no more buoys are judged, the clock stops. |
| Catch-up | ±5% thrust at 120 m behind or ahead of the player | Computer riders only. Keeps the pack within reach without the player noticing a push. |

A buoy is a moored `RigidBody3D` (80 kg): springs pull it to its anchor, to the water height and
upright along the waves. A head-on hit at 50 km/h costs the craft 30% of its speed and pushes the
buoy 2 m, after which it swings back; as a kinematic body it had stopped the craft dead. Gates use
the anchor position.

## Course design tool

`tools/courses/course_tool.py SPEC.json --map out.png --scene` lays out a course from a JSON spec
(`tools/courses/gull_cove.json`): control points with half widths, buoys, ramps and rocks by
course offset and lateral offset, and terrain islands. It uses the same spline as the game, so
offsets match, draws a top-down map (walls with the inside loops cut out, buoys with a tick toward
their passing side, ramps, rocks, islands and shallows) and circles every wall point that lies over
water shallower than 2.5 m, and writes the course scene. Writing the scene overwrites it, so edit
the spec, not the scene, for layout changes. Session 3 needs three more courses; start from a copy
of the Gull Cove spec.

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

### Milestone 3 (a course)

Measured with gdh on `race/race.tscn` (Gull Cove, seed 1):

- **Laps and buoys.** The test driver (stick input) rode a lap in 44.8 s passing 9 of 9 buoys;
  with keyboard steering, a full race in 2:14.02 (laps 45.83, 43.72, 44.44 s), 27 of 27 buoys,
  ending in FINISH. Passing buoy 3 on the wrong side counted a miss (8 passed, 1 missed).
- **Ramps.** Riding over ramp 1 at 54 km/h: off the lip at 17.5° nose up, 2.8 m above the water,
  1.4 s in the air, landing at 45 km/h. `airborne` turns on only past the lip (418.7 m, lip at
  418 m), because a hull touching anything solid isn't in the air.
- **Walls.** Steering into the start straight's wall at 52 km/h, the craft stops 0.6 m inside
  the wall line and slides along it at 35 km/h.
- **Reset.** Stopped against the pillar at 318 m, reset puts the craft on the centre line facing
  along the course, and it rides away at 42 km/h within 2 s; reset on a ramp puts it beside the ramp.
- **Playtester agent:** passed all 7 goals (keyboard lap 44.33 s and a full race in 2:08.00, buoy
  judging both ways for red and yellow, both ramps, walls in three places including the hairpin,
  rocks and pillars solid, reset, no engine errors or warnings). It found: reset pointing the craft
  back at a pillar or into a ramp, `airborne` turning on while still on the ramp face, ramps off
  the buoy line, walls with nothing marking them, the start banner behind the HUD, buoy calls on
  top of the rider, a wrong camera view on the first frame and a test helper moving distance
  backwards. All are fixed and re-checked above; the underwater look it noted is listed under
  known issues.
- **Frame time** on the race: GPU median 0.60 ms, p99 0.82 ms; CPU (render) 0.09 ms.
- **Regression scenarios:** `course_buoys`, `course_laps`, `course_ramps`, `course_walls`,
  `course_reset` (49 checks) plus the five from milestone 2: all 10 pass. The playtester's own
  scenarios replayed exact inputs and checked exact values (a lap time to 0.05 s, rocks by node
  name), so any physics change would break them; they are kept in `captures/` as evidence only.
- Screenshots: `docs/screenshots/m3_*.png` (start grid, slalom with the buoy arrow, hairpin,
  pillars, ramp jump, wall floats, the course map).

### Milestone 4 (the race rules)

- **Power meter.** A clean lap with the test driver filled it to 5 by the fifth buoy and lapped in
  43.45 s (44.8 s before power); a miss emptied it. Top speeds as in the table above.
- **Crashes.** Pillar hit at 54 km/h: `impact`, rider in the water and back on (see the numbers
  above). Nose-first landing off ramp 1 with a held forward lean: `nose_dive` at 34° nose down.
  Upside down: `capsized` after 0.35 s, and the craft turned upright as the rider climbs on.
  No false crashes in 20 s heading into open water's steep swell at power 0 and 5 (8–9 jumps each),
  20 s of carving hops, clean ramp jumps, a lap, wall scrapes or buoy hits. Holding a forward lean
  straight into open water's steepest swell for 20 s crashed twice (nose first), which is the rule
  working: lean back or stay neutral in the air.
- **Playtester agent:** passed all 7 goals (power meter, disqualification by riding past five buoys
  on the wrong side, crash and remount, no false crashes over about 2.8 laps, jumps, wall scrapes
  and buoy hits, reset while swimming, HUD values and layout, no engine errors). It found: reset
  skipping the crash penalty, a nose-first crash needing full power, MAX POWER hidden by NICE, the
  clock running after disqualification, DISQUALIFIED briefly covering the HUD, NICE in a red that
  looked like a miss, and the swimmer at the edge of the screen. All are fixed.
- **Regression scenarios** added: `race_power`, `race_disqualify`, `race_crash`; `course_reset`
  now also checks that reset waits for the rider. All 13 pass.

### Milestone 5 (opponents)

- **Computer riders alone** (player idle): three 3-lap races, all within 2.1 s of each other at
  2:02–2:05, 0–1 misses each, no crashes after the fixes below.
- **Against the player's craft on the computer driver** (skill 0.95), five races on seeds 11–55:
  the player 1st in four (1:59.9–2:03.4), Koa winning one; the field within 2:00–2:10; no crashes;
  1–5 misses in all per race (planned mistakes and the odd one in traffic); riders within 1.4 m of
  each other (touching) in 0.7–0.9% of samples.
- **Places** update every tick; the playtester matched the HUD place with the distance order in
  1,503 samples over 3 races and about 20 lead changes.
- **Frame time** with four craft: GPU median 0.62 ms; game scripts and physics 1.6 ms a frame
  (median), most of it the wave solver (`WaveSet.find_rest_position`).
- **Playtester agent:** goals 1, 3, 4, 5 and 7 passed (computer riders complete clean races on
  smooth lines, places live, a keyboard-driven player won by 1.3 s and 1.4 s, so the field is
  within reach, results screen with RACING rows filling in, focus and ui_accept, no errors). It
  found: Koa's overtaking move sending it into the rock after the hairpin in 2 of 5 races and then
  sitting against it for 3 s; the wrong-side mistake never happening with fixed seeds; riders
  riding hull to hull for long stretches; Koa pushing a stopped player 35 m; places not shown before
  the start. All are fixed and re-measured above.
- **Regression scenarios** added: `race_opponents` (riders, line, places) and `race_results`
  (results rows, RACE AGAIN). Single-racer scenarios start with `-- --no-opponents`; those that
  teleport past buoys turn disqualification off. All 15 pass.
- Screenshots: `docs/screenshots/m5_*.png` (the grid with opponents, racing 2nd in a pack, the
  results).

### Milestone 6 (stunts and riders)

- **Stunts:** `race_stunts` (27 checks): a barrel roll and a handstand started early land
  clean, score 100 and 120 and add a power level; stunt on the water does nothing; a backflip
  started 0.5 s into the jump throws the rider off (`stunt_failed`); 0.5 s of forward lean
  lands about 20° nose down, untidy, losing 5–36% of the speed.
- **Riders:** `riders_select` (15 checks): the stats shown per rider, the list wrapping,
  confirming races as Ines against the other three with Ines's handling and weight, and the
  computer riders on their own stats. The flat-water and Gull Cove numbers are in "Riders".
- **Playtester agent:** goals 2–6 passed (every stunt binding including gamepad B and X,
  stunt directions, scores and the combo, late stunts failing, landing quality matching the
  speed lost to the percent, rider stats in the expected order, computer riders landing 6
  barrel rolls in 18 ramp jumps, results buttons, no engine errors). Goal 1 failed on one
  point: gamepad A didn't confirm, because `ui_accept` had only its keyboard defaults. Also
  found: rider names touching the button edge, the stats panel jumping 13 px between one- and
  two-line descriptions, early backflips and handstands landing untidy on short jumps, and no
  call for a failed stunt. All fixed: `ui_accept`/`ui_cancel` now include gamepad A/B, buttons
  have side padding, the description keeps two lines' height, the two stunts take 0.8 s, and
  the HUD calls WIPEOUT on any crash. All 17 scenarios pass.

## Stunts and landings

The `stunt` action pressed in the air (after `stunt_min_air_time`, 0.08 s) starts a stunt; the
direction held as it goes down picks it (`JetSki.stunt_for`, from the raw axes so a key pressed
with it counts): steer left or right is a **barrel roll** that way, lean back a **backflip**,
lean forward a **handstand**, nothing a **spin** (a flat 360°). The rider can't steer or lean
while a stunt runs; a second stunt can follow the first in the same jump.

- **The model turns, not the body.** A roll, flip or spin turns the `Model` node about
  `JetSki.STUNT_PIVOT` (between hull and rider), easing in and out
  (`p - sin(2πp)/2π`); the rigid body keeps its air attitude. Driving the body through 360° in
  under a second fought the air control and the camera, and a body rolled 180° at touchdown
  would be judged by the physics, not the stunt. The handstand is the rider's own pose
  (`JetSkiModel.set_stunt`): the body swings forward over the bars, upside down, legs up. A
  replacement model only needs `set_stunt(stunt, progress)` for the handstand; the turn works
  on any model.
- **Timing.** Roll 0.75 s, backflip 0.8 s, spin 0.7 s, handstand 0.8 s. A ramp jump on Gull
  Cove gives 0.85–1.25 s of air (waves and power), so any one stunt fits if started within
  about 0.1–0.2 s of the lip; two need more air (Ebb Reef's ramps at low tide, big swells). At
  0.9 s a backflip or handstand started at the first moment still landed untidy on a third of
  the shorter jumps; at 0.8 s, ten such jumps (1.00–1.27 s of air) all landed clean.
- **Touchdown mid-stunt.** A roll, flip or spin within `stunt_landing_tolerance` (45°) of
  finished, or a handstand past 85%, counts: the model finishes the turn in 0.12 s and the
  landing is at least untidy. Otherwise the rider is thrown off (`stunt_failed`).
- **Landing quality** (`JetSki._judge_landing`, after `crash_landing_air_time` 0.3 s of air or
  any stunt): **failed** is the milestone-4 crash rules plus `stunt_failed`. **Clean**: nose
  between 8° down and 28° up against the water, roll under 15°, slip under 20°; no speed lost.
  Clean ramp landings come in 12–23° nose up, so 28° leaves room. **Untidy**: anything between;
  "badness" is how far the worst measure is from its clean limit toward its crash limit (nose
  up: 25° past the limit), and the craft loses 8% (just past clean) to 35% (nearly a crash) of
  its speed through the water at once. Holding lean forward for 0.33 s of a ramp jump lands
  1° down (clean), 0.5 s lands 21° down (untidy, 28% lost), 0.67 s lands 26° down (crash).
- **Scoring:** roll 100, backflip 150, spin 80, handstand 120; two in one jump ×1.5, three ×2;
  an untidy landing half. `JetSki.landed(quality, stunts, points)` reports every judged
  landing; `Race` adds the points to `RacerState.stunt_points` and, in a race, adds
  `RaceRules.stunt_power` (1) power levels for a landed stunt, so stunts are worth the risk in a
  race (the original gives nothing for them outside stunt mode). The HUD calls "BARREL ROLL
  +100", "ROUGH" on an untidy one and "ROUGH LANDING" for an untidy landing without a stunt.
- **Computer riders** judge each jump 0.1 s after take-off from the climb rate and height
  (air left = (v + √(v² + 2gh)) / g) and, half the time, barrel-roll if the air left beats the
  roll by a margin that shrinks with skill and has some random misjudgement below skill 1, so a
  weaker rider can land mid-roll. Over two watched races each rider landed 0–4.

## Riders

`RiderProfile` (`riders/*.tres`) holds a rider's name, a one-line description, colours
(including the hull's bottom, so riders tell apart from behind), four craft factors and a weight,
and the computer skill. `RiderProfile.tuned(base)` returns a copy of the craft's `JetSkiTuning`:

- **Top speed s, acceleration a:** thrust × a, linear drag × a/s, quadratic drag × a/s². Top
  speed solves thrust = linear·v + quadratic·v², so a keeps it and s scales it; a scales the push
  from a standstill.
- **Handling h:** turn rates, yaw response and yaw acceleration × h. **Grip g:** `grip_g` and
  `grip_rate` × g; a computer rider counts on `cornering × g` in the turns.
- **Weight:** every force that scales with the body (thrust, drag, buoyancy, damping, torques)
  scales with the mass too, so the weight changes collisions (who pushes whom), not the ride.

| Rider | Top speed | Accel. | Handling | Grip | Mass | Character |
|---|---|---|---|---|---|---|
| Marina | 1.00 | 1.00 | 1.00 | 1.00 | 300 kg | the base craft |
| Koa | 1.06 | 0.86 | 0.92 | 1.00 | 330 kg | fast once going, slow to get there and to turn |
| Ines | 0.96 | 1.00 | 1.12 | 1.10 | 280 kg | tightest turns, holds the line, lowest top speed |
| Dax | 1.00 | 1.14 | 1.04 | 0.88 | 290 kg | quickest off the mark, slides in turns |

Measured on flat water (`test/tools/rider_bench.py --flat`, repeatable to 0.01 s):

| Rider | 0–40 km/h | 0–50 km/h | Top speed | Full-lock U-turn from top speed | Most slip | Speed after |
|---|---|---|---|---|---|---|
| Marina | 1.95 s | 2.98 s | 58.2 km/h | 2.63 s | 8.5° | 49.6 km/h |
| Koa | 2.18 s | 3.18 s | 61.5 km/h | 2.87 s | 5.9° | 54.4 km/h |
| Ines | 1.97 s | 3.13 s | 55.9 km/h | 2.38 s | 6.4° | 49.3 km/h |
| Dax | 1.72 s | 2.62 s | 58.3 km/h | 2.40 s | 29.4° | 38.5 km/h |

On waves the same runs vary by about 0.2 s between repeats (the craft meets different swells),
so compare riders on flat water. On Gull Cove, each rider alone on the computer driver at skill
1.0 over 3 laps: Koa 1:58.71, Marina 1:59.80, Dax 1:59.99, Ines 2:00.55, no misses or crashes.
The spread is 1.5%, so the choice is about feel, not a best rider.

**Rider select** (`menus/rider_select.tscn`, the main scene): the riders down the left (focus
moves with ui_up/ui_down, the list wraps, the mouse works too), the focused rider's craft
floating on Gull Cove in the middle with the camera circling it, and a panel on the right with
the name, the line and four stat bars (`StatBar`; 3 is the base craft, a point per 7%, half
steps). ui_accept sets `Game.player_rider` and opens the race. `Race` then races that rider
against `Game.opponents_for()` the rest; the command line `-- --rider NAME` does the same.
The results screen has RACE AGAIN, RIDERS (back to rider select) and QUIT.

## Game flow and modes

`Game` (`game/game.gd`, an autoload) holds the riders, the courses (`CourseInfo` resources:
id, name, conditions line, scene), the chosen rider, course and mode, the championship under
way and the records, and changes scenes: main menu → rider select → course select (or the
championship's next course) → race → results → back. Each screen calls Game
(`start_mode`, `rider_chosen`, `course_chosen`, `goto_standings`, `next_championship_race`,
`goto_main_menu`...), so screens don't know about each other. ui_cancel goes back a screen.
`Race` reads `Game.mode` and sets itself up; `-- --mode NAME` sets the mode from the command
line for tests.

- **Quick race:** one race against the other three riders. Results: RACE AGAIN, COURSES,
  MAIN MENU.
- **Championship** (`Championship`): the four courses in menu order, points 10/6/3/1 by place
  (none when disqualified), standings after each race (`menus/standings.tscn`: this race's
  points and the totals, then the next course), the champion after the last; equal points go
  to the better place in the last race. The results screen adds a POINTS column and CONTINUE
  records the order as it stands (riders still out are placed where they are). The original
  needed a points total to go on; this one always runs all four races, so a bad race isn't
  the end.
- **Time trial** (`TimeTrial`): alone from the middle of the grid, 3 laps. The HUD shows the
  record and the best lap, and each lap call adds the difference from the record lap (green
  ahead, red behind). At the finish `Records` keeps the race time and best lap if they are
  better (with the rider), and a race record saves the run as the course's ghost.
- **Ghosts:** `GhostRecorder` stores, every physics tick, the model's transform (so stunts
  show), steer, lean, airborne and the stunt with its progress: 12 floats a tick, about 350 KB
  for a 2-minute run, zstd-compressed in `user://ghosts/<course>.ghost`. `GhostRider` plays it
  back on a see-through `JetSkiModel` (`ghost = true`: alpha 0.38, a faint blue glow, no
  shadows) in step with the race clock, interpolated between ticks. Every race now starts the
  wave clock at 0 (`Ocean.reset_time` in `Race._ready`), so the ghost rides the water it was
  recorded on; before that the ghost floated a metre off the surface on a retry.
- **Stunt mode** (`StuntMode`): one lap against a clock of 0.1 s per meter of the lap, rounded
  up to 5 s (Gull Cove 65 s). Rings (`StuntRing`) float along the racing line every 50 m,
  clear of buoys and ramps by 18 m, and an air ring hangs 9 m past each ramp's lip, 1.2 m
  above it, where a full-speed jump flies. A ring scores 100 (an air ring 200) times a chain
  multiplier (+0.25 per ring in a row, up to ×3, reset by a ring missed) and adds a power
  level; landed stunts score as in a race; finishing adds 10 per second left. Buoys still
  count for the power meter but can't disqualify. The best score per course is saved.
- **Records** (`game/records.gd`): `user://records.cfg`, a ConfigFile with the best race and
  lap per course (and who set them) and the best stunt score. gdh runs keep `user://` in their
  own folder, so tests never touch a player's records.
- **Results for the solo modes** are `SoloResults` (rows of label and value; RETRY, COURSES,
  MAIN MENU) instead of the race results.

## The four courses

| Course | Conditions | Lap | How |
|---|---|---|---|
| Gull Cove | calm | 636 m | `cove_calm.tres`: the cove swell at half height (troughs to about −0.7 m). The first course, for learning the buoys. |
| Whitecap Point | choppy open sea | 908 m | `whitecap_chop.tres`: `open_sea` with a lower main swell (0.62 m) and stronger chop (0.19, 0.13, 0.07 m). The craft hops off the chop on every straight. Long start straight with a ramp, a sweeping top, a chicane past a rock, a long bottom sweep. |
| Lantern Harbor | night, harbour lights | 1021 m | `night_environment.tres` (dark sky with stars, a moon disc, colour ambient light, glow), a dim blue moon low in the sky so its glitter shows the swells, `harbor_swell.tres` (cove swell at 55%). Piers with lamps and lit buildings along the north shore, a breakwater with red and green entrance lights, lit buoys (`Buoy.lamp_energy`) and darker water (`OceanSurface.shader_overrides`). The course leaves through the breakwater gap and comes back round its east end. |
| Ebb Reef | the tide goes out each lap | 852 m | `Course.lap_levels` 0, −0.9, −1.8 m: when the leader starts lap 2 and 3 the rest level falls at 0.15 m/s and the HUD calls THE TIDE IS GOING OUT. Reef flats break the surface, four rocks hidden 0.6 m under the water on lap 1 stand up to 1.2 m above it on lap 3 (the computer riders' line avoids them from the start), and the ramps' lips rise from 1.8 m to 3.6 m above the water, so the jumps grow. The ramps start 4.2 m under the high-tide level (19 m long, same 17.6° slope): with the default 2 m, a trough at low tide exposed the ramp's front edge and riders hit it head-on. Walls stay 4.3 m deep at high tide (2.5 m at low tide). |

Computer races (four riders, 3 laps): Whitecap Point 58–60 s laps, 0–1 misses each, no crashes;
Lantern Harbor about 60 s laps, Koa about 10 s ahead of the rest (top speed and skill on long
straights), 0–1 misses, no crashes; Ebb Reef 50–59 s laps, 0–2 misses, no crashes.

**Water level and other systems.** `Ocean.level` is set by each course at load (and reset to 0
by every `OceanSurface`, since the autoload outlives scenes). Buoys, wall floats, rings, the
chase camera and the physics all read it through `Ocean`; the ramps and rocks are fixed, which
is what makes them taller at low tide.

**Course tool additions** (`tools/courses/course_tool.py`): `props` (pier, lamp and building
entries with their properties), `lit_buoys`, `water` (shader overrides), `lap_levels`,
`ramp_bottom` (deeper ramps at the same slope), `wall_depth` (the map's depth check), and
`--thumb`, which draws the menu map (`levels/<id>_map.png`). Edit the JSON and rerun
`--scene --thumb`, never the scene.

## Controls (Input Map actions)

| Action | Keyboard | Gamepad |
|---|---|---|
| throttle | Space, J | A, right trigger |
| steer_left / steer_right | A / D, Left / Right | left stick X, D-pad |
| lean_forward / lean_back | W / S, Up / Down | left stick Y (up = forward), D-pad |
| stunt | K, Left Shift (in the air; the held direction picks the stunt) | B, X |
| reset_craft | R (in a race: back on the course, clear of obstacles; not while swimming) | Back |
| ui_accept / ui_cancel (menus) | Enter, Space / Escape | A / B |
| toggle_camera | C | Y |
| watch_next | Tab (watch mode only: follow the next rider) | right shoulder |
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

- Anything just under the water (the underwater part of rocks, ramp posts) is drawn bright
  turquoise, because the water's depth colour treats it as shallow water. It reads like a cyan
  shadow under rocks. A milestone-8 polish item: darken or desaturate the shallow colour where the
  depth comes from a moving or vertical object rather than the seabed.
- The test driver (`test/tools/autodrive.py`) follows a line through the buoys only; it knows
  nothing of rocks. The computer riders' `RacingLine` does.
- A computer rider close behind can come between the chase camera and the player's craft.
- Computer riders don't aim for ramps; they ride over them because the ramps sit on the line.

- The terrain is flat-shaded with 4 m cells, so the edges of shallow areas show straight facets
  through the water. A finer grid near shores would smooth this.
- Eight waves repeat visibly when seen from high above; at riding height it isn't noticeable.
- Holding a turn through a long jump yaws the craft in the air, so it can land with 40–50° of slip
  and slide. Since milestone 6 such a landing is untidy and costs speed.
- Off the throttle the craft slows quickly (42 to 7 km/h in 3 s). Real jet skis do, but it may
  feel abrupt; lower `linear_drag` if so.
- The craft beaches itself on island sand and can't reverse; R resets it. Course walls keep
  racers 2.5 m deep or more.
- A replay of a gdh session reaches the same state, but screenshots differ in about 0.5% of
  pixels around the rider (the pose eases in `_process`), so screenshot baselines need a tolerance.
- No spray, wake or sound yet (milestone 8). `JetSki.carving` and `JetSki.airborne` are there for
  them.

## For the next session (milestone 8)

- **Spray and wakes:** `JetSki.carving`, `airborne`, `last_landing` (with `quality`),
  `thrust`, `speed` and `rider_state` are there to drive them; `JetSki.landed` fires at each
  judged touchdown.
- **Sound:** no audio yet. Engine pitch from `JetSki.thrust` and `speed`; splash on `landed`.
- **Announcer:** `RaceHud.show_message` / `show_sub_message`, and the race signals
  (`started`, `lap_completed`, `racer_finished`, `racer_crashed`, `racer_landed`,
  `tide_turned`, places from `RacerState.place`).
- **Options:** add to the main menu; `Records.clear()` exists for a "clear records" option.
