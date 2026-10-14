class_name RaceWeather
extends Node
## Puts a [Forecast]'s weather on a course and changes it into the next weather during a
## race. [Race] adds it when the race has a forecast.
##
## [method setup] runs before the course enters the tree: it keeps the course's own sky,
## light, fog and water colours, then sets the start weather on top of them. The course
## keeps its look files unchanged, because the weather works on its own copies of the
## environment, the sky material and the water material.
##
## [method change_to] blends every value from the weather now to the next one over a time
## given in wave time, with the same ease in and out as [method Ocean.change_waves], so
## the waves, sky, fog, light, water colour, rain and wind change together. [Race] starts
## the waves' change itself, from [method waves_for].

## The sky shader's colours that [member Weather.sky_grey] and
## [member Weather.sky_brightness] change.
const SKY_COLOURS: Array[StringName] = [&"zenith_color", &"horizon_color", &"below_color", &"cloud_color", &"cloud_shade_color"]
## The water shader's colours that [member Weather.water_grey] and
## [member Weather.water_brightness] change.
const WATER_COLOURS: Array[StringName] = [&"deep_color", &"shallow_color", &"crest_color"]

## The forecast this race follows.
var forecast: Forecast
## The weather now, or the one the race is changing into. Null: the course's own.
var weather: Weather
## The rain around the camera, or null when no weather of the forecast rains.
var rain: Rain
## Seconds between two updates of the sky during a change. Each update redraws the sky's
## reflections, so it isn't done every frame.
var sky_update_interval: float = 0.1
## The rain's colour is the fog's times this.
var rain_brightness: float = 1.6

var _course: Course
var _surface: OceanSurface
var _sun: DirectionalLight3D
var _environment: Environment
var _sky_material: ShaderMaterial
# The course's own values, before any weather: {key: value}.
var _base: Dictionary = {}
# The values shown now, and during a change the values it started from and goes to.
var _look: Dictionary = {}
var _from: Dictionary = {}
var _to: Dictionary = {}
var _change_start := 0.0
var _change_duration := -1.0
var _sky_wait := 0.0
# Waves already made for a weather: {[weather, source waves]: waves}, so the same weather
# on the same waves is the same resource.
var _waves: Dictionary = {}


## Sets [param p_forecast]'s start weather on [param course] (not yet in the tree).
func setup(course: Course, p_forecast: Forecast) -> void:
	_course = course
	forecast = p_forecast
	_surface = CourseConditions._find(course, func(node: Node) -> bool: return node is OceanSurface) as OceanSurface
	_sun = CourseConditions._find(course, func(node: Node) -> bool: return node is DirectionalLight3D) as DirectionalLight3D
	var water_keys: Array[StringName] = WATER_COLOURS.duplicate()
	for each: Weather in [forecast.start, forecast.later]:
		if each != null:
			for key: String in each.water_overrides:
				if StringName(key) not in water_keys:
					water_keys.append(StringName(key))
	if _surface != null and _surface.water_material != null:
		for key in water_keys:
			_base["water:" + key] = _surface.shader_overrides.get(String(key),
					_shader_value(_surface.water_material, key))
	# The start weather's waves, environment and tide replace the course's.
	weather = forecast.start
	if weather != null:
		var course_waves := _surface.wave_set if _surface != null else null
		weather.apply_to(course)
		if _surface != null:
			_waves[[weather, course_waves]] = _surface.wave_set
	var world := CourseConditions._find(course, func(node: Node) -> bool: return node is WorldEnvironment) as WorldEnvironment
	if world != null and world.environment != null:
		_environment = _copy_environment(world.environment)
		world.environment = _environment
		_base["ambient_energy"] = _environment.ambient_light_energy
		_base["fog_density"] = _environment.fog_density if _environment.fog_enabled else 0.0
		_base["fog_sky_affect"] = _environment.fog_sky_affect
		_base["fog_color"] = _environment.fog_light_color
		if _environment.sky != null and _environment.sky.sky_material is ShaderMaterial:
			_sky_material = _environment.sky.sky_material as ShaderMaterial
			for key: StringName in SKY_COLOURS + ([&"cloud_coverage", &"sun_brightness", &"halo_strength"] as Array[StringName]):
				var value: Variant = _shader_value(_sky_material, key)
				if value != null:
					_base["sky:" + key] = value
	if _sun != null:
		_base["sun_energy"] = _sun.light_energy
	_base["rain"] = 0.0
	_base["wind"] = Vector3.ZERO
	for each: Weather in [forecast.start, forecast.later]:
		if each != null and each.rain > 0.0 and rain == null:
			rain = Rain.new()
			rain.name = "Rain"
			add_child(rain)
	_look = look_of(weather)
	_apply(_look, true)


