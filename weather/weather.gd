class_name Weather
extends CourseConditions
## The weather to race in: the waves, the sky and light, the fog, the water's colour, rain
## and wind.
##
## Most fields change the course's own conditions instead of replacing them, so one weather
## works on every course, by day or by night: a storm makes Gull Cove's waves higher and
## Lantern Harbor's night darker. A field at its default changes nothing. The fields
## [Weather] has from [CourseConditions] replace the course's values, as they do there.
##
## [RaceWeather] puts a weather on a course and changes it into another during a race;
## [Forecast] says which weather a race starts in and which it changes to.
## [method CourseConditions.apply_to] sets only the waves and the fields from
## [CourseConditions]: the sky, light, fog, water colour, rain and wind need a [RaceWeather].

## Where the weather comes in the menus: lower first.
@export var order: int = 0
## Short name used on the command line (`-- --weather storm`) and in save files.
@export var id: String = ""
## The name the menus show.
@export var display_name: String = ""
## What the announcer says when the race changes into this weather.
@export var announcement: String = ""

@export_group("Waves")
## Multiplies the height of the course's waves when [member CourseConditions.wave_set] is
## empty. The waves keep their lengths and directions, so a change into this weather only
## makes them grow or shrink. Above 1 they grow no higher than the course's ramps take
## ([method Course.wave_height_limit]).
@export_range(0.0, 2.0, 0.01) var wave_scale: float = 1.0

@export_group("Sky")
## Share of the sky's colour taken out, from 0 (the course's sky) to 1 (grey at the same
## brightness). It also greys the fog, so the horizon stays one colour.
@export_range(0.0, 1.0, 0.01) var sky_grey: float = 0.0
## Multiplies the brightness of the sky, its clouds and the fog.
@export_range(0.0, 2.0, 0.01) var sky_brightness: float = 1.0
## The sky shader's cloud_coverage: lower values cover more of the sky. Negative keeps the
## course's.
@export_range(-1.0, 1.0, 0.01) var cloud_coverage: float = -1.0
## Multiplies the sun's (or moon's) disc and halo in the sky: 0 hides them behind cloud.
@export_range(0.0, 1.0, 0.01) var sun_disc: float = 1.0

@export_group("Light")
## Multiplies the sun's (or moon's) light energy.
@export_range(0.0, 2.0, 0.01) var sun_energy: float = 1.0
## Multiplies the ambient light energy.
@export_range(0.0, 2.0, 0.01) var ambient_energy: float = 1.0

@export_group("Fog")
## The fog's density (exponential fog). Negative keeps the course's.
@export_range(-0.001, 0.05, 0.0001) var fog_density: float = -1.0
## How much the fog hides the sky, 0 to 1. Negative keeps the course's.
@export_range(-1.0, 1.0, 0.01) var fog_sky_affect: float = -1.0
## How much of the fog's colour comes from the sky behind it, 0 to 1. Thick fog wants 0,
## or the clouds show through it. Negative keeps the course's.
@export_range(-1.0, 1.0, 0.01) var fog_aerial_perspective: float = -1.0

@export_group("Water")
## Share of the water's colour taken out (deep, shallow and crest colours), 0 to 1.
@export_range(0.0, 1.0, 0.01) var water_grey: float = 0.0
## Multiplies the brightness of the water's colours.
@export_range(0.0, 2.0, 0.01) var water_brightness: float = 1.0

@export_group("Rain and wind")
## How hard it rains, from 0 (dry) to 1 (a downpour).
@export_range(0.0, 1.0, 0.01) var rain: float = 0.0
## Where the wind blows toward, in degrees, as for a wave ([member GerstnerWave.direction_degrees]):
## 0 toward +X, 90 toward +Z.
@export_range(0.0, 360.0, 0.1, "degrees") var wind_direction: float = 0.0
## The wind's speed. Spray and rain drift with it.
@export_range(0.0, 30.0, 0.1, "suffix:m/s") var wind_speed: float = 0.0


## The wind as a horizontal velocity, in m/s.
func wind() -> Vector3:
	var angle := deg_to_rad(wind_direction)
	return Vector3(cos(angle), 0.0, sin(angle)) * wind_speed


## The waves of this weather on a course whose own waves are [param course_waves]:
## [member CourseConditions.wave_set] when set, else [param course_waves] at
## [member wave_scale] times their height, but grown no higher than [param height_limit]
## (see [method Course.wave_height_limit]). The scaled set is a new resource; call it once
## per race and keep the result, since the race tells waves apart by identity.
func waves_on(course_waves: WaveSet, height_limit: float = INF) -> WaveSet:
	if wave_set != null:
		return wave_set
	var scale := scale_on(course_waves, height_limit)
	if course_waves == null or is_equal_approx(scale, 1.0):
		return course_waves
	var scaled := course_waves.duplicate() as WaveSet
	scaled.amplitude_scale = course_waves.amplitude_scale * scale
	return scaled


## What [method waves_on] multiplies the height of [param course_waves] by: [member wave_scale],
## or less when that would make them higher than [param height_limit], but never below 1
## because of the limit.
func scale_on(course_waves: WaveSet, height_limit: float = INF) -> float:
	if wave_scale <= 1.0 or course_waves == null:
		return wave_scale
	var height := course_waves.max_height()
	if height <= 0.0:
		return wave_scale
	return clampf(height_limit / height, 1.0, wave_scale)


## Sets the fields from [CourseConditions], and the waves scaled by [member wave_scale]
## when [member CourseConditions.wave_set] is empty. The rest of the weather needs a
## [RaceWeather].
func apply_to(course: Course) -> void:
	super.apply_to(course)
	if wave_set == null and not is_equal_approx(wave_scale, 1.0):
		var surface := _find(course, func(node: Node) -> bool: return node is OceanSurface) as OceanSurface
		if surface != null:
			surface.wave_set = waves_on(surface.wave_set, course.wave_height_limit())
