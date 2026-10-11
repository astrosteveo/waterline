extends Node
## The game's state between scenes (autoload `Game`): the riders and courses, what the
## player chose, the mode being played, the championship under way, the saved records, and
## the scene changes between menus and races.
##
## The flow: main menu -> rider select -> course select (or, in a championship, the next
## course) -> race -> results -> back. Each scene asks Game where to go next, so the scenes
## don't know about each other.

enum Mode {
	## One race against the three other riders.
	QUICK_RACE,
	## A race on each course in turn, with points for places.
	CHAMPIONSHIP,
	## Alone against the clock and the best run's ghost.
	TIME_TRIAL,
	## One lap scored on rings and stunts.
	STUNT,
}

const MAIN_MENU := "res://menus/main_menu.tscn"
const RIDER_SELECT := "res://menus/rider_select.tscn"
const COURSE_SELECT := "res://menus/course_select.tscn"
const RACE := "res://race/race.tscn"
const STANDINGS := "res://menus/standings.tscn"

## Every rider, in the order the rider select screen shows them.
var riders: Array[RiderProfile] = [
	preload("res://riders/marina.tres"),
	preload("res://riders/koa.tres"),
	preload("res://riders/ines.tres"),
	preload("res://riders/dax.tres"),
]
## Every course, in the order the menus list them (and a championship runs them).
var courses: Array[CourseInfo] = [
	preload("res://levels/gull_cove.course.tres"),
	preload("res://levels/whitecap_point.course.tres"),
	preload("res://levels/lantern_harbor.course.tres"),
	preload("res://levels/ebb_reef.course.tres"),
]
## The mode being played.
var mode: Mode = Mode.QUICK_RACE
## True once the player has picked a mode from the main menu, so the menu can refocus it.
var mode_chosen: bool = false
## The rider the player chose, or null to use the race scene's own.
var player_rider: RiderProfile
## The course for the next race, or null to use the race scene's own.
var course: CourseInfo
## The championship under way, or null.
var championship: Championship
## Best times, scores and ghosts.
var records := Records.new()


func _ready() -> void:
	# `-- --mode time_trial` (or stunt, championship, quick_race) starts a race scene in
	# that mode, for tests.
	var named := arg_value("--mode")
	if named != "":
		var index := Mode.keys().find(named.to_upper())
		if index >= 0:
			mode = index as Mode


func _exit_tree() -> void:
	# Static variables outlive the scene tree; drop what they hold so nothing is reported as
	# leaked when the game quits.
	MenuStyle.release()
	SoundBank.release()


## The rider called [param display_name] (any case), or null.
func rider_named(display_name: String) -> RiderProfile:
	for rider in riders:
		if rider.display_name.to_lower() == display_name.to_lower():
			return rider
	return null


## The course with [param id], or null.
func course_named(id: String) -> CourseInfo:
	for info in courses:
		if info.id == id:
			return info
	return null


## Every rider but [param player], to race against them.
func opponents_for(player: RiderProfile) -> Array[RiderProfile]:
	var others: Array[RiderProfile] = []
	for rider in riders:
		if rider != player:
			others.append(rider)
	return others


## True in the modes where the player rides alone.
func is_solo() -> bool:
	return mode == Mode.TIME_TRIAL or mode == Mode.STUNT


## The name of [member mode] for menus.
func mode_name() -> String:
	return ["QUICK RACE", "CHAMPIONSHIP", "TIME TRIAL", "STUNT MODE"][mode]


# --- Scene flow ----------------------------------------------------------------------

## Starts [param new_mode]: the rider select screen comes first.
func start_mode(new_mode: Mode) -> void:
	mode = new_mode
	mode_chosen = true
	championship = null
	_change(RIDER_SELECT)


## The rider select screen chose [param rider].
func rider_chosen(rider: RiderProfile) -> void:
	player_rider = rider
	if mode == Mode.CHAMPIONSHIP:
		championship = Championship.new(rider, riders, courses)
		course = championship.current_course()
		_change(RACE)
	else:
		_change(COURSE_SELECT)


## The course select screen chose [param info].
func course_chosen(info: CourseInfo) -> void:
	course = info
	_change(RACE)


## After a championship race: the standings.
func goto_standings() -> void:
	_change(STANDINGS)


## From the standings: the next championship race.
func next_championship_race() -> void:
	if championship == null or championship.is_over():
		goto_main_menu()
		return
	course = championship.current_course()
	_change(RACE)


func goto_rider_select() -> void:
	_change(RIDER_SELECT)


func goto_course_select() -> void:
	_change(COURSE_SELECT)


func goto_main_menu() -> void:
	championship = null
	_change(MAIN_MENU)


func _change(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(path)


## The value after [param flag] on the command line (`-- --rider koa`), or "".
static func arg_value(flag: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(flag)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else ""
