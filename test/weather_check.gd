extends Node
## Checks the weather data and [RaceWeather] on real course scenes: the weathers found in
## res://weather/, [method Forecast.pick] repeating for a seed, the laps a forecast's
## weathers cover, waves scaled from the course's own, the light, fog, sky, water, rain and
## wind a weather sets on a day course and a night course, a change back to the course's own
## values, and the shared files left unchanged. Run it with gdh
## (test/scenarios/weather.scenario.json): step until [member done], then check that
## [member failures] is empty.

const GULL_COVE := "res://levels/gull_cove.tscn"
const LANTERN_HARBOR := "res://levels/lantern_harbor.tscn"
const COVE_CALM := "res://water/presets/cove_calm.tres"
const DAY := "res://environment/day_environment.tres"
const WATER := "res://water/ocean_material.tres"

## True once every check has run.
var done: bool = false
## Each check that failed, as a line of text.
var failures: PackedStringArray = PackedStringArray()
## The names of the checks that ran.
var checks: PackedStringArray = PackedStringArray()

var _course: Course
var _weather: RaceWeather


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var storm := Game.weather_named("storm")
	var clear := Game.weather_named("clear")
	var fog := Game.weather_named("fog")

	# The weathers in res://weather/.
	_check("weathers found in menu order", Game.weathers.map(func(w: Weather) -> String: return w.id),
			["clear", "overcast", "storm", "fog"])
	_check("weather by id, any case", Game.weather_named("STORM") == storm, true)

	# Forecasts from a seed.
	var picks := []
	var repeats := true
	var laps_in_range := true
	var changes := 0
	var changes_to_same := 0
	for draw_seed in 40:
		var forecast := Forecast.pick(Game.weathers, draw_seed, 3)
		var again := Forecast.pick(Game.weathers, draw_seed, 3)
		repeats = repeats and forecast.start == again.start and forecast.later == again.later \
				and forecast.change_lap == again.change_lap
		picks.append(forecast.start.id)
		if forecast.later != null:
			changes += 1
			changes_to_same += 1 if forecast.later == forecast.start else 0
			laps_in_range = laps_in_range and forecast.change_lap >= 2 and forecast.change_lap <= 3
	_check("the same seed gives the same forecast", repeats, true)
	_check("every weather is drawn over 40 seeds", ["clear", "overcast", "storm", "fog"].all(func(id: String) -> bool: return id in picks), true)
	_check("some forecasts change, never into the same weather", [changes > 5, changes < 35, changes_to_same], [true, true, 0])
	_check("a change comes on lap 2 or 3 of 3", laps_in_range, true)
	_check("no weathers: an empty forecast", Forecast.pick([] as Array[Weather], 1, 3).is_empty(), true)

	# The laps a forecast's weathers cover.
	var turn := Forecast.new(clear, storm, 3)
	_check("weather per lap", [turn.weather_for_lap(0, 3) == clear, turn.weather_for_lap(1, 3) == clear,
			turn.weather_for_lap(2, 3) == storm], [true, true, true])
	_check("a change past the last lap never comes", [turn.changes_in(2), turn.weather_for_lap(5, 2) == clear], [false, true])
	_check("described", [turn.describe(3), turn.describe(2), Forecast.new(storm).describe(3)],
			["CLEAR, THEN STORM ON LAP 3", "CLEAR", "STORM"])
	var typed := Race.forecast_from_text("clear,storm", "3", "12")
	_check("forecast from the command line", [typed.start == clear, typed.later == storm, typed.change_lap, typed.change_time],
			[true, true, 3, 12.0])

	# Waves scaled from the course's own.
	var calm := load(COVE_CALM) as WaveSet
	var stormy := storm.waves_on(calm)
	_check("storm waves: the course's at 1.3 times the height",
			[stormy != calm, stormy.amplitude_scale, stormy.max_height() / calm.max_height(), stormy.wave_count()],
			[true, calm.amplitude_scale * 1.3, 1.3, calm.wave_count()])
	_check("the preset is unchanged", [calm.amplitude_scale, calm.resource_path], [0.5, COVE_CALM])

	var day := load(DAY) as Environment
	var day_fog := day.fog_density
	# The water file's own value (null: it keeps the shader's default), and the values in use.
	var shared_deep: Variant = (load(WATER) as ShaderMaterial).get_shader_parameter(&"deep_color")
	var zenith: Color = RaceWeather._shader_value(day.sky.sky_material as ShaderMaterial, &"zenith_color")
	var deep: Color = RaceWeather._shader_value(load(WATER) as ShaderMaterial, &"deep_color")

	# A storm on a day course.
	_load(GULL_COVE, Forecast.new(storm))
	await get_tree().physics_frame
	var world := _course.get_node(^"WorldEnvironment") as WorldEnvironment
	var sun := _course.get_node(^"Sun") as DirectionalLight3D
	var surface := _surface()
	_check("storm: waves", [surface.wave_set == Ocean.wave_set, Ocean.wave_set.amplitude_scale], [true, 0.5 * 1.3])
	_check("storm: the course's own sky is copied", [world.environment != day, world.environment.resource_path], [true, ""])
	_check("storm: light", [sun.light_energy, world.environment.ambient_light_energy], [1.25 * 0.3, day.ambient_light_energy * 0.8])
	_check("storm: fog", [world.environment.fog_enabled, world.environment.fog_density, world.environment.fog_sky_affect],
			[true, 0.004, 0.3])
	_check("storm: grey sky", RaceWeather._shade(zenith, 0.85, 0.45),
			(world.environment.sky.sky_material as ShaderMaterial).get_shader_parameter(&"zenith_color"))
	_check("storm: no sun disc", (world.environment.sky.sky_material as ShaderMaterial).get_shader_parameter(&"sun_brightness"), 0.0)
	_check("storm: water", [surface.water_material.get_shader_parameter(&"deep_color"),
			surface.water_material.get_shader_parameter(&"ripple_strength")],
			[RaceWeather._shade(deep, 0.6, 0.6), 0.22])
	_check("storm: wind and rain", [Ocean.wind, _weather.rain != null and _weather.rain.strength == 1.0,
			_weather.rain.wind], [storm.wind(), true, storm.wind()])
	_check("storm: the wind blows toward 60 degrees", [storm.wind().x > 0.0, storm.wind().z < 0.0, storm.wind().length()],
			[true, true, 14.0])
	_check("storm: shared files untouched", [day.fog_density, RaceWeather._shader_value(day.sky.sky_material as ShaderMaterial, &"zenith_color"),
			(load(WATER) as ShaderMaterial).get_shader_parameter(&"deep_color")], [day_fog, zenith, shared_deep])

	# Back to the course's own conditions at once.
	_weather.change_to(null, 0.0)
	_check("back to the course's own", [sun.light_energy, world.environment.fog_density,
			(world.environment.sky.sky_material as ShaderMaterial).get_shader_parameter(&"zenith_color"),
			surface.water_material.get_shader_parameter(&"deep_color"), Ocean.wind, _weather.rain.strength],
			[1.25, day_fog, zenith, deep, Vector3.ZERO, 0.0])

	# A storm on a night course keeps the course's own water overrides.
	_load(LANTERN_HARBOR, Forecast.new(storm))
	await get_tree().physics_frame
	surface = _surface()
	_check("night storm: the course's water darkened", surface.water_material.get_shader_parameter(&"deep_color"),
			RaceWeather._shade(Color(0.04, 0.13, 0.28, 1), 0.6, 0.6))
	_check("night storm: the course's other water overrides stay", surface.water_material.get_shader_parameter(&"crest_strength"), 0.16)
	_check("night storm: moonlight dimmed", (_course.get_node(^"Sun") as DirectionalLight3D).light_energy, 0.7 * 0.3)

	# Fog and no rain.
	_load(GULL_COVE, Forecast.new(fog))
	await get_tree().physics_frame
	world = _course.get_node(^"WorldEnvironment") as WorldEnvironment
	_check("fog: thick, hiding the sky", [world.environment.fog_density, world.environment.fog_sky_affect,
			world.environment.fog_aerial_perspective], [0.02, 0.9, 0.0])
	_check("fog: no rain", _weather.rain == null, true)

	_clear()
	done = true
	print("weather: %s" % ("passed" if failures.is_empty() else "FAILED\n  " + "\n  ".join(failures)))


## Replaces the course under test with a new instance of [param path] in [param forecast]'s
## start weather, set up as [Race] does.
func _load(path: String, forecast: Forecast) -> void:
	_clear()
	_course = (load(path) as PackedScene).instantiate() as Course
	_weather = RaceWeather.new()
	_weather.setup(_course, forecast)
	add_child(_course)
	add_child(_weather)


func _clear() -> void:
	for node: Node in [_weather, _course]:
		if node != null:
			remove_child(node)
			node.free()
	_weather = null
	_course = null


func _surface() -> OceanSurface:
	return _course.get_node(^"OceanSurface") as OceanSurface


func _check(name: String, actual: Variant, expected: Variant) -> void:
	checks.append(name)
	if not _same(actual, expected):
		failures.append("%s: got %s, expected %s" % [name, actual, expected])


static func _same(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a) - float(b)) < 0.0001
	if a is Color and b is Color:
		return a.is_equal_approx(b)
	if a is Vector3 and b is Vector3:
		return a.is_equal_approx(b)
	return a == b
