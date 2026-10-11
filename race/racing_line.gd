class_name RacingLine
extends RefCounted
## The line computer riders follow round a [Course]: a sideways offset from the centre line
## at every centre-line sample. It passes each buoy on its marked side, [member clearance]
## meters from it, cuts to the inside of turns that have no buoy, eases smoothly between
## those points and stays clear of the walls. It also stores the line's curvature, from
## which a rider works out how fast it can take what is ahead.

## Distance kept from a buoy's centre when passing it.
var clearance: float = 4.0
## Distance kept from the walls.
var wall_margin: float = 3.0

var _course: Course
## Sideways offset from the centre line at each centre-line sample.
var _lateral := PackedFloat32Array()
## Curvature of the line itself at each sample, 1/m (positive: turning right).
var _curvature := PackedFloat32Array()
## The line's points, at the water's rest level.
var _points := PackedVector3Array()
## Course offsets of the buoy passing points, and their sideways offsets.
var _key_offsets := PackedFloat32Array()
var _key_laterals := PackedFloat32Array()


func _init(course: Course, p_clearance: float = 4.0) -> void:
	_course = course
	clearance = p_clearance
	_build()


## Sideways offset of the line at course [param offset].
func lateral_at(offset: float) -> float:
	return _lerp(_lateral, offset)


## Curvature of the line at course [param offset], 1/m, positive for a right turn.
func curvature_at(offset: float) -> float:
	return _lerp(_curvature, offset)


## The point of the line at course [param offset], with an extra sideways [param shift].
func point_at(offset: float, shift: float = 0.0) -> Vector3:
	return _course.point_at(offset) + _course.right_at(offset) * (lateral_at(offset) + shift)


## The buoy passing points as [offset, lateral] pairs, for tools.
func key_points() -> Array:
	var out := []
	for i in _key_offsets.size():
		out.append([_key_offsets[i], _key_laterals[i]])
	return out


## The highest speed, in m/s, at which a craft turning at up to [param turn_rate] rad/s
## can follow the line at [param offset] (it needs speed × curvature ≤ turn rate).
func speed_limit(offset: float, turn_rate: float) -> float:
	var k := absf(curvature_at(offset))
	return turn_rate / k if k > 1e-4 else INF


func _lerp(values: PackedFloat32Array, offset: float) -> float:
	var n := values.size()
	if n == 0:
		return 0.0
	var f := fposmod(offset, _course.length) / _course.length * n
	var i := int(f)
	return lerpf(values[i % n], values[(i + 1) % n], f - i)


func _build() -> void:
	var n := _course.sample_count()
	var step := _course.length / n
	# Key points: each buoy's passing point.
	var keys: Array[Vector2] = []
	for gate in _course.gates:
		var buoy_lateral := (gate.position - _course.point_at(gate.offset)).dot(_course.right_at(gate.offset))
		keys.append(Vector2(gate.offset, buoy_lateral + gate.required_side * clearance))
	# Turns without a buoy near their apex: cut to the inside, half way to the wall.
	var turn_keys: Array[Vector2] = []
	for i in n:
		var offset := i * step
		var k := _course.curvature_at(offset)
		if absf(k) < 1.0 / 60.0:
			continue
		if absf(k) < absf(_course.curvature_at(offset - step)) or absf(k) < absf(_course.curvature_at(offset + step)):
			continue
		var near_buoy := false
		for key in keys:
			if absf(wrapf(key.x - offset, -_course.length * 0.5, _course.length * 0.5)) < 30.0:
				near_buoy = true
		if near_buoy:
			continue
		var limits := _course.limits_at(offset)
		var inside := limits.y if k > 0.0 else limits.x
		turn_keys.append(Vector2(offset, inside * 0.5))
	keys.append_array(turn_keys)
	keys.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)
	_key_offsets.clear()
	_key_laterals.clear()
	for key in keys:
		_key_offsets.append(key.x)
		_key_laterals.append(key.y)

	# Hold each key from a little before to a little after it, ease between keys.
	_lateral.resize(n)
	for i in n:
		_lateral[i] = _lateral_from_keys(i * step, keys)
	# Keep off the walls.
	for i in n:
		var limits := _course.limits_at(i * step)
		_lateral[i] = clampf(_lateral[i], limits.x + wall_margin, limits.y - wall_margin)
	# Points and curvature of the line itself.
	_points.resize(n)
	for i in n:
		_points[i] = point_at(i * step)
	_curvature.resize(n)
	var span := maxi(int(4.0 / step), 1)
	for i in n:
		var a := _points[posmod(i - span, n)]
		var b := _points[i]
		var c := _points[(i + span) % n]
		_curvature[i] = _signed_curvature(a, b, c)
	# Smooth the curvature a little, so one kink doesn't dominate.
	var smoothed := PackedFloat32Array()
	smoothed.resize(n)
	for i in n:
		var total := 0.0
		for d in range(-span, span + 1):
			total += _curvature[posmod(i + d, n)]
		smoothed[i] = total / (2 * span + 1)
	_curvature = smoothed


func _lateral_from_keys(offset: float, keys: Array[Vector2]) -> float:
	if keys.is_empty():
		return 0.0
	var length := _course.length
	const BEFORE := 12.0
	const AFTER := 6.0
	# Previous and next key along the course, wrapping round the lap.
	var prev := keys[keys.size() - 1]
	var prev_distance := INF
	var next := keys[0]
	var next_distance := INF
	for key in keys:
		var ahead := fposmod(key.x - offset, length)
		var behind := fposmod(offset - key.x, length)
		if behind < prev_distance:
			prev_distance = behind
			prev = key
		if ahead < next_distance:
			next_distance = ahead
			next = key
	if prev_distance <= AFTER:
		return prev.y
	if next_distance <= BEFORE:
		return next.y
	var gap := prev_distance + next_distance - AFTER - BEFORE
	var t := clampf((prev_distance - AFTER) / maxf(gap, 0.01), 0.0, 1.0)
	return lerpf(prev.y, next.y, t * t * (3.0 - 2.0 * t))


## Signed curvature of the circle through three points (positive: turning right, which is
## clockwise seen from above).
static func _signed_curvature(a: Vector3, b: Vector3, c: Vector3) -> float:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var bc := Vector2(c.x - b.x, c.z - b.z)
	var ac := Vector2(c.x - a.x, c.z - a.z)
	var cross := ab.x * bc.y - ab.y * bc.x
	var denominator := ab.length() * bc.length() * ac.length()
	if denominator < 1e-6:
		return 0.0
	# With x right and z toward the viewer, a positive cross product is a clockwise turn
	# seen from above, which is a right turn.
	return 2.0 * cross / denominator
