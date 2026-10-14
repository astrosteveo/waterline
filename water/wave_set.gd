@tool
class_name WaveSet
extends Resource
## The wave parameters that the water shader and the physics share.
##
## The shader displaces the water mesh with the sum of these Gerstner waves, and the
## functions here compute the same surface on the CPU, from the same numbers, for the
## jet skis, buoys and floating objects. [OceanSurface] packs the waves into shader
## uniforms with [method get_shader_wave_data] and [method get_shader_wave_phases].
##
## Gerstner waves move points sideways as well as up, so the point drawn at a world
## position (x, z) started somewhere else. [method sample] and [method height_at] find
## that rest position with Newton's method, then evaluate the waves there.
##
## A wave set can also change into another one over time: [method changing_to] makes a
## new set whose wave amplitudes move from this set's to the target's, as a function of
## wave time only. While it changes, every function that takes a time uses the amplitudes
## at that time, and the shader gets them from [method get_shader_wave_shapes].

## The most waves the shader accepts (the size of its uniform arrays).
const MAX_WAVES := 16
## Floats per wave in the packed array: dir.x, dir.z, k, omega, amplitude,
## horizontal amplitude, phase, wavelength.
const STRIDE := 8
## Newton iterations when inverting the horizontal displacement. Each one roughly squares
## the error; see NOTES.md for the measured accuracy.
const SOLVE_ITERATIONS := 4

## The wave trains, summed. Long swells move the jet ski; short ones add chop.
@export var waves: Array[GerstnerWave] = []:
	set(value):
		for wave in waves:
			if wave != null and wave.changed.is_connected(_on_wave_changed):
				wave.changed.disconnect(_on_wave_changed)
		waves = value
		for wave in waves:
			if wave != null and not wave.changed.is_connected(_on_wave_changed):
				wave.changed.connect(_on_wave_changed)
		# A change in progress refers to the old waves by index.
		_start_amplitudes = PackedFloat64Array()
		_change_duration = -1.0
		_on_wave_changed()

## Multiplies every wave's amplitude: below 1 for calm water, above 1 for rough water.
@export_range(0.0, 3.0, 0.01) var amplitude_scale: float = 1.0:
	set(value):
		amplitude_scale = maxf(value, 0.0)
		_on_wave_changed()

## Multiplies every wave's speed.
@export_range(0.0, 4.0, 0.01) var time_scale: float = 1.0:
	set(value):
		time_scale = maxf(value, 0.0)
		_on_wave_changed()

## Gravity used for the deep-water dispersion relation omega = sqrt(g * k).
@export var gravity: float = 9.81:
	set(value):
		gravity = maxf(value, 0.01)
		_on_wave_changed()

var _packed := PackedFloat64Array()
var _count := 0
var _dirty := true
# A change made by changing_to(): each wave's amplitude when the change starts (the
# wave's own amplitude is the one it ends at), indexed like `waves`, and the change's
# start and length in wave time. No change while _change_duration is negative.
var _start_amplitudes := PackedFloat64Array()
var _change_start := 0.0
var _change_duration := -1.0
# Per packed wave: amplitude and horizontal amplitude at the start and at the end of the
# change. _ensure_amplitudes() writes the ones for a time into _packed.
var _ends := PackedFloat64Array()
# The change weight whose amplitudes _packed holds (NAN: none yet).
var _packed_weight := NAN


