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


## Number of waves in use (at most [constant MAX_WAVES]).
func wave_count() -> int:
	_ensure_packed()
	return _count


## The largest the crests can fold: the sum of k * horizontal amplitude over all waves.
## The surface folds over itself, and the CPU solve fails, only where this reaches 1, so
## keep it below about 0.9.
func max_fold() -> float:
	_ensure_packed()
	var total := 0.0
	for i in _count:
		total += _packed[i * STRIDE + 2] * _packed[i * STRIDE + 5]
	return total


## The highest the surface can rise above its rest level: the sum of the amplitudes.
func max_height() -> float:
	_ensure_packed()
	var total := 0.0
	for i in _count:
		total += _packed[i * STRIDE + 4]
	return total


## Where the surface point that rests at (x, z) is at time t. The y value is relative to
## the rest level of the water.
func surface_point(x: float, z: float, t: float) -> Vector3:
	_ensure_packed()
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
	_ensure_packed()
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
## (amplitude, horizontal amplitude, 0, 0).
func get_shader_wave_data() -> Dictionary:
	_ensure_packed()
	var dir_k := PackedVector4Array()
	var shape := PackedVector4Array()
	dir_k.resize(MAX_WAVES)
	shape.resize(MAX_WAVES)
	for i in _count:
		var o := i * STRIDE
		dir_k[i] = Vector4(_packed[o], _packed[o + 1], _packed[o + 2], _packed[o + 7])
		shape[i] = Vector4(_packed[o + 4], _packed[o + 5], 0.0, 0.0)
	return {"count": _count, "wave_dir_k": dir_k, "wave_shape": shape}


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


func _ensure_packed() -> void:
	if not _dirty:
		return
	_dirty = false
	var used: Array[GerstnerWave] = []
	for wave in waves:
		if wave != null and wave.amplitude > 0.0:
			used.append(wave)
	if used.size() > MAX_WAVES:
		push_warning("WaveSet has %d waves; the shader uses the first %d." % [used.size(), MAX_WAVES])
	_count = mini(used.size(), MAX_WAVES)
	_packed.resize(_count * STRIDE)
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


func _on_wave_changed() -> void:
	_dirty = true
	emit_changed()
