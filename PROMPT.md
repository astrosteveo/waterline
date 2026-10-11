# Build "Waterline", a jet ski racer inspired by Wave Race 64

You are building a 3D jet ski racing game in Godot 4.7 (the installed version is 4.7.2) in this directory, `/home/astrosteveo/Projects/waterline`. The directory is empty, so you start from nothing. The game is a spiritual successor to Nintendo's Wave Race 64 (1996): it copies the game's mechanics and the way it feels to play, but every name, character, course, model, texture, sound and piece of music is original. Nintendo owns the Wave Race name, characters and assets, so don't use or recreate any of them, and don't use the name "Wave Race" anywhere in the game.

Work autonomously through the milestones below. You have a long time and a large budget, so favor doing each milestone well over getting to the end quickly. The work is split across several sessions (see "Sessions" below), so in each session do only the milestones that session covers.

## Sessions

The milestones are split into three sessions. Each session starts with a fresh context and a different reasoning effort, because the early milestones are the hardest and everything later depends on them. You can't set your own effort level, so the person running you sets it before the session starts.

| Session | Milestones | Recommended effort | Opening message |
|---|---|---|---|
| 1 | 1–2 | max | `Read PROMPT.md and follow it. This is session 1.` |
| 2 | 3–5 | xhigh | `Read PROMPT.md, NOTES.md and git log. This is session 2.` |
| 3 | 6–8 | high | `Read PROMPT.md, NOTES.md and git log. This is session 3.` |

At the start of each session:

1. Work out which session this is from the first message. If the message doesn't say, use the first milestone that `NOTES.md` doesn't list as done, and pick the session that contains it.
2. In your first reply, say which session this is, which milestones you will do, and the recommended effort for it. Remind the person to run `/effort <level>` (or use the `/model` menu) now if they haven't set that level, because the effort can't be changed for the turns you have already run.
3. Do only that session's milestones. When they are done, stop and give the report described at the end of this prompt, even if you have time left.

If a session's milestones are split further (see below), keep the same recommended effort for each part.

## What makes Wave Race 64 worth copying

People remember Wave Race 64 for its water, not its content. Keep these qualities in mind for every decision, because they are what separate this game from a generic racer on a flat blue plane:

- **The water is a physical surface that moves.** Swells roll across the course, and the jet ski rides up, over and down them. A wave can lift the craft into the air, push it sideways or slow it down. The water height under the craft decides its pitch, roll and vertical speed every frame. The same waves the player sees are the waves the physics uses.
- **Steering depends on the rider's lean.** The player leans forward to dig the nose in and turn tighter, and leans back to lift the nose, which helps on landings and over waves. Holding a hard turn while leaning forward produces a sharp carving turn that throws spray. Turning too hard at high speed loses grip and slides.
- **Buoy passes set the power meter.** Each buoy has a color that tells the player which side to pass it on. In the original, the player keeps red buoys on their right and yellow buoys on their left. Each correct pass adds one level to a power meter (up to five levels), and each level raises top speed. A missed buoy resets the meter to zero. Missing five buoys in one race disqualifies the player.
- **Jumps reward clean landings.** Ramps and big swells launch the craft. In the air, the player can do simple stunts (barrel roll, handstand, spin). Landing flat keeps speed, and landing nose-first or sideways costs speed or knocks the rider off.
- **Falling off is a real penalty.** A hard crash or bad landing throws the rider into the water. The rider swims back, climbs on and starts again from low speed, which costs several seconds.

## Technical rules

- Use Godot 4.7 and typed GDScript. Don't use C#, GDExtension or add-ons from the Asset Library unless a milestone can't be done without one, and if so, say why in `NOTES.md`.
- Use the Forward+ renderer.
- Write the water as a shader that displaces a dense mesh with a sum of Gerstner waves (directional waves that peak sharply and trough gently). Put the wave parameters in one shared resource. Write a GDScript function that computes the same wave height and surface normal at any world position on the CPU, from the same parameters. The jet ski physics, buoys and floating objects call that function. The visual surface and the physics surface must match, so check them against each other: put a test object on the water and confirm in a screenshot that it sits on the drawn surface and doesn't float above it or sink through it.
- Model the jet ski as a `RigidBody3D` with buoyancy forces applied at four or more sample points on the hull, plus forces for thrust, steering, lean and drag. Expose every tuning number (thrust, drag, grip, lean strength, buoyancy) as an exported variable or a resource so you can tune without editing code.
- Support both a gamepad (analog stick for steering and lean, triggers or face buttons for throttle) and a keyboard. Define every control as an action in the Input Map. Don't check raw keys in code.
- Build all art from code-generated or hand-written geometry at first: primitive meshes, CSG and simple shaders. Low-poly, flat-shaded, bright colors are fine and fit the 1996 look. Keep every model swappable, so real models can replace the placeholders later without code changes.
- Generate placeholder sound effects procedurally (for example, an `AudioStreamGenerator` for the engine pitch) or leave clearly named silent placeholders. Don't download audio.

