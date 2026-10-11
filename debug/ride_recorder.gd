class_name RideRecorder
extends Node
## Collects ride statistics from a [JetSki] every physics tick, for tuning and tests.
## Call [method reset] before a run and read [method report] after it, for example from
## gdh: [code]gdh live eval "scene.get_node('RideRecorder').report()"[/code].

@export var craft: JetSki
@export var chase_camera: ChaseCamera

var _ticks := 0
var _airborne_ticks := 0
var _sliding_ticks := 0
var _carving_ticks := 0
var _speed_sum := 0.0
var _top_speed := 0.0
var _jumps: Array[Dictionary] = []
var _jump_start_height := 0.0
var _jump_peak := 0.0
var _jump_ticks := 0
var _was_airborne := false
var _max_grip_usage := 0.0
var _max_slip := 0.0
var _min_camera_gap := INF
var _start_position := Vector3.ZERO
var _distance := 0.0
var _last_position := Vector3.ZERO
var _yaw_turned := 0.0
var _last_yaw := 0.0
var _crashes_at_reset := 0


func _ready() -> void:
	# Run after the physics step has updated the craft's telemetry.
	process_physics_priority = 100
	reset()


## Clears the statistics and starts counting from the craft's current state.
func reset() -> void:
	_ticks = 0
	_airborne_ticks = 0
	_sliding_ticks = 0
	_carving_ticks = 0
	_speed_sum = 0.0
	_top_speed = 0.0
	_jumps.clear()
	_was_airborne = false
	_max_grip_usage = 0.0
	_max_slip = 0.0
	_min_camera_gap = INF
	_distance = 0.0
	_yaw_turned = 0.0
	if craft != null:
		_crashes_at_reset = craft.crash_count
		_start_position = craft.global_position
		_last_position = craft.global_position
		_last_yaw = craft.global_rotation.y
	if chase_camera != null:
		chase_camera.min_water_gap = INF


func _physics_process(_delta: float) -> void:
	if craft == null:
		return
	_ticks += 1
	_speed_sum += craft.speed
	_top_speed = maxf(_top_speed, craft.speed)
	_max_grip_usage = maxf(_max_grip_usage, craft.grip_usage)
	_max_slip = maxf(_max_slip, absf(craft.slip_angle))
	if craft.sliding:
		_sliding_ticks += 1
	if craft.carving:
		_carving_ticks += 1
	var here := craft.global_position
	_distance += Vector2(here.x - _last_position.x, here.z - _last_position.z).length()
	_last_position = here
	var yaw := craft.global_rotation.y
	_yaw_turned += absf(wrapf(yaw - _last_yaw, -PI, PI))
	_last_yaw = yaw
	if chase_camera != null:
		_min_camera_gap = minf(_min_camera_gap, chase_camera.min_water_gap)

	if craft.airborne:
		_airborne_ticks += 1
		if not _was_airborne:
			_jump_start_height = craft.water_height
			_jump_peak = craft.clearance
			_jump_ticks = 0
		_jump_ticks += 1
		_jump_peak = maxf(_jump_peak, craft.clearance)
	elif _was_airborne and _jump_ticks > 0:
		_jumps.append({"air_time": _jump_ticks / float(Engine.physics_ticks_per_second), "peak_clearance": _jump_peak})
	_was_airborne = craft.airborne


## The statistics since the last reset.
func report() -> Dictionary:
	var seconds := _ticks / float(Engine.physics_ticks_per_second)
	var long_jumps := 0
	var longest := 0.0
	var highest := 0.0
	for jump in _jumps:
		longest = maxf(longest, jump["air_time"])
		highest = maxf(highest, jump["peak_clearance"])
		if jump["air_time"] >= 0.4:
			long_jumps += 1
	return {
		"seconds": seconds,
		"distance_m": _distance,
		"average_speed_kmh": _speed_sum / maxf(_ticks, 1) * 3.6,
		"top_speed_kmh": _top_speed * 3.6,
		"airborne_share": _airborne_ticks / float(maxi(_ticks, 1)),
		"jumps": _jumps.size(),
		"jumps_over_0_4s": long_jumps,
		"longest_air_s": longest,
		"highest_clearance_m": highest,
		"sliding_share": _sliding_ticks / float(maxi(_ticks, 1)),
		"carving_share": _carving_ticks / float(maxi(_ticks, 1)),
		"max_grip_usage": _max_grip_usage,
		"max_slip_degrees": rad_to_deg(_max_slip),
		"turned_degrees": rad_to_deg(_yaw_turned),
		"min_camera_gap_m": _min_camera_gap,
		"displacement": craft.global_position - _start_position if craft != null else Vector3.ZERO,
		"crashes": craft.crash_count - _crashes_at_reset if craft != null else 0,
	}
