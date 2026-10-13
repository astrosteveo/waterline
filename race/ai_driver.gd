class_name AIDriver
extends Node
## A computer rider. It writes the parent [JetSki]'s controls every physics tick, as
## [PlayerInput] does for the player, so it rides with the same physics.
##
## It steers by pure pursuit toward a point on the race's [RacingLine] a speed-dependent
## distance ahead, turning the needed yaw rate into a steer value, and carves (leans
## forward) when full lock isn't enough. It lifts off the throttle when the line ahead
## curves more tightly than it can turn at its speed. In the air it levels the nose for the
## landing. Lower [member skill] makes it wander off the line, react later, misjudge its
## speed and now and then take a buoy on the wrong side.

## 0 to 1: how well the rider follows the line, judges speed and passes buoys.
@export_range(0.0, 1.0, 0.01) var skill: float = 0.8
## Seconds of lookahead at full speed, on top of a fixed distance.
@export_range(0.1, 2.0, 0.01, "suffix:s") var lookahead_time: float = 0.45
@export_range(1.0, 20.0, 0.1, "suffix:m") var lookahead_min: float = 6.0
## Deceleration the rider counts on when planning to slow for a turn, m/s².
@export_range(0.5, 15.0, 0.1) var braking: float = 3.5
## Share of the craft's turn rate the rider plans to use in turns.
@export_range(0.3, 1.5, 0.01) var turn_margin: float = 0.95
## Sideways acceleration the rider counts on in turns, m/s². Past what the hull's grip gives,
## the craft slides wide.
@export_range(1.0, 50.0, 0.1) var cornering: float = 15.0
## Chance per lap, at skill 0, of taking one buoy on the wrong side. Scales with 1 - skill.
@export_range(0.0, 1.0, 0.01) var blunder_chance: float = 0.8
## When false the rider sits still with the throttle off.
@export var enabled: bool = true
## Ride round at an easy pace, for the player's craft after the finish.
@export var cruise: bool = false
## Sideways room kept from another craft just ahead, in meters...
@export_range(0.0, 10.0, 0.1, "suffix:m") var overtake_offset: float = 3.5
## ...and from one alongside.
@export_range(0.0, 10.0, 0.1, "suffix:m") var side_gap: float = 2.4
## Chance of a barrel roll on a jump long enough for one (judged from the climb and the
## height). A less skilled rider judges the air time less carefully and can land mid-roll.
@export_range(0.0, 1.0, 0.01) var stunt_chance: float = 0.5
## Seed for this rider's mistakes, so a race replays the same way.
@export var mistake_seed: int = 1

var race: Race
var racer: RacerState

var _craft: JetSki
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()
var _time := 0.0
var _steer := 0.0
var _blunder_gate := -1
var _blunder_lap := -1
var _stuck_time := 0.0
var _confidence := 1.0
var _avoid := 0.0
var _blocked_ahead := false
var _yielding := false
var _jump_judged := false


func _ready() -> void:
	_craft = get_parent() as JetSki
	if _craft == null:
		push_error("AIDriver must be a child of a JetSki.")
	if racer != null and racer.craft_profile != null:
		# Count on this craft's own grip in the turns.
		cornering *= racer.craft_profile.grip
	_rng.seed = mistake_seed
	_noise.seed = mistake_seed
	_noise.frequency = 0.08
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH


func _physics_process(delta: float) -> void:
	if _craft == null:
		return
	var controls := _craft.controls
	if not enabled or race == null or racer == null or race.racing_line == null:
		controls.clear()
		return
	_time += delta
	var line := race.racing_line
	var course := race.course
	var offset := racer.progress.offset
	var speed := maxf(_craft.forward_speed, 0.0)
	var position := _craft.global_position
	var nose := -_craft.global_basis.z
	nose.y = 0.0
	nose = nose.normalized() if nose.length_squared() > 1e-6 else Vector3.FORWARD

	_plan_mistakes(course)
	_update_avoidance(position, nose, speed, offset, delta)

	# --- Steering: pure pursuit toward the line ahead, never looking past the next buoy, so
	# the rider passes it on its side before turning for the one after. ---
	var look := lookahead_min + lookahead_time * speed
	if racer.next_gate < course.gates.size():
		var to_gate := wrapf(course.gates[racer.next_gate].offset - offset, -course.length * 0.5, course.length * 0.5)
		if to_gate > 0.0 and to_gate + 2.5 < look:
			look = maxf(to_gate + 2.5, 4.0)
	var target_offset := offset + look
	# Keep the shift inside the free gap all the way to the target, not only at it, so a
	# move round another craft can't cut across a rock on the way.
	var blundering := _blundering(target_offset)
	var shift := _shift(target_offset)
	if not blundering:
		var gap := line.gap_between(offset, target_offset)
		var line_lateral := line.lateral_at(target_offset)
		shift = clampf(line_lateral + shift, gap.x, gap.y) - line_lateral
	var target := line.point_at(target_offset, shift, blundering)
	var to_target := target - position
	to_target.y = 0.0
	var distance := maxf(to_target.length(), 0.5)
	var direction := to_target / distance
	# Positive when the target is to the left (counter-clockwise seen from above).
	var alpha := atan2(nose.cross(direction).y, nose.dot(direction))
	var wanted_yaw_rate := 2.0 * maxf(speed, 4.0) * sin(alpha) / distance
	if absf(alpha) > PI * 0.5:
		wanted_yaw_rate = signf(alpha) * 10.0
	var turn_rate := _turn_rate(speed)
	var steer := clampf(-wanted_yaw_rate / maxf(turn_rate, 0.1), -1.0, 1.0)
	# React a little late, more so at low skill.
	var reaction := lerpf(0.16, 0.04, skill)
	_steer = lerpf(_steer, steer, clampf(delta / reaction, 0.0, 1.0))

	# --- Speed: lift off for what is ahead. ---
	var throttle := 1.0
	var lean := 0.0
	var carve_rate := turn_rate * _craft.tuning.lean_forward_turn * _craft.tuning.carve_turn
	var plan_rate := carve_rate * turn_margin * _confidence
	var plan_accel := cornering * lerpf(0.8, 1.0, skill) * _confidence * _confidence
	var horizon := maxf(speed * 2.0, 14.0)
	var s := 2.0
	while s <= horizon:
		var limit := line.speed_limit(offset + s, plan_rate, plan_accel)
		var allowed := sqrt(limit * limit + 2.0 * braking * s)
		if speed > allowed:
			throttle = 0.0
			if speed > allowed + 2.0:
				lean = 1.0
			break
		s += 2.0
	# Carve when the turn needs more than full lock.
	if absf(wanted_yaw_rate) > turn_rate * 0.95 and speed > _craft.tuning.carve_min_speed:
		lean = 1.0

	# --- In the air: level the nose for a flat landing, a little nose up. ---
	if _craft.airborne:
		var pitch := rad_to_deg(asin(clampf(-_craft.global_basis.z.y, -1.0, 1.0)))
		lean = clampf((pitch - 4.0) / 15.0, -1.0, 1.0)
		throttle = 1.0
		_consider_stunt()
	else:
		_jump_judged = false

	# Closing fast on a craft right in front: ease off rather than ram it. Alongside a
	# craft that is ahead, coming to a buoy or a turn: drop in behind it.
	if _blocked_ahead:
		throttle = minf(throttle, 0.3)
	elif _yielding:
		throttle = minf(throttle, 0.6)
	# Less skilled riders ride a little slower on the straights.
	throttle *= 0.7 if cruise else lerpf(0.8, 1.0, skill)
	controls.throttle = throttle
	controls.steer = _steer
	controls.lean = lean
	_check_stuck(speed, delta)


## Once per jump, a moment after take-off: a barrel roll if the air time left looks long
## enough. The margin it keeps shrinks with skill falling, to below nothing at skill 0.
func _consider_stunt() -> void:
	if _jump_judged or cruise or _craft.air_time < 0.1 or not racer.is_racing():
		return
	_jump_judged = true
	var climb := _craft.linear_velocity.y
	var height := maxf(_craft.clearance, 0.0)
	var air_left := (climb + sqrt(climb * climb + 2.0 * 9.8 * height)) / 9.8
	var margin := lerpf(-0.08, 0.15, skill) + _rng.randf_range(-0.25, 0.05) * (1.0 - skill)
	if air_left > _craft.tuning.barrel_roll_time + margin and _rng.randf() < stunt_chance:
		_craft.controls.request_stunt(Vector2(-1.0 if _rng.randf() < 0.5 else 1.0, 0.0))


## The craft's neutral full-lock turn rate at [param speed], as [JetSki] computes it.
func _turn_rate(speed: float) -> float:
	var t := _craft.tuning
	return lerpf(t.turn_rate_low, t.turn_rate_high, smoothstep(t.turn_rate_peak_speed, t.reference_top_speed, speed))


