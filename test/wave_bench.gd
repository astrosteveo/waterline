extends RefCounted
## Measures the CPU wave functions: how exactly the rest-position solve inverts the
## horizontal displacement, and how long a query takes. Run from gdh:
## [code]gdh live eval "load('res://test/wave_bench.gd').new().run()"[/code]


func run(samples: int = 2000) -> Dictionary:
	var waves := Ocean.wave_set
	var t := Ocean.time
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var worst_residual := 0.0
	var total_residual := 0.0
	for i in samples:
		var x := rng.randf_range(-200.0, 200.0)
		var z := rng.randf_range(-200.0, 200.0)
		var rest := waves.find_rest_position(x, z, t)
		var moved := waves.surface_point(rest.x, rest.y, t)
		var residual := Vector2(moved.x - x, moved.z - z).length()
		worst_residual = maxf(worst_residual, residual)
		total_residual += residual

	var start := Time.get_ticks_usec()
	for i in samples:
		waves.height_at(rng.randf_range(-200.0, 200.0), rng.randf_range(-200.0, 200.0), t)
	var height_us := float(Time.get_ticks_usec() - start) / samples

	var out := WaterSample.new()
	start = Time.get_ticks_usec()
	for i in samples:
		waves.sample(rng.randf_range(-200.0, 200.0), rng.randf_range(-200.0, 200.0), t, out)
	var sample_us := float(Time.get_ticks_usec() - start) / samples

	return {
		"waves": waves.wave_count(),
		"max_fold": waves.max_fold(),
		"max_height_m": waves.max_height(),
		"solve_residual_max_m": worst_residual,
		"solve_residual_mean_m": total_residual / samples,
		"height_at_us": height_us,
		"sample_us": sample_us,
	}
