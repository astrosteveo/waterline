class_name RacerState
extends RefCounted
## One racer's standing in a [Race]: progress along the course, laps, times and buoys.
## [Race] updates it every physics tick.

## The racer's craft.
var craft: JetSki
## Name shown on the HUD and the results.
var display_name: String = ""
## True for the human player.
var is_player: bool = false
## Where the racer is along the course.
var progress := CourseProgress.new()
## Index of the next buoy gate to pass in this lap.
var next_gate: int = 0
## Laps completed.
var laps_done: int = 0
## Race time at which the current lap started, in seconds.
var lap_start_time: float = 0.0
## Time of each completed lap, in seconds.
var lap_times: PackedFloat64Array = PackedFloat64Array()
## True once the racer has crossed the finish line on the last lap.
var finished: bool = false
## Race time at the finish, in seconds.
var finish_time: float = 0.0
## Buoys passed on the correct side, and buoys missed, over the whole race.
var buoys_passed: int = 0
var buoys_missed: int = 0
## Place in the race, 1 for the leader. [Race] refreshes it every tick.
var place: int = 1
## Level of the power meter: one more for each buoy passed on the correct side, back to 0
## on a miss. Each level raises the craft's thrust.
var power: int = 0
## True once the racer has missed too many buoys; it races no more.
var disqualified: bool = false
## True once a stunt run's clock ran out; [member finish_time] holds the limit.
var timed_out: bool = false
## Times the rider was thrown off.
var crashes: int = 0
## Stunts landed and the points they scored.
var stunts_landed: int = 0
var stunt_points: int = 0
## True while the racer has been heading against the course for a while.
var wrong_way: bool = false
## The rider, or null.
var profile: RiderProfile
## The craft the rider rides, or null.
var craft_profile: CraftProfile
## Extra thrust factor on top of the power meter's, set by a computer rider's catch-up.
var thrust_bias: float = 1.0

## Horizontal position at the last tick, for gate crossings.
var last_position: Vector3 = Vector3.ZERO
## Ticks left during which gate crossings are ignored (after the craft was moved).
var teleport_ticks: int = 0
## Distance along the course to give the racer after a placement by [method Race.place_racer],
## or NAN.
var place_distance: float = NAN
## Seconds spent moving against the course.
var reverse_time: float = 0.0


## Distance travelled in the current lap (0 at the start line).
func lap_distance(course_length: float) -> float:
	return progress.distance - laps_done * course_length


## The fastest completed lap, or INF if none.
func best_lap() -> float:
	var best := INF
	for t in lap_times:
		best = minf(best, t)
	return best


## True while the racer still races (not finished or disqualified).
func is_racing() -> bool:
	return not finished and not disqualified and not timed_out
