class_name PhysicsLayers
extends Object
## The physics layer bits used across the game. Their names are set in project.godot.

## Layer 1: terrain, rocks, ramps, pillars, the start gate. The chase camera stays in front
## of these.
const SCENERY := 1 << 0
## Layer 2: jet skis.
const CRAFT := 1 << 1
## Layer 3: the invisible walls at the edges of a course.
const WALLS := 1 << 2
## Layer 4: buoys, crates and other floating things.
const FLOATING := 1 << 3