func _ready() -> void:
	# The course's OceanSurface calms the wind when it enters the tree.
	_apply(_look, true)


## The waves of [param p_weather] on a course whose waves on that lap would be
## [param course_waves]. The same arguments give the same resource.
func waves_for(p_weather: Weather, course_waves: WaveSet) -> WaveSet:
	if p_weather == null:
		return course_waves
	var key := [p_weather, course_waves]
	if not _waves.has(key):
		_waves[key] = p_weather.waves_on(course_waves)
	return _waves[key]


## Starts changing into [param next] over [param duration] seconds of wave time, from the
## values shown now. Null changes back to the course's own conditions. Calling it during a
## change starts the new one from where the values are.
func change_to(next: Weather, duration: float) -> void:
	weather = next
	_from = _look.duplicate()
	_to = look_of(next)
	_change_start = Ocean.end_time
	_change_duration = maxf(duration, 0.0)
	_sky_wait = 0.0
	if duration <= 0.0:
		_finish_change()


## True while a change runs.
func is_changing() -> bool:
	return _change_duration >= 0.0


## How far the change has gone at wave time [param t], from 0 to 1, eased in and out as
## [method WaveSet.change_weight] eases the waves. 1 when there is no change.
func change_weight(t: float) -> float:
	if not is_changing():
		return 1.0
	if _change_duration <= 0.0:
		return 1.0
	return smoothstep(0.0, 1.0, (t - _change_start) / _change_duration)


## The value of [param key] shown now ("sun_energy", "fog_density", "sky:zenith_color",
## "water:deep_color", "rain", "wind" and so on), or null.
func value(key: String) -> Variant:
	return _look.get(key)


## Every value [param p_weather] sets, worked out from the course's own: what the course
## looks like in that weather. Null gives the course's own values.
func look_of(p_weather: Weather) -> Dictionary:
	var result := _base.duplicate()
	if p_weather == null:
		return result
	if result.has("sun_energy"):
		result["sun_energy"] = float(_base["sun_energy"]) * p_weather.sun_energy
	if result.has("ambient_energy"):
		result["ambient_energy"] = float(_base["ambient_energy"]) * p_weather.ambient_energy
	if result.has("fog_density") and p_weather.fog_density >= 0.0:
		result["fog_density"] = p_weather.fog_density
	if result.has("fog_sky_affect") and p_weather.fog_sky_affect >= 0.0:
		result["fog_sky_affect"] = p_weather.fog_sky_affect
	if result.has("fog_color"):
		result["fog_color"] = _shade(_base["fog_color"], p_weather.sky_grey, p_weather.sky_brightness)
	for key in SKY_COLOURS:
		if result.has("sky:" + key):
			result["sky:" + key] = _shade(_base["sky:" + key], p_weather.sky_grey, p_weather.sky_brightness)
	if result.has("sky:cloud_coverage") and p_weather.cloud_coverage >= 0.0:
		result["sky:cloud_coverage"] = p_weather.cloud_coverage
	for key: String in ["sky:sun_brightness", "sky:halo_strength"]:
		if result.has(key):
			result[key] = float(_base[key]) * p_weather.sun_disc
	for key: String in p_weather.water_overrides:
		if result.has("water:" + key):
			result["water:" + key] = p_weather.water_overrides[key]
	for key in WATER_COLOURS:
		if result.has("water:" + key):
			result["water:" + key] = _shade(result["water:" + key], p_weather.water_grey, p_weather.water_brightness)
	result["rain"] = p_weather.rain
	result["wind"] = p_weather.wind()
	return result