## A new wave set that starts as this one is at wave time [param start_time] and changes
## into [param target] over [param duration] seconds. Only amplitudes change: a wave of
## this set fades out, a wave of [param target] fades in, and a wave in both (same
## direction, wavelength, sharpness, phase and speed) changes amplitude in place. Each
## wave keeps its wavelength, direction and speed, so the surface never jumps. The new
## set holds copies of the waves, so neither this set nor [param target] changes.
## When this set is itself changing, the new one starts from its amplitudes at
## [param start_time].
func changing_to(target: WaveSet, start_time: float, duration: float) -> WaveSet:
	var copies: Array[GerstnerWave] = []
	var starts := PackedFloat64Array()
	var speeds := PackedFloat64Array()
	for i in waves.size():
		var wave := waves[i]
		if wave == null:
			continue
		var amplitude := _source_amplitude(i, start_time) * amplitude_scale
		if amplitude <= 0.0:
			continue
		var copy := _copy_wave(wave, wave.speed_scale * time_scale)
		copy.amplitude = 0.0
		copies.append(copy)
		starts.append(amplitude)
		speeds.append(copy.speed_scale)
	# Target waves match only waves of this set, never each other.
	var from_count := copies.size()
	var matched := PackedByteArray()
	matched.resize(from_count)
	if target != null:
		# Speeds are kept in this set's gravity.
		var speed_factor := target.time_scale * sqrt(target.gravity / gravity)
		for wave in target.waves:
			if wave == null or wave.amplitude <= 0.0:
				continue
			var amplitude := wave.amplitude * target.amplitude_scale
			var speed := wave.speed_scale * speed_factor
			var found := -1
			for j in from_count:
				var other := copies[j]
				if matched[j] == 0 and is_equal_approx(other.direction_degrees, wave.direction_degrees) \
						and is_equal_approx(other.wavelength, wave.wavelength) \
						and is_equal_approx(other.sharpness, wave.sharpness) \
						and is_equal_approx(other.phase_degrees, wave.phase_degrees) \
						and is_equal_approx(speeds[j], speed):
					found = j
					break
			if found >= 0:
				matched[found] = 1
				copies[found].amplitude = amplitude
			else:
				var copy := _copy_wave(wave, speed)
				copy.amplitude = amplitude
				copies.append(copy)
				starts.append(0.0)
	if copies.size() > MAX_WAVES:
		push_warning("A wave change needs %d waves, more than the %d the shader takes; the ones past %d are left out. Use presets that share waves or have fewer of them." \
				% [copies.size(), MAX_WAVES, MAX_WAVES])
	var result := WaveSet.new()
	result.gravity = gravity
	result.waves = copies
	result._start_amplitudes = starts
	result._change_start = start_time
	result._change_duration = maxf(duration, 0.0)
	result._on_wave_changed()
	return result


## True while this set is changing (see [method changing_to]), until
## [method finish_change].
func is_changing() -> bool:
	return _change_duration >= 0.0


## The wave time the change ends at, or -INF when there is none.
func change_end() -> float:
	return _change_start + _change_duration if is_changing() else -INF


## How far the change has gone at wave time [param t], from 0 (this set's start) to 1
## (the target). It eases in and out, so the waves start and stop changing gently.
## 1 when there is no change.
func change_weight(t: float) -> float:
	if not is_changing():
		return 1.0
	if t <= _change_start:
		return 0.0
	if _change_duration <= 0.0 or t >= _change_start + _change_duration:
		return 1.0
	return smoothstep(0.0, 1.0, (t - _change_start) / _change_duration)


## Ends the change: the waves stay at the target's amplitudes, and those that faded out
## are dropped, so they cost nothing. Call it once no query comes before
## [method change_end]; it changes no height at or after that time.
func finish_change() -> void:
	if not is_changing():
		return
	_start_amplitudes = PackedFloat64Array()
	_change_duration = -1.0
	_on_wave_changed()


## Number of waves in use (at most [constant MAX_WAVES]).
func wave_count() -> int:
	_ensure_packed()
	return _count


## The largest the crests can fold: the sum of k * horizontal amplitude over all waves.
## The surface folds over itself, and the CPU solve fails, only where this reaches 1, so
## keep it below about 0.9. During a change it is the larger of the start's and the end's.
func max_fold() -> float:
	_ensure_packed()
	if not is_changing():
		var total := 0.0
		for i in _count:
			total += _packed[i * STRIDE + 2] * _packed[i * STRIDE + 5]
		return total
	var start := 0.0
	var end := 0.0
	for i in _count:
		start += _packed[i * STRIDE + 2] * _ends[i * 4 + 1]
		end += _packed[i * STRIDE + 2] * _ends[i * 4 + 3]
	return maxf(start, end)


## The highest the surface can rise above its rest level: the sum of the amplitudes.
## During a change, the sum of each wave's larger amplitude.
func max_height() -> float:
	_ensure_packed()
	if not is_changing():
		return max_height_at(0.0)
	var total := 0.0
	for i in _count:
		total += maxf(_ends[i * 4], _ends[i * 4 + 2])
	return total


## The highest the surface can rise above its rest level at wave time [param t].
func max_height_at(t: float) -> float:
	_ensure_amplitudes(t)
	var total := 0.0
	for i in _count:
		total += _packed[i * STRIDE + 4]
	return total


