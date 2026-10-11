class_name Race
extends Node3D
## Runs a race on a course: loads the course scene, puts the racers on the starting grid,
## counts down, then every physics tick tracks each racer along the course, judges buoy
## passes by the side the racer crossed on, counts laps and times them.
##
## Times come from physics ticks, and a crossing is placed within its tick by
## interpolating the racer's movement, so lap times don't depend on the frame rate.

## Seconds left in the countdown: 3, 2, 1, then 0 for "go".
signal countdown_changed(seconds_left: int)
## The racers were released.
signal started
## A racer crossed a buoy's gate: [param correct] is false for the wrong side or a
## skipped buoy.
signal gate_judged(racer: RacerState, gate: CourseGate, correct: bool)
## A racer crossed the finish line at the end of a lap.
signal lap_completed(racer: RacerState, lap: int, lap_time: float)
## A racer finished the race.
signal racer_finished(racer: RacerState)
## A racer's power meter changed.
signal power_changed(racer: RacerState, level: int)
## A racer missed too many buoys and is out of the race.
signal racer_disqualified(racer: RacerState)
## A racer's rider was thrown off.
signal racer_crashed(racer: RacerState, reason: StringName)
## The player finished or was disqualified; the race is over for them.
signal finished

enum Phase {
	## Racers wait on the grid.
	COUNTDOWN,
	## The clock runs.
	RACING,
	## The player is done.
	FINISHED,
}

## The course to race on: a scene whose root is a [Course].
@export var course_scene: PackedScene
## The craft every racer rides.
@export var craft_scene: PackedScene = preload("res://jetski/jetski.tscn")
## The power meter and disqualification rules.
@export var rules: RaceRules
## Laps to race; 0 uses the course's own number.
@export_range(0, 9, 1) var laps_override: int = 0
## Seconds of countdown before the start.
@export_range(0.0, 10.0, 0.1, "suffix:s") var countdown_time: float = 3.0
## Starting slot of the player, counted from the left.
@export_range(0, 7, 1) var player_slot: int = 1
## Slots on the starting grid.
@export_range(1, 8, 1) var grid_slots: int = 4
## Seconds of moving against the course before the racer is told it is going the wrong way.
@export_range(0.1, 5.0, 0.1, "suffix:s") var wrong_way_delay: float = 1.0

@export_group("Nodes")
@export var chase_camera: ChaseCamera
@export var debug_hud: DebugHud
@export var ride_recorder: RideRecorder
@export var camera_switcher: CameraSwitcher

var course: Course
var racers: Array[RacerState] = []
var player: RacerState
var phase: Phase = Phase.COUNTDOWN
## Seconds since the start.
var race_time: float = 0.0
## Laps in this race.
var laps: int = 3

var _ticks := 0
var _countdown_left := 0.0
var _last_countdown_second := -1


func _ready() -> void:
	# After the racers' input (priority 0), before the ride recorder (100).
	process_physics_priority = 50
	if rules == null:
		rules = RaceRules.new()
	if course_scene == null:
		push_error("Race needs a course scene.")
		return
	course = course_scene.instantiate() as Course
	if course == null:
		push_error("The course scene's root must be a Course.")
		return
	add_child(course)
	move_child(course, 0)
	laps = laps_override if laps_override > 0 else course.laps
	_spawn_player()
	for racer in racers:
		course.track(racer.progress, racer.craft.global_position)
		racer.last_position = _flat(racer.craft.global_position)
	_countdown_left = countdown_time
	phase = Phase.COUNTDOWN


func _spawn_player() -> void:
	var craft := craft_scene.instantiate() as JetSki
	craft.name = "Player"
	var racer := _add_racer(craft, "You", player_slot)
	racer.is_player = true
	player = racer
	var input := PlayerInput.new()
	input.name = "PlayerInput"
	craft.add_child(input)
	if chase_camera != null:
		chase_camera.set_target(craft)
	if debug_hud != null:
		debug_hud.craft = craft
	if ride_recorder != null:
		ride_recorder.craft = craft
		ride_recorder.reset()
	if camera_switcher != null:
		camera_switcher.player_input = input


