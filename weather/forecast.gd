class_name Forecast
extends Resource
## The weather for one race: the weather it starts in and, if it changes, the weather it
## changes into, the lap that brings the change and how long the change takes.
##
## [Race] races in [member Game.forecast], or in the one `-- --weather` names. [method pick]
## draws a forecast from a list of weathers and a seed, so the same seed gives the same
## weather.

## The weather at the start. Null: the course's own conditions.
@export var start: Weather
## The weather the race changes into, or null for none.
@export var later: Weather
## The lap that brings [member later]: the change starts when the leader starts this lap
## (2 is the second lap). A lap past the race's last never comes.
@export_range(2, 9, 1) var change_lap: int = 2
## Seconds of wave time the change takes. The waves, sky, fog, light, water colour, rain
## and wind change together over this time.
@export_range(0.0, 120.0, 0.1, "suffix:s") var change_time: float = 20.0


func _init(p_start: Weather = null, p_later: Weather = null, p_change_lap: int = 2,
		p_change_time: float = 20.0) -> void:
	start = p_start
	later = p_later
	change_lap = p_change_lap
	change_time = p_change_time


## True when the race keeps the course's own conditions all the way.
func is_empty() -> bool:
	return start == null and later == null


## True when the weather changes during a race of [param laps] laps.
func changes_in(laps: int) -> bool:
	return later != null and later != start and change_lap <= laps


## The weather on lap [param lap] (0 for the first) of a race of [param laps] laps: null
## means the course's own conditions.
func weather_for_lap(lap: int, laps: int) -> Weather:
	return later if changes_in(laps) and lap + 1 >= change_lap else start


## The forecast as the menus write it: "STORM", or "CLEAR, THEN STORM ON LAP 2".
func describe(laps: int) -> String:
	var first := _name(start)
	if not changes_in(laps):
		return first
	return "%s, THEN %s ON LAP %d" % [first, _name(later), change_lap]


## A forecast drawn from [param weathers] with [param draw_seed], for a race of [param laps]
## laps: the start weather, and with a chance of [param change_chance] a change into
## another of them at a lap from 2 to [param laps]. The same arguments give the same
## forecast.
static func pick(weathers: Array[Weather], draw_seed: int, laps: int, change_chance: float = 0.5) -> Forecast:
	var forecast := Forecast.new()
	if weathers.is_empty():
		return forecast
	var rng := RandomNumberGenerator.new()
	rng.seed = draw_seed
	forecast.start = weathers[rng.randi_range(0, weathers.size() - 1)]
	var change_roll := rng.randf()
	var other_index := rng.randi_range(0, maxi(weathers.size() - 2, 0))
	var lap := rng.randi_range(2, maxi(laps, 2))
	if weathers.size() > 1 and laps >= 2 and change_roll < change_chance:
		var others := weathers.filter(func(w: Weather) -> bool: return w != forecast.start)
		forecast.later = others[mini(other_index, others.size() - 1)]
		forecast.change_lap = lap
	return forecast


static func _name(weather: Weather) -> String:
	if weather == null:
		return "AS USUAL"
	return (weather.display_name if weather.display_name != "" else weather.id).to_upper()