## Where the surface point that rests at (x, z) is at time t. The y value is relative to
## the rest level of the water.
func surface_point(x: float, z: float, t: float) -> Vector3:
	_ensure_amplitudes(t)
	var px := x
	var py := 0.0
	var pz := z
	for i in _count:
		var o := i * STRIDE
		var dx := _packed[o]
		var dz := _packed[o + 1]
		var f := _packed[o + 2] * (dx * x + dz * z) - _packed[o + 3] * t + _packed[o + 6]
		var c := cos(f)
		px += dx * _packed[o + 5] * c
		pz += dz * _packed[o + 5] * c
		py += _packed[o + 4] * sin(f)
	return Vector3(px, py, pz)


## The rest position whose displaced surface point lies above world position (x, z).
func find_rest_position(x: float, z: float, t: float) -> Vector2:
	_ensure_amplitudes(t)
	var px := x
	var pz := z
	for iteration in SOLVE_ITERATIONS:
		# Displacement d(p) and the Jacobian J of p + d(p).
		var ox := 0.0
		var oz := 0.0
		var jxx := 1.0
		var jxz := 0.0
		var jzz := 1.0
		for i in _count:
			var o := i * STRIDE
			var dx := _packed[o]
			var dz := _packed[o + 1]
			var k := _packed[o + 2]
			var horizontal := _packed[o + 5]
			var f := k * (dx * px + dz * pz) - _packed[o + 3] * t + _packed[o + 6]
			var c := cos(f)
			var ks := k * horizontal * sin(f)
			ox += dx * horizontal * c
			oz += dz * horizontal * c
			jxx -= dx * dx * ks
			jxz -= dx * dz * ks
			jzz -= dz * dz * ks
		var ex := px + ox - x
		var ez := pz + oz - z
		if absf(ex) + absf(ez) < 1e-7:
			break
		var det := jxx * jzz - jxz * jxz
		if det < 1e-4:
			# Folded crest: fall back to a plain fixed-point step.
			px -= ex
			pz -= ez
			continue
		px -= (jzz * ex - jxz * ez) / det
		pz -= (jxx * ez - jxz * ex) / det
	return Vector2(px, pz)


## Height of the surface above world position (x, z) at time t, relative to the rest level.
func height_at(x: float, z: float, t: float) -> float:
	var rest := find_rest_position(x, z, t)
	var height := 0.0
	for i in _count:
		var o := i * STRIDE
		var f := _packed[o + 2] * (_packed[o] * rest.x + _packed[o + 1] * rest.y) \
				- _packed[o + 3] * t + _packed[o + 6]
		height += _packed[o + 4] * sin(f)
	return height


## Height, normal, water velocity and fold of the surface above world position (x, z) at
## time t. The height is relative to the rest level. Pass [param out] to reuse an object.
## While the set changes, the velocity leaves out how fast the amplitudes change, which is
## tiny next to the waves' own motion.
func sample(x: float, z: float, t: float, out: WaterSample = null) -> WaterSample:
	if out == null:
		out = WaterSample.new()
	var rest := find_rest_position(x, z, t)
	var height := 0.0
	# Partial derivatives of the surface point with respect to the rest position.
	var tx := Vector3(1.0, 0.0, 0.0)
	var tz := Vector3(0.0, 0.0, 1.0)
	var velocity := Vector3.ZERO
	for i in _count:
		var o := i * STRIDE
		var dx := _packed[o]
		var dz := _packed[o + 1]
		var k := _packed[o + 2]
		var omega := _packed[o + 3]
		var amplitude := _packed[o + 4]
		var horizontal := _packed[o + 5]
		var f := k * (dx * rest.x + dz * rest.y) - omega * t + _packed[o + 6]
		var s := sin(f)
		var c := cos(f)
		height += amplitude * s
		var ks := k * horizontal * s
		var kc := k * amplitude * c
		tx += Vector3(-dx * dx * ks, dx * kc, -dx * dz * ks)
		tz += Vector3(-dx * dz * ks, dz * kc, -dz * dz * ks)
		velocity += Vector3(dx * horizontal * omega * s, -amplitude * omega * c, dz * horizontal * omega * s)
	out.height = height
	out.normal = tz.cross(tx).normalized()
	out.velocity = velocity
	out.fold = tx.x * tz.z - tz.x * tx.z
	return out


