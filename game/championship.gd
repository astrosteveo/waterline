class_name Championship
extends RefCounted
## A championship: one race on each course in turn, points for each place, standings after
## every race. The rider with the most points after the last race wins; on equal points,
## the better place in the last race decides.

## Points for 1st, 2nd, 3rd and 4th. A disqualified rider scores nothing.
const POINTS: Array[int] = [10, 6, 3, 1]

var player: RiderProfile
var riders: Array[RiderProfile] = []
var courses: Array[CourseInfo] = []
## Index of the race to run next (or just run, before [method record] moves it on).
var race_index: int = 0
## Points per rider, by display name.
var points: Dictionary[String, int] = {}
## Each race's result: an array of display names in finishing order, and those disqualified.
var results: Array[Dictionary] = []


func _init(p_player: RiderProfile, p_riders: Array[RiderProfile], p_courses: Array[CourseInfo]) -> void:
	player = p_player
	riders = p_riders.duplicate()
	courses = p_courses.duplicate()
	for rider in riders:
		points[rider.display_name] = 0


func current_course() -> CourseInfo:
	return courses[mini(race_index, courses.size() - 1)]


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
