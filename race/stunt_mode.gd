class_name StuntMode
extends Node
## Stunt mode: one lap against the clock, scored on rings and stunts.
##
## Rings float along the racing line, and one hangs past each ramp's lip. Passing through a
## ring scores [member ring_points] (double for an air ring), times a chain multiplier that
## grows with each ring in a row and drops back when a ring is missed, and adds a power level.
## Landed stunts score their points ([method JetSki.stunt_points]). Finishing the lap before
## the time runs out adds [member finish_bonus] per second left. The run ends at the finish
## line or when the time runs out.

## The score changed.
signal score_changed(score: int)
## The player went through [param ring], scoring [param points] at [param multiplier].
signal ring_taken(ring: StuntRing, points: int, multiplier: float)
## The player rode past a ring without going through it.
signal ring_missed(ring: StuntRing)
## The run is over: [param completed] is true if the player finished the lap in time.
signal run_over(completed: bool)

@export var ring_points: int = 100
## Each ring in a row adds this to the multiplier...
@export_range(0.0, 2.0, 0.05) var chain_step: float = 0.25
## ...up to this.
@export_range(1.0, 10.0, 0.1) var max_multiplier: float = 3.0
## Distance between floating rings along the course, in meters.
@export_range(10.0, 200.0, 1.0, "suffix:m") var ring_spacing: float = 50.0
## No floating ring within this distance of a buoy or a ramp.
@export_range(0.0, 50.0, 1.0, "suffix:m") var keep_clear: float = 18.0
## Seconds allowed per meter of the lap; the limit is rounded up to 5 s.
@export_range(0.01, 1.0, 0.001) var seconds_per_meter: float = 0.1
## Points per second left at the finish.
@export var finish_bonus: int = 10

var race: Race
var rings: Array[StuntRing] = []
var score: int = 0
var ring_score: int = 0
var stunt_score: int = 0
var finish_score: int = 0
var rings_taken: int = 0
## Rings in a row without a miss.
var chain: int = 0
var time_limit: float = 60.0
var over: bool = false
var completed: bool = false

var _ring_offsets: PackedFloat32Array = PackedFloat32Array()
var _ring_done: PackedByteArray = PackedByteArray()
var _last := Vector3.ZERO


func _ready() -> void:
	# After the race (50) has tracked the racers this tick.
	process_physics_priority = 55


## Builds the rings on [param p_race]'s course and starts listening to the race.
func setup(p_race: Race) -> void:
	race = p_race
	time_limit = ceilf(race.course.length * seconds_per_meter / 5.0) * 5.0
	_build_rings()
	race.racer_landed.connect(_on_landed)
	race.racer_finished.connect(_on_finished)
	race.started.connect(func() -> void: _last = _centre())


## Seconds left on the clock.
func time_left() -> float:
	if race == null or race.phase == Race.Phase.COUNTDOWN:
		return time_limit
	return maxf(time_limit - race.race_time, 0.0)


## The current ring multiplier.
func multiplier() -> float:
	return minf(1.0 + chain * chain_step, max_multiplier)


func _physics_process(_delta: float) -> void:
	if race == null or over or race.phase != Race.Phase.RACING:
		return
	var here := _centre()
	var player := race.player
	if not player.craft.is_rider_aboard():
		_last = here
		return
	for i in rings.size():
		if _ring_done[i] == 1:
			continue
		var ring := rings[i]
		if ring.crosses(_last, here):
			_take(i)
		elif ring.misses(_last, here) or _left_behind(i, player):
			_miss(i)
	_last = here
	if race.race_time >= time_limit:
		_end(false)


func _centre() -> Vector3:
	var craft := race.player.craft
	return craft.global_transform * Vector3(0.0, 0.6, 0.0)


func _left_behind(i: int, player: RacerState) -> bool:
	var ahead := player.progress.offset - _ring_offsets[i]
	return player.laps_done == 0 and ahead > 20.0 and ahead < race.course.length * 0.5


func _take(i: int) -> void:
	_ring_done[i] = 1
	var ring := rings[i]
	var factor := multiplier()
	var points := roundi(ring_points * (1 if ring.floating else 2) * factor)
	chain += 1
	rings_taken += 1
	ring_score += points
	ring.take()
	race.add_power(race.player, 1)
	_add(points)
	ring_taken.emit(ring, points, factor)


func _miss(i: int) -> void:
	_ring_done[i] = 1
	chain = 0
	ring_missed.emit(rings[i])


func _add(points: int) -> void:
	score += points
	score_changed.emit(score)


func _on_landed(racer: RacerState, quality: StringName, stunts: Array[StringName], points: int) -> void:
	if racer != race.player or over or quality == &"failed" or stunts.is_empty():
		return
	stunt_score += points
	_add(points)


func _on_finished(racer: RacerState) -> void:
	if racer != race.player or over:
		return
	finish_score = int(floorf(maxf(time_limit - racer.finish_time, 0.0))) * finish_bonus
	_add(finish_score)
	_end(true)


func _end(finished: bool) -> void:
	if over:
		return
	over = true
	completed = finished
	if not finished:
		race.end_for_player()
	run_over.emit(finished)


func _build_rings() -> void:
	var course := race.course
	var line := race.racing_line
	var holder := Node3D.new()
	holder.name = "Rings"
	race.add_child(holder)
	# Places to keep clear: buoys and ramps.
	var avoid := PackedFloat32Array()
	for gate in course.gates:
		avoid.append(gate.offset)
	var ramps := course.find_children("*", "Ramp", true, false)
	var probe := CourseProgress.new()
	for node in ramps:
		course.relocate(probe, (node as Node3D).global_position)
		avoid.append(probe.offset)
	var last := -INF
	var s := 40.0
	while s < course.length - 30.0:
		var clear := true
		for a in avoid:
			if absf(wrapf(s - a, -course.length * 0.5, course.length * 0.5)) < keep_clear:
				clear = false
				break
		if clear and s - last >= ring_spacing:
			var ring := StuntRing.new()
			ring.name = "Ring%d" % (rings.size() + 1)
			ring.radius = 2.9
			var at := line.point_at(s)
			ring.transform = Transform3D(Basis.looking_at(course.tangent_at(s), Vector3.UP), at)
			holder.add_child(ring)
			_add_ring(ring, s)
			last = s
		s += 2.0
	# Air rings past each ramp's lip, where a full-speed jump flies.
	for node in ramps:
		var ramp := node as Ramp
		var forward := -ramp.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var lip := ramp.global_transform * Vector3(0.0, ramp.top, -ramp.length * 0.5)
		var ring := StuntRing.new()
		ring.name = "AirRing%d" % (rings.size() + 1)
		ring.floating = false
		ring.color = Color(0.3, 0.9, 1.0)
		ring.transform = Transform3D(Basis.looking_at(forward, Vector3.UP), lip + forward * 9.0 + Vector3.UP * 1.2)
		holder.add_child(ring)
		course.relocate(probe, ring.global_position)
		_add_ring(ring, probe.offset)
	# In course order, so the HUD can count them in order.
	var order := range(rings.size())
	order.sort_custom(func(a: int, b: int) -> bool: return _ring_offsets[a] < _ring_offsets[b])
	var sorted_rings: Array[StuntRing] = []
	var sorted_offsets := PackedFloat32Array()
	for i in order:
		sorted_rings.append(rings[i])
		sorted_offsets.append(_ring_offsets[i])
	rings = sorted_rings
	_ring_offsets = sorted_offsets


func _add_ring(ring: StuntRing, offset: float) -> void:
	rings.append(ring)
	_ring_offsets.append(offset)
	_ring_done.append(0)
