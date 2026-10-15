extends RefCounted
## Checks a change of waves made with [method WaveSet.changing_to] on the CPU: the
## surface starts as the first set and ends as the second, moves only a little from one
## physics tick to the next, gives the same heights whatever was asked before, and leaves
## both presets as they were. Run from gdh:
## [code]gdh live eval "load('res://test/wave_change_check.gd').new().run()"[/code]
## Every value in the result whose key ends in "_ok" must be true; [method failures] lists
## the ones that are not.

const FROM := "res://water/presets/open_sea.tres"
const TO := "res://water/presets/rolling_swell.tres"
const START := 5.0
const DURATION := 4.0


## The names of the checks in [method run] that failed.
func failures() -> PackedStringArray:
	var failed := PackedStringArray()
	var result := run()
	for key: String in result:
		if key.ends_with("_ok") and not result[key]:
			failed.append(key)
	return failed


func run() -> Dictionary:
	var from: WaveSet = load(FROM)
	var to: WaveSet = load(TO)
	var from_before := _snapshot(from)
	var to_before := _snapshot(to)
	var change := from.changing_to(to, START, DURATION)
	var points := _points()

	# Before the start it is the first set, after the end the second.
	var start_error := maxf(_largest_difference(change, from, points, START - 1.0), _largest_difference(change, from, points, START))
	var end_error := maxf(_largest_difference(change, to, points, START + DURATION), _largest_difference(change, to, points, START + DURATION + 3.0))

	# The largest height change between two physics ticks, through the whole change, against
	# the same without a change (the waves' own motion).
	var tick := 1.0 / 60.0
	var largest_step := 0.0
	var t := START - 0.5
	var before := _heights(change, points, t)
	while t < START + DURATION + 0.5:
		t += tick
		var heights := _heights(change, points, t)
		for i in heights.size():
			largest_step = maxf(largest_step, absf(heights[i] - before[i]))
		before = heights
	var own_step := 0.0
	for s in [from, to]:
		var set: WaveSet = s
		var a := _heights(set, points, START)
		var b := _heights(set, points, START + tick)
		for i in a.size():
			own_step = maxf(own_step, absf(b[i] - a[i]))

	# The same time gives the same heights, whatever was asked before.
	var middle := START + DURATION * 0.37
	var first := _heights(change, points, middle)
	_heights(change, points, START + DURATION * 0.9)
	var fresh := from.changing_to(to, START, DURATION)
	var again := _heights(fresh, points, middle)
	var repeat_error := 0.0
	for i in first.size():
		repeat_error = maxf(repeat_error, absf(first[i] - again[i]))
	repeat_error = maxf(repeat_error, absf(first[0] - _heights(change, points, middle)[0]))

	# Ending the change drops the faded waves without moving the surface.
	var waves_during := change.wave_count()
	change.finish_change()
	var finish_error := _largest_difference(change, to, points, START + DURATION + 1.0)

	# A set that shares waves with the target changes them in place.
	var half := to.duplicate(true) as WaveSet
	half.amplitude_scale = to.amplitude_scale * 0.5
	var shared := half.changing_to(to, 0.0, 1.0)
	var shared_error := maxf(_largest_difference(shared, half, points, 0.0), _largest_difference(shared, to, points, 1.0))

	# Too many waves: the change warns and keeps the first MAX_WAVES (this warning is
	# expected in the output).
	var many := WaveSet.new()
	var extra: Array[GerstnerWave] = []
	for i in 9:
		extra.append(GerstnerWave.new(i * 40.0, 5.0 + i, 0.02))
	many.waves = extra
	var capped := from.changing_to(many, 0.0, 1.0)

	return {
		"capped_waves": capped.wave_count(),
		"capped_ok": capped.wave_count() == WaveSet.MAX_WAVES,
		"start_error_m": start_error,
		"start_ok": start_error < 1e-9,
		"end_error_m": end_error,
		"end_ok": end_error < 1e-9,
		"largest_tick_step_m": largest_step,
		"waves_own_tick_step_m": own_step,
		"smooth_ok": largest_step < own_step * 1.1,
		"repeat_error_m": repeat_error,
		"repeat_ok": repeat_error == 0.0,
		"waves_during": waves_during,
		"waves_during_ok": waves_during == from.wave_count() + to.wave_count(),
		"waves_after": change.wave_count(),
		"finish_ok": finish_error < 1e-9 and change.wave_count() == to.wave_count() and not change.is_changing(),
		"shared_waves": shared.wave_count(),
		"shared_ok": shared.wave_count() == to.wave_count() and shared_error < 1e-9,
		"presets_unchanged_ok": _snapshot(from) == from_before and _snapshot(to) == to_before,
	}


func _points() -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var points := PackedVector2Array()
	for i in 200:
		points.append(Vector2(rng.randf_range(-150.0, 150.0), rng.randf_range(-150.0, 150.0)))
	return points


func _heights(waves: WaveSet, points: PackedVector2Array, t: float) -> PackedFloat64Array:
	var heights := PackedFloat64Array()
	for p in points:
		heights.append(waves.height_at(p.x, p.y, t))
	return heights


func _largest_difference(a: WaveSet, b: WaveSet, points: PackedVector2Array, t: float) -> float:
	var largest := 0.0
	var ha := _heights(a, points, t)
	var hb := _heights(b, points, t)
	for i in ha.size():
		largest = maxf(largest, absf(ha[i] - hb[i]))
	return largest


# Everything about a preset that a change could alter.
func _snapshot(waves: WaveSet) -> Array:
	var values := [waves.amplitude_scale, waves.time_scale, waves.gravity, waves.waves.size()]
	for wave in waves.waves:
		values.append_array([wave.direction_degrees, wave.wavelength, wave.amplitude, wave.sharpness,
				wave.phase_degrees, wave.speed_scale])
	return values
