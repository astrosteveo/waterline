class_name RacingLine
extends RefCounted
## The line computer riders follow round a [Course]: a sideways offset from the centre line
## at every centre-line sample. It passes each buoy on its marked side, [member clearance]
## meters from it, runs straight up each ramp, cuts to the inside of turns that have no buoy,
## eases smoothly between those points and stays clear of the walls. It also
## stores the line's curvature, from which a rider works out how fast it can take what is
## ahead.

## Distance kept from a buoy's centre when passing it.
var clearance: float = 4.0
## Distance kept from the walls.
var wall_margin: float = 3.0
## Distance kept from rocks, past their radius.
var obstacle_margin: float = 2.2
## More distance kept from rocks for each meter the waves' height passes 1 m.
var high_wave_margin: float = 5.0
## Least distance from a buoy's centre on its passing side, near the buoy.
var buoy_margin: float = 2.6
## Least distance from a ramp's sides, on the approach and up the ramp: a rider's moves round
## another craft and its wander keep it this far inside the ramp's width.
var ramp_margin: float = 1.2
## How far before a ramp's leading edge the line and a rider's moves keep to the ramp, so a
## rider meets it straight and on it.
var ramp_approach: float = 15.0

var _course: Course
## Sideways offset from the centre line at each centre-line sample.
var _lateral := PackedFloat32Array()
## The free gap around the line at each sample: walls and rocks either side...
var _low := PackedFloat32Array()
var _high := PackedFloat32Array()
## ...and the same gap that also keeps each buoy on its passing side.
var _keep_low := PackedFloat32Array()
var _keep_high := PackedFloat32Array()
## Curvature of the line itself at each sample, 1/m (positive: turning right).
var _curvature := PackedFloat32Array()
## The line's points, at the water's rest level.
var _points := PackedVector3Array()
## Course offsets of the key points (buoys, ramps, turns), and their sideways offsets.
var _key_offsets := PackedFloat32Array()
var _key_laterals := PackedFloat32Array()


func _init(course: Course, p_clearance: float = 4.0) -> void:
	_course = course
	clearance = p_clearance
	# High waves throw a craft off the crests, where it can't turn and flies wide in a bend:
	# keep further from the rocks.
	obstacle_margin += maxf(Ocean.wave_set.max_height() - 1.0, 0.0) * high_wave_margin
	for ramp: Ramp in course.find_children("*", "Ramp", true, false):
		var progress := CourseProgress.new()
		course.relocate(progress, ramp.global_position)
		ramp_offsets.append(progress.offset)
		ramp_laterals.append(progress.lateral)
		ramp_half_widths.append(ramp.width * 0.5)
		_ramp_lengths.append(ramp.length)
	_build()


## Where each ramp's middle is along the course (offsets), for riders to keep their lane and
## their distance over a jump.
var ramp_offsets := PackedFloat32Array()
## Each ramp's middle as a sideways offset from the centre line, and half its width.
var ramp_laterals := PackedFloat32Array()
var ramp_half_widths := PackedFloat32Array()
var _ramp_lengths := PackedFloat32Array()


## True from [param before] meters before a ramp to [param after] meters past it, where a
## craft launches and lands.
func near_ramp(offset: float, before: float = 30.0, after: float = 35.0) -> bool:
	for ramp in ramp_offsets:
		var ahead := wrapf(ramp - offset, -_course.length * 0.5, _course.length * 0.5)
		if ahead <= before and ahead >= -after:
			return true
	return false


## Sideways offset of the line at course [param offset].
func lateral_at(offset: float) -> float:
	return _lerp(_lateral, offset)


## Curvature of the line at course [param offset], 1/m, positive for a right turn.
func curvature_at(offset: float) -> float:
	return _lerp(_curvature, offset)