## Keeps clear of other craft: moves the line away from a craft alongside, and to the
## side of one just ahead to pass it (less in tight turns, where the rider holds the line),
## easing back once clear. Closing fast on a craft right in front sets [member _blocked_ahead].
func _update_avoidance(position: Vector3, nose: Vector3, speed: float, offset: float, delta: float) -> void:
	var target := 0.0
	_blocked_ahead = false
	_yielding = false
	var right := nose.cross(Vector3.UP)
	var nearest := INF
	# Overtaking moves shrink to nothing in turns tighter than about 25 m.
	var turn_room := clampf(1.0 - absf(race.racing_line.curvature_at(offset)) * 25.0, 0.0, 1.0)
	var gates := race.course.gates
	var near_buoy := false
	if racer.next_gate < gates.size():
		var to_gate := wrapf(gates[racer.next_gate].offset - offset, -race.course.length * 0.5, race.course.length * 0.5)
		near_buoy = to_gate > 0.0 and to_gate < 30.0
	for other in race.racers:
		if other == racer:
			continue
		var to_other := other.craft.global_position - position
		to_other.y = 0.0
		var ahead := to_other.dot(nose)
		var aside := to_other.dot(right)
		var away := -signf(aside if absf(aside) > 0.2 else 1.0)
		if ahead > -3.0 and ahead < 4.0 and absf(aside) < 2.6:
			# Alongside: keep a craft's width between the hulls (less in turns), and if the
			# other craft is ahead and a buoy or a turn is coming, drop in behind it.
			target = away * side_gap * maxf(turn_room, 0.3)
			nearest = -INF
			if other.progress.distance > racer.progress.distance and (near_buoy or turn_room < 0.6):
				_yielding = true
		elif ahead >= 4.0 and ahead < 14.0 and absf(aside) < 2.5 and ahead < nearest:
			nearest = ahead
			target = away * overtake_offset * turn_room
			if ahead < 8.0 and absf(aside) < 1.6 and speed - other.craft.forward_speed > 2.0:
				_blocked_ahead = true
	_avoid = move_toward(_avoid, target, delta * 4.0)


## Sideways shift from the line: a slow wander that grows as skill falls, the shift round
## a craft ahead, and the planned wrong-side pass of a blundered buoy.
func _shift(offset: float) -> float:
	var wander := _noise.get_noise_1d(_time * 10.0) * (1.0 - skill) * 3.0 + _avoid
	if _blunder_gate >= 0 and _blunder_lap == racer.laps_done:
		var gate := race.course.gates[_blunder_gate]
		var ahead := wrapf(gate.offset - offset, -race.course.length * 0.5, race.course.length * 0.5)
		if ahead > -6.0 and ahead < 25.0:
			# Aim for the other side of the buoy.
			return -2.0 * gate.required_side * race.racing_line.clearance
	return wander


## True near the buoy this rider has decided to take on the wrong side.
func _blundering(offset: float) -> bool:
	if _blunder_gate < 0 or _blunder_lap != racer.laps_done:
		return false
	var gate := race.course.gates[_blunder_gate]
	var ahead := wrapf(gate.offset - offset, -race.course.length * 0.5, race.course.length * 0.5)
	return ahead > -6.0 and ahead < 25.0


## Once per lap, decides which buoy (if any) this rider will get wrong and how
## confident it is in the turns.
func _plan_mistakes(course: Course) -> void:
	if _blunder_lap == racer.laps_done or course.gates.is_empty():
		return
	_blunder_lap = racer.laps_done
	_blunder_gate = -1
	if _rng.randf() < blunder_chance * (1.0 - skill):
		_blunder_gate = _rng.randi_range(0, course.gates.size() - 1)
	# How boldly the rider takes the turns this lap: less skilled riders are more cautious
	# on the whole, but now and then overcook a lap and run wide.
	_confidence = lerpf(0.9, 1.0, skill) + _rng.randf_range(-0.05, 0.3) * (1.0 - skill)


func _check_stuck(speed: float, delta: float) -> void:
	if race.phase == Race.Phase.COUNTDOWN or not _craft.is_rider_aboard():
		_stuck_time = 0.0
		return
	if speed < 1.5 or racer.wrong_way:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > 1.8:
		_stuck_time = 0.0
		race.rescue(racer)