## How to check your work

Godot's `--headless` mode draws nothing, so you can't judge a 3D game from it. Use the `gdh` skills, which are installed:

- Load the `gdh:gdh` skill before you change any scene, shader or gameplay code. Use it to render screenshots on the real GPU, read engine errors and play the game with scripted input.
- Load `gdh:godot-gdscript`, `gdh:godot-project` and `gdh:godot-editor` when you write scripts, set up the project and create or edit scenes, so the UIDs and APIs are correct for 4.7.
- Use the `gdh:playtester` agent to check gameplay goals after each milestone, for example "Can the player complete one lap of the test course with keyboard input in under 90 seconds?" or "Does missing a buoy reset the power meter to zero?"

After each milestone, play the game with scripted input, look at screenshots, and fix every engine error and warning before you move on. Judge the feel with numbers as well as pictures: log speed, height above water and grip over a run, and compare them with what you expect. When you claim that something works, base the claim on a run you did, and say what you checked.

## Milestones

Finish each milestone, check it and commit it before you start the next one. Run `git init` at the start, and commit after each milestone with a message that says what now works.

1. **Water.** A project with an ocean that has rolling Gerstner swells, a skybox, a sun and a free camera. The water has depth-based color, foam on wave crests and a specular highlight. The CPU height function matches the shader.
2. **The jet ski on open water.** A drivable jet ski with buoyancy, thrust, steering, forward and back lean, and a chase camera that follows smoothly without clipping into waves. The craft visibly rides over swells and catches air off big ones. Spend real time tuning this milestone, because every later milestone depends on how the craft feels. Write down the final tuning values and why you chose them in `NOTES.md`.
3. **A course.** One test course: a closed loop marked by red and yellow buoys, with a start and finish line, two ramps, some rocks or pillars to steer around, and invisible walls at the edges. Lap counting, a lap timer, and buoy pass detection that knows which side the player passed on.
4. **The race rules.** The power meter (five levels, rises on correct passes, resets on a miss), disqualification after five misses, crashing and remounting, and a heads-up display showing position, lap, time, speed and the power meter.
5. **Opponents.** Three computer-controlled riders that follow a racing line through the buoys, use the same physics as the player, and can make mistakes. Race positions update live. The race ends with a results screen.
6. **Stunts and riders.** Air stunts with clean and failed landings. Four original riders, each with different values for top speed, acceleration, handling and grip. A rider select screen.
7. **Game modes and courses.** A main menu, a championship (a series of races with points), time trial with a saved best time and ghost replay, and a stunt mode scored on stunts and rings. At least four courses with different conditions: calm water, choppy water, night with harbor lights, and a course where the water level changes between laps.
8. **Polish.** Spray particles from the hull and on hard turns, a wake behind each craft, engine pitch that follows speed, splash sounds on landings, a race announcer done as on-screen text, and an options menu for volume and controls.

If a milestone turns out to be much bigger than expected, split it and record the split in `NOTES.md`. Don't skip the checks to save time.

## Keeping track of progress

Keep `NOTES.md` at the project root up to date. It records the current milestone, what works, what is broken or unfinished, tuning decisions and the reasons for them, and anything you would tell another engineer picking up the project tomorrow. If your context is reset, read `NOTES.md` and `git log` first and continue from there, without starting over.

## When to stop and ask

Work without asking for approval on normal design and implementation choices, and record those choices in `NOTES.md`. Stop and ask only when a decision would be hard to undo and the instructions above don't settle it, for example replacing the physics approach after milestone 2, or adding a third-party dependency.

When you finish a session, give a short report: which milestones are done, what you checked and how, what is still rough, and the command to run the game. Unless this was the last session, end the report with the next session's number, its milestones, its recommended effort, and its opening message from the table above. Remind the person to start a new session, set the effort with `/effort <level>` before sending the opening message, and add their own notes on how the game feels to `NOTES.md` first if they have any.
