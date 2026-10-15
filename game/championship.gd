class_name Championship
extends RefCounted
## A championship: one race on each course in turn, points for each place, standings after
## every race. The rider with the most points after the last race wins; on equal points,
## the better place in the last race decides. Each race's weather is drawn from its course's
## weathers and the championship's seed as the championship starts, so the player sees each
## forecast before the race, and the same seed gives the same forecasts.

## Points for 1st, 2nd, 3rd and 4th. A disqualified rider scores nothing.
const POINTS: Array[int] = [10, 6, 3, 1]

var player: RiderProfile
var riders: Array[RiderProfile] = []
var courses: Array[CourseInfo] = []
## The cup raced, or null: its name, laps and the computer riders' skill offset.
var cup: CupInfo
## Index of the race to run next (or just run, before [method record] moves it on).
var race_index: int = 0
## Points per rider, by display name.
var points: Dictionary[String, int] = {}
## Each race's result: an array of display names in finishing order, and those disqualified.
var results: Array[Dictionary] = []
## The seed the forecasts are drawn from.
var weather_seed: int = 0
## Laps per race, for the forecasts: the cup's, or 3.
var laps: int = 3
## Each race's weather, one per course.
var forecasts: Array[Forecast] = []


func _init(p_player: RiderProfile, p_riders: Array[RiderProfile], p_courses: Array[CourseInfo],
		p_cup: CupInfo = null, p_weather_seed: int = 0) -> void:
	player = p_player
	riders = p_riders.duplicate()
	courses = p_courses.duplicate()
	cup = p_cup
	for rider in riders:
		points[rider.display_name] = 0
	weather_seed = p_weather_seed
	laps = cup.laps if cup != null and cup.laps > 0 else 3
	forecasts = draw_forecasts(courses, weather_seed, laps)


## A forecast for each of [param race_courses], drawn from its weathers
## ([method Game.weathers_for]) and [param draw_seed]: the same arguments give the same
## forecasts.
static func draw_forecasts(race_courses: Array[CourseInfo], draw_seed: int, race_laps: int) -> Array[Forecast]:
	var drawn: Array[Forecast] = []
	for i in race_courses.size():
		drawn.append(Forecast.pick(Game.weathers_for(race_courses[i]), hash([draw_seed, i]), race_laps))
	return drawn


func current_course() -> CourseInfo:
	return courses[mini(race_index, courses.size() - 1)]


## The weather of the race to run next (or just run).
func current_forecast() -> Forecast:
	return forecasts[mini(race_index, forecasts.size() - 1)] if not forecasts.is_empty() else null


## True once a race has been run, so a craft chosen now is for the next race.
func is_under_way() -> bool:
	return race_index > 0 and not is_over()


func is_over() -> bool:
	return race_index >= courses.size()


## Records a race's finishing order ([param order], display names, first to last) and who
## was disqualified, adds the points, and moves on to the next race. Returns the points each
## rider scored in it.
func record(order: Array[String], disqualified: Array[String]) -> Dictionary[String, int]:
	var scored: Dictionary[String, int] = {}
	var place := 0
	for name in order:
		var award := 0
		if not disqualified.has(name):
			award = POINTS[place] if place < POINTS.size() else 0
			place += 1
		scored[name] = award
		points[name] = points.get(name, 0) + award
	results.append({"order": order, "disqualified": disqualified, "points": scored})
	race_index += 1
	return scored


## Display names sorted by points, most first. Ties go to the better place in the latest race.
func standings() -> Array[String]:
	var names: Array[String] = []
	for rider in riders:
		names.append(rider.display_name)
	var last: Array = results.back()["order"] if not results.is_empty() else []
	names.sort_custom(func(a: String, b: String) -> bool:
		if points[a] != points[b]:
			return points[a] > points[b]
		return last.find(a) < last.find(b))
	return names