func _process(delta: float) -> void:
	if not is_changing():
		return
	var t := Ocean.render_time()
	var weight := change_weight(t)
	for key: String in _to:
		_look[key] = _blend(_from.get(key, _to[key]), _to[key], weight)
	if t >= _change_start + _change_duration:
		_finish_change()
		return
	_sky_wait -= delta
	var sky_due := _sky_wait <= 0.0
	if sky_due:
		_sky_wait = sky_update_interval
	_apply(_look, sky_due)


func _finish_change() -> void:
	_look = _to.duplicate()
	_change_duration = -1.0
	_apply(_look, true)


## Sets [param values] on the course's light, environment, sky, water, rain and wind.
func _apply(values: Dictionary, with_sky: bool) -> void:
	if _sun != null and values.has("sun_energy"):
		_sun.light_energy = values["sun_energy"]
	if _environment != null:
		_environment.ambient_light_energy = values.get("ambient_energy", _environment.ambient_light_energy)
		var density: float = values.get("fog_density", _environment.fog_density)
		_environment.fog_enabled = density > 0.0
		_environment.fog_density = density
		_environment.fog_sky_affect = values.get("fog_sky_affect", _environment.fog_sky_affect)
		_environment.fog_light_color = values.get("fog_color", _environment.fog_light_color)
	if _sky_material != null and with_sky:
		for key: String in values:
			if key.begins_with("sky:"):
				_sky_material.set_shader_parameter(key.substr(4), values[key])
	if _surface != null:
		var water := {}
		for key: String in values:
			if key.begins_with("water:"):
				water[key.substr(6)] = values[key]
		if not water.is_empty():
			_surface.shader_overrides = _surface.shader_overrides.merged(water, true)
	Ocean.wind = values.get("wind", Vector3.ZERO)
	if rain != null:
		rain.strength = values.get("rain", 0.0)
		rain.wind = Ocean.wind
		if values.has("fog_color"):
			var fog: Color = values["fog_color"]
			rain.colour = Color(fog.r * rain_brightness, fog.g * rain_brightness, fog.b * rain_brightness)


## [param colour] with [param grey] of its colour taken out and its brightness times
## [param brightness].
static func _shade(colour: Variant, grey: float, brightness: float) -> Color:
	var c: Color = colour if colour is Color else Color(colour.x, colour.y, colour.z)
	var luminance := c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722
	var shaded := c.lerp(Color(luminance, luminance, luminance, c.a), grey)
	return Color(shaded.r * brightness, shaded.g * brightness, shaded.b * brightness, c.a)


static func _blend(a: Variant, b: Variant, weight: float) -> Variant:
	if a is float or a is int:
		return lerpf(a, b, weight)
	if a is Color:
		return (a as Color).lerp(b, weight)
	if a is Vector3:
		return (a as Vector3).lerp(b, weight)
	return b if weight >= 0.5 else a


## The value of uniform [param key] on [param material]: its own, else the shader's default.
static func _shader_value(material: ShaderMaterial, key: StringName) -> Variant:
	var found: Variant = material.get_shader_parameter(key)
	if found == null and material.shader != null:
		found = RenderingServer.shader_get_parameter_default(material.shader.get_rid(), key)
	if found is Vector3:
		found = Color(found.x, found.y, found.z)
	return found


## A copy of [param source] with its own sky and sky material, so changing them leaves the
## file and other courses alone.
static func _copy_environment(source: Environment) -> Environment:
	var copy := source.duplicate() as Environment
	if copy.sky != null:
		copy.sky = copy.sky.duplicate() as Sky
		if copy.sky.sky_material != null:
			copy.sky.sky_material = copy.sky.sky_material.duplicate() as Material
	return copy