## Adds a racer riding [param craft] (not yet in the tree) in starting slot [param slot].
func _add_racer(craft: JetSki, display_name: String, slot: int) -> RacerState:
	var holder := get_node_or_null(^"Racers")
	if holder == null:
		holder = Node3D.new()
		holder.name = "Racers"
		add_child(holder)
	var grid := course.grid_transform(slot, grid_slots)
	craft.transform = grid
	holder.add_child(craft)
	craft.hold(grid)
	var racer := RacerState.new()
	racer.craft = craft
	racer.display_name = display_name
	racers.append(racer)
	craft.reset_handler = rescue.bind(racer)
	craft.power_multiplier = rules.thrust_for(0)
	craft.crashed.connect(_on_crashed.bind(racer))
	return racer


func _physics_process(delta: float) -> void:
	if course == null:
		return
	if phase == Phase.COUNTDOWN:
		_countdown_left -= delta
		var second := ceili(_countdown_left)
		if second != _last_countdown_second:
			_last_countdown_second = second
			countdown_changed.emit(maxi(second, 0))
		if _countdown_left <= 0.0:
			_start()
		for racer in racers:
			_follow(racer)
		return
	_ticks += 1
	race_time = _ticks * delta
	for racer in racers:
		_update_racer(racer, delta)
	_update_places()


func _start() -> void:
	phase = Phase.RACING
	_ticks = 0
	race_time = 0.0
	for racer in racers:
		racer.craft.release()
		racer.lap_start_time = 0.0
	started.emit()


## Tracks a racer's position without judging anything (before the start).
func _follow(racer: RacerState) -> void:
	var here := _flat(racer.craft.global_position)
	course.track(racer.progress, here)
	racer.last_position = here


func _update_racer(racer: RacerState, delta: float) -> void:
	var here := _flat(racer.craft.global_position)
	var before := racer.last_position
	racer.last_position = here
	if racer.teleport_ticks > 0:
		racer.teleport_ticks -= 1
		course.relocate(racer.progress, here)
		if not is_nan(racer.place_distance):
			racer.progress.distance = racer.place_distance
			if racer.teleport_ticks == 0:
				racer.place_distance = NAN
		return
	course.track(racer.progress, here)
	_update_wrong_way(racer, before, here, delta)
	if not racer.is_racing():
		return
	var gates := course.gates
	# Buoy gates: the next one, or a later one if the racer skipped some.
	for look in 3:
		var index := racer.next_gate + look
		if index >= gates.size():
			break
		var gate := gates[index]
		var t := gate.crossing(before, here)
		if t < 0.0:
			continue
		for skipped in range(racer.next_gate, index):
			_judge(racer, gates[skipped], false)
		_judge(racer, gate, gate.is_correct_side(before.lerp(here, t)))
		racer.next_gate = index + 1
		break
	# A gate left far behind without being crossed (the racer was moved past it) is missed.
	var lap_distance := racer.lap_distance(course.length)
	while racer.next_gate < gates.size() and lap_distance > gates[racer.next_gate].offset + 30.0:
		_judge(racer, gates[racer.next_gate], false)
		racer.next_gate += 1
	# The finish line, once the racer has come most of the way round.
	var t_finish := course.finish_gate.crossing(before, here)
	if t_finish >= 0.0 and racer.progress.distance >= (racer.laps_done + 1) * course.length - 60.0:
		for missed in range(racer.next_gate, gates.size()):
			_judge(racer, gates[missed], false)
		racer.next_gate = 0
		_complete_lap(racer, race_time - delta + t_finish * delta)


func _judge(racer: RacerState, gate: CourseGate, correct: bool) -> void:
	if not racer.is_racing():
		return
	if correct:
		racer.buoys_passed += 1
		_set_power(racer, mini(racer.power + 1, rules.power_levels))
	else:
		racer.buoys_missed += 1
		if rules.miss_resets_power:
			_set_power(racer, 0)
	if racer.is_player and gate.buoy != null:
		gate.buoy.flash(Color(1.0, 1.0, 1.0) if correct else Color(0.1, 0.1, 0.1), 0.7)
	gate_judged.emit(racer, gate, correct)
	if not correct and rules.misses_to_disqualify > 0 and racer.buoys_missed >= rules.misses_to_disqualify:
		_disqualify(racer)


func _set_power(racer: RacerState, level: int) -> void:
	if level == racer.power:
		return
	racer.power = level
	racer.craft.power_multiplier = rules.thrust_for(level)
	power_changed.emit(racer, level)