## The point of the line at course [param offset], moved sideways by [param shift] but kept
## clear of walls and rocks and on each buoy's passing side. With [param any_side] true the
## buoys don't count, for a rider who means to take one on the wrong side.
func point_at(offset: float, shift: float = 0.0, any_side: bool = false) -> Vector3:
	var low := _lerp(_low if any_side else _keep_low, offset)
	var high := _lerp(_high if any_side else _keep_high, offset)
	var lateral := clampf(lateral_at(offset) + shift, low, high)
	return _course.point_at(offset) + _course.right_at(offset) * lateral


## The narrowest free gap (walls, rocks and buoys' passing sides) between course offsets
## [param from] and [param to], sampled every 2 m: Vector2(highest low side, lowest high side).
func gap_between(from: float, to: float) -> Vector2:
	var low := -INF
	var high := INF
	var span := fposmod(to - from, _course.length)
	var s := 0.0
	while true:
		low = maxf(low, _lerp(_keep_low, from + s))
		high = minf(high, _lerp(_keep_high, from + s))
		if s >= span:
			break
		s = minf(s + 2.0, span)
	return Vector2(low, maxf(high, low))


## How far the line can move sideways at [param offset] before meeting a wall or a rock:
## Vector2(lowest lateral, highest lateral).
func free_gap_at(offset: float) -> Vector2:
	return Vector2(_lerp(_low, offset), _lerp(_high, offset))


## The line every [param spacing] meters as [offset, lateral, lowest, highest] rows, for tools.
func table(spacing: float = 2.0) -> Array:
	var rows := []
	var offset := 0.0
	while offset < _course.length:
		var gap := free_gap_at(offset)
		rows.append([offset, lateral_at(offset), gap.x, gap.y])
		offset += spacing
	return rows


## The key points (buoys' passing points, ramps' leading edges and lips, the insides of
## turns) as [offset, lateral] pairs, for tools.
func key_points() -> Array:
	var out := []
	for i in _key_offsets.size():
		out.append([_key_offsets[i], _key_laterals[i]])
	return out