## Per-wave constants for the shader, as two arrays of [constant MAX_WAVES] items:
## [code]wave_dir_k[/code] (dir.x, dir.z, k, wavelength) and [code]wave_shape[/code]
## (amplitude, horizontal amplitude, 0, 0). While the set changes, the amplitudes are those
## of the last time asked for: send [method get_shader_wave_shapes] every frame.
func get_shader_wave_data() -> Dictionary:
	_ensure_packed()
	var dir_k := PackedVector4Array()
	dir_k.resize(MAX_WAVES)
	for i in _count:
		var o := i * STRIDE
		dir_k[i] = Vector4(_packed[o], _packed[o + 1], _packed[o + 2], _packed[o + 7])
	return {"count": _count, "wave_dir_k": dir_k, "wave_shape": _shapes()}


## The [code]wave_shape[/code] uniform at wave time [param t]: it changes only while the
## set changes.
func get_shader_wave_shapes(t: float) -> PackedVector4Array:
	_ensure_amplitudes(t)
	return _shapes()


## Each wave's phase at time t, wrapped to [0, TAU), for the shader. Computing the phase
## here in double precision keeps the shader's 32-bit floats accurate however long the
## game runs.
func get_shader_wave_phases(t: float) -> PackedFloat32Array:
	_ensure_packed()
	var phases := PackedFloat32Array()
	phases.resize(MAX_WAVES)
	for i in _count:
		var o := i * STRIDE
		phases[i] = fposmod(_packed[o + 6] - _packed[o + 3] * t, TAU)
	return phases


func _shapes() -> PackedVector4Array:
	var shape := PackedVector4Array()
	shape.resize(MAX_WAVES)
	for i in _count:
		var o := i * STRIDE
		shape[i] = Vector4(_packed[o + 4], _packed[o + 5], 0.0, 0.0)
	return shape


# The amplitude, before amplitude_scale, of waves[index] at wave time t.
func _source_amplitude(index: int, t: float) -> float:
	var end := waves[index].amplitude
	if not is_changing():
		return end
	return lerpf(_start_amplitudes[index], end, change_weight(t))


# A copy of a wave with its speed set to speed (time_scale already applied).
static func _copy_wave(wave: GerstnerWave, speed: float) -> GerstnerWave:
	var copy := GerstnerWave.new(wave.direction_degrees, wave.wavelength, wave.amplitude,
			wave.sharpness, wave.phase_degrees)
	copy.speed_scale = speed
	return copy


# Packs the waves and writes their amplitudes at wave time t into _packed.
func _ensure_amplitudes(t: float) -> void:
	_ensure_packed()
	if not is_changing():
		return
	var weight := change_weight(t)
	if weight == _packed_weight:
		return
	_packed_weight = weight
	for i in _count:
		var o := i * STRIDE
		var e := i * 4
		_packed[o + 4] = lerpf(_ends[e], _ends[e + 2], weight)
		_packed[o + 5] = lerpf(_ends[e + 1], _ends[e + 3], weight)


func _ensure_packed() -> void:
	if not _dirty:
		return
	_dirty = false
	_packed_weight = NAN
	var changing := is_changing()
	var used: Array[GerstnerWave] = []
	var starts := PackedFloat64Array()
	for i in waves.size():
		var wave := waves[i]
		if wave == null:
			continue
		var start := _start_amplitudes[i] if changing else 0.0
		if wave.amplitude > 0.0 or start > 0.0:
			used.append(wave)
			starts.append(start)
	if used.size() > MAX_WAVES and not changing:
		push_warning("WaveSet has %d waves; the shader uses the first %d." % [used.size(), MAX_WAVES])
	_count = mini(used.size(), MAX_WAVES)
	_packed.resize(_count * STRIDE)
	_ends.resize(_count * 4)
	for i in _count:
		var wave := used[i]
		var o := i * STRIDE
		var angle := deg_to_rad(wave.direction_degrees)
		var k := TAU / wave.wavelength
		var amplitude := wave.amplitude * amplitude_scale
		_packed[o] = cos(angle)
		_packed[o + 1] = sin(angle)
		_packed[o + 2] = k
		_packed[o + 3] = sqrt(gravity * k) * wave.speed_scale * time_scale
		_packed[o + 4] = amplitude
		_packed[o + 5] = amplitude * wave.sharpness
		_packed[o + 6] = deg_to_rad(wave.phase_degrees)
		_packed[o + 7] = wave.wavelength
		var start := starts[i] * amplitude_scale
		_ends[i * 4] = start
		_ends[i * 4 + 1] = start * wave.sharpness
		_ends[i * 4 + 2] = amplitude
		_ends[i * 4 + 3] = amplitude * wave.sharpness


func _on_wave_changed() -> void:
	_dirty = true
	emit_changed()