func _disqualify(racer: RacerState) -> void:
	racer.disqualified = true
	racer.finish_time = race_time
	racer.next_gate = 0
	racer_disqualified.emit(racer)
	if racer.is_player:
		phase = Phase.FINISHED
		finished.emit()


func _on_crashed(reason: StringName, racer: RacerState) -> void:
	racer.crashes += 1
	racer_crashed.emit(racer, reason)


func _complete_lap(racer: RacerState, at_time: float) -> void:
	var lap_time := at_time - racer.lap_start_time
	racer.lap_times.append(lap_time)
	racer.laps_done += 1
	racer.lap_start_time = at_time
	lap_completed.emit(racer, racer.laps_done, lap_time)
	if racer.laps_done >= laps:
		racer.finished = true
		racer.finish_time = at_time
		racer_finished.emit(racer)
		if racer.is_player:
			phase = Phase.FINISHED
			finished.emit()


func _update_wrong_way(racer: RacerState, before: Vector3, here: Vector3, delta: float) -> void:
	var along := (here - before).dot(course.tangent_at(racer.progress.offset)) / delta
	if along < -1.5:
		racer.reverse_time += delta
	elif along > 1.0:
		racer.reverse_time = 0.0
	racer.wrong_way = racer.reverse_time >= wrong_way_delay


func _update_places() -> void:
	var order := racers.duplicate()
	order.sort_custom(func(a: RacerState, b: RacerState) -> bool: return Race.is_ahead(a, b))
	for i in order.size():
		(order[i] as RacerState).place = i + 1


## True if racer [param a] is ahead of racer [param b].
static func is_ahead(a: RacerState, b: RacerState) -> bool:
	if a.disqualified != b.disqualified:
		return b.disqualified
	if a.finished != b.finished:
		return a.finished
	if a.finished:
		return a.finish_time < b.finish_time
	return a.progress.distance > b.progress.distance


## Puts [param racer]'s craft back on the course where it is, facing the way the course
## goes, stopped. The rider's reset action calls it.
func rescue(racer: RacerState) -> void:
	racer.craft.respawn(_clear_spot(racer.progress.offset, racer.progress.lateral, racer.craft))
	racer.teleport_ticks = 2
	racer.reverse_time = 0.0


## A spot on the course near [param offset] with nothing solid within a few meters: where
## the racer was across the course if that is clear, else the centre line, else either
## side, trying a little further on if needed. It faces along the course.
func _clear_spot(offset: float, lateral: float, craft: JetSki) -> Transform3D:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	query.shape = sphere
	query.collision_mask = PhysicsLayers.SCENERY | PhysicsLayers.FLOATING | PhysicsLayers.CRAFT
	query.exclude = [craft.get_rid()]
	for ahead in [0.0, 10.0, 20.0, -10.0, 30.0]:
		var at: float = offset + ahead
		var limits := course.limits_at(at)
		for candidate in [lateral, 0.0, limits.x * 0.5, limits.y * 0.5]:
			var side := clampf(candidate, limits.x + 4.0, limits.y - 4.0)
			var spot := course.transform_at(at, side)
			query.transform = Transform3D(Basis.IDENTITY, spot.origin + Vector3.UP * 0.5)
			if space.intersect_shape(query, 1).is_empty():
				return spot
	return course.transform_at(offset, 0.0)


## Moves [param racer] to the course point [param offset] meters past the start line and
## [param lateral] meters right of the centre line, facing along the course (or against it
## when [param backwards]), moving at [param speed] m/s. For tests and tools.
func place_racer(racer: RacerState, offset: float, lateral: float = 0.0, speed: float = 0.0,
		backwards: bool = false) -> void:
	var where := course.transform_at(offset, lateral)
	if backwards:
		where.basis = where.basis.rotated(Vector3.UP, PI)
	racer.craft.respawn(where, speed)
	racer.teleport_ticks = 2
	racer.reverse_time = 0.0
	racer.place_distance = racer.laps_done * course.length + offset


## 1st, 2nd, 3rd, 4th...
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1:
				suffix = "st"
			2:
				suffix = "nd"
			3:
				suffix = "rd"
	return "%d%s" % [n, suffix]


## The race time formatted as m:ss.cc.
static func format_time(seconds: float) -> String:
	if seconds == INF or seconds < 0.0:
		return "-:--.--"
	var hundredths := int(roundf(seconds * 100.0))
	return "%d:%02d.%02d" % [hundredths / 6000, (hundredths / 100) % 60, hundredths % 100]


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