## The highest speed, in m/s, at which a craft can follow the line at [param offset]: it
## needs speed × curvature ≤ [param turn_rate] (rad/s) to turn the nose fast enough, and
## speed² × curvature ≤ [param side_accel] (m/s²) for the hull to hold the line without
## sliding wide.
func speed_limit(offset: float, turn_rate: float, side_accel: float = INF) -> float:
	var k := absf(curvature_at(offset))
	if k < 1e-4:
		return INF
	return minf(turn_rate / k, sqrt(side_accel / k))


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
	# Real turns (tighter than 30 m, at least 35 degrees) without a buoy near their apex:
	# cut to the inside, half way to the wall. Gentle bends keep the line between buoys.
	var turn_keys: Array[Vector2] = []
	for i in n:
		var offset := i * step
		var k := _course.curvature_at(offset)
		if absf(k) < 1.0 / 30.0:
			continue
		if absf(k) < absf(_course.curvature_at(offset - step)) or absf(k) < absf(_course.curvature_at(offset + step)):
			continue
		var turned := 0.0
		var d := -20.0
		while d <= 20.0:
			turned += _course.curvature_at(offset + d) * 2.0
			d += 2.0
		if absf(turned) < deg_to_rad(35.0):
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
	# Each ramp's leading edge and lip, where the line would cross the ramp's middle anyway,
	# moved only as far as it takes to keep [member ramp_margin] inside the ramp's sides. The
	# line holds a key from 12 m before it, so it runs straight from there up the ramp and off
	# the lip. Held to the ramp's middle instead, the line swerved at the foot of a ramp with a
	# buoy just before it, and riders in high waves launched turning and nose-dived.
	var ramp_keys: Array[Vector2] = []
	for r in ramp_offsets.size():
		var half := maxf(ramp_half_widths[r] - ramp_margin, 0.0)
		var lateral := clampf(_lateral_from_keys(ramp_offsets[r], keys), ramp_laterals[r] - half, ramp_laterals[r] + half)
		ramp_keys.append(Vector2(fposmod(ramp_offsets[r] - _ramp_lengths[r] * 0.5, _course.length), lateral))
		ramp_keys.append(Vector2(fposmod(ramp_offsets[r] + _ramp_lengths[r] * 0.5, _course.length), lateral))
	keys.append_array(ramp_keys)
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
	# Keep off the walls and round the rocks, then smooth what that bent.
	_low.resize(n)
	_high.resize(n)
	var rocks := _course.obstacles()
	for i in n:
		_fit_gap(i, step, rocks)
	_keep_low = _low.duplicate()
	_keep_high = _high.duplicate()
	for gate in _course.gates:
		var buoy_lateral := (gate.position - _course.point_at(gate.offset)).dot(_course.right_at(gate.offset))
		var first := int(floor((gate.offset - 4.0) / step))
		for j in range(first, first + int(8.0 / step) + 1):
			var i := posmod(j, n)
			if gate.required_side > 0:
				_keep_low[i] = minf(maxf(_keep_low[i], buoy_lateral + buoy_margin), _keep_high[i])
			elif gate.required_side < 0:
				_keep_high[i] = maxf(minf(_keep_high[i], buoy_lateral - buoy_margin), _keep_low[i])
	# From the approach to the lip, keep to the ramp, inside its width.
	for r in ramp_offsets.size():
		var half := maxf(ramp_half_widths[r] - ramp_margin, 0.0)
		var first := int(floor((ramp_offsets[r] - _ramp_lengths[r] * 0.5 - ramp_approach) / step))
		var last := int(ceil((ramp_offsets[r] + _ramp_lengths[r] * 0.5) / step))
		for j in range(first, last + 1):
			var i := posmod(j, n)
			_keep_low[i] = minf(maxf(_keep_low[i], ramp_laterals[r] - half), _keep_high[i])
			_keep_high[i] = maxf(minf(_keep_high[i], ramp_laterals[r] + half), _keep_low[i])
	# Blur and clamp in turns, like an elastic band pulled round the rocks, so the line moves
	# over gradually before a rock instead of jumping at its edge.
	var reach := maxi(int(6.0 / step), 1)
	for _round in 10:
		var smoothed := _lateral.duplicate()
		for i in n:
			var total := 0.0
			for d in range(-reach, reach + 1):
				total += _lateral[posmod(i + d, n)]
			smoothed[i] = clampf(total / (2 * reach + 1), _keep_low[i], _keep_high[i])
		_lateral = smoothed
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


## Moves the line at sample [param i] out of any rock's way and records the free gap round it.
func _fit_gap(i: int, step: float, rocks: Array[Vector3]) -> void:
	var offset := i * step
	var centre := _course.point_at(offset)
	var forward := _course.tangent_at(offset)
	var right := forward.cross(Vector3.UP)
	var limits := _course.limits_at(offset)
	var low := limits.x + wall_margin
	var high := limits.y - wall_margin
	var lateral := clampf(_lateral[i], low, high)
	var blocked: Array[Vector2] = []
	for rock in rocks:
		var to_rock := Vector3(rock.x, 0.0, rock.y) - centre
		var along := to_rock.dot(forward)
		var reach := rock.z + obstacle_margin
		if absf(along) >= reach:
			continue
		var half := sqrt(reach * reach - along * along)
		var side := to_rock.dot(right)
		blocked.append(Vector2(side - half, side + half))
	for gap in blocked:
		if lateral > gap.x and lateral < gap.y:
			lateral = gap.x if lateral - gap.x < gap.y - lateral else gap.y
	for gap in blocked:
		if gap.y <= lateral:
			low = maxf(low, gap.y)
		elif gap.x >= lateral:
			high = minf(high, gap.x)
	_low[i] = low
	_high[i] = maxf(high, low)
	_lateral[i] = clampf(lateral, _low[i], _high[i])


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
