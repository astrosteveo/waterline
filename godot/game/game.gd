extends Node
## The game's state between scenes (autoload `Game`): the riders, craft and courses, what
## the player chose, the mode being played, the championship under way, the saved records, and
## the scene changes between menus and races.
##
## The flow: main menu -> rider select -> craft select -> course select (or, in a championship,
## the next course) -> race -> results -> back. Each scene asks Game where to go next, so the
## scenes don't know about each other.

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
const CRAFT_SELECT := "res://menus/craft_select.tscn"
const COURSE_SELECT := "res://menus/course_select.tscn"
const CUP_SELECT := "res://menus/cup_select.tscn"
const RACE := "res://race/race.tscn"
const STANDINGS := "res://menus/standings.tscn"

## Every rider, in the order the rider select screen shows them.
var riders: Array[RiderProfile] = [
	preload("res://riders/marina.tres"),
	preload("res://riders/koa.tres"),
	preload("res://riders/ines.tres"),
	preload("res://riders/dax.tres"),
]
## Every craft, in the order the menus list them.
var crafts: Array[CraftProfile] = [
	preload("res://craft/tradewind.tres"),
	preload("res://craft/swordfish.tres"),
	preload("res://craft/petrel.tres"),
	preload("res://craft/skipjack.tres"),
]
## Where the courses are: every `*.course.tres` in it is a course.
const COURSES_DIR := "res://levels/"

## Every course in [constant COURSES_DIR], in the order the menus list them (and a championship
## runs them): by [member CourseInfo.order], then by id.
var courses: Array[CourseInfo] = find_courses(COURSES_DIR)
## Where the championship cups are: every `*.cup.tres` in it is a cup.
const CUPS_DIR := "res://cups/"

## Every cup in [constant CUPS_DIR], in the order the cup select screen lists them: by
## [member CupInfo.order], then by id.
var cups: Array[CupInfo] = find_cups(CUPS_DIR)
## Where the weathers are: every `*.weather.tres` in it is a weather.
const WEATHERS_DIR := "res://weather/"

## Every weather in [constant WEATHERS_DIR], in the order the menus list them: by
## [member Weather.order], then by id.
var weathers: Array[Weather] = find_weathers(WEATHERS_DIR)
## The weather for the next race, or null for the course's own conditions. Time trials and
## stunt runs don't use it. `-- --weather` replaces it.
var forecast: Forecast
## The weather chosen for quick races on the course select screen, or null for a random one
## from the course's weathers.
var quick_weather: Weather
## The mode being played.
var mode: Mode = Mode.QUICK_RACE
## True once the player has picked a mode from the main menu, so the menu can refocus it.
var mode_chosen: bool = false
## The rider the player chose, or null to use the race scene's own.
var player_rider: RiderProfile
## The craft the player rides: the rider's default craft once the rider is chosen, then the
## craft chosen on the craft select screen. Null: the rider's default craft.
var player_craft: CraftProfile
## The course for the next race, or null to use the race scene's own.
var course: CourseInfo
## The cup chosen for the championship, or null.
var cup: CupInfo
## The championship under way, or null.
var championship: Championship
## Best times, scores and ghosts.
var records := Records.new()

var _quitting := false


func _ready() -> void:
	# `-- --mode time_trial` (or stunt, championship, quick_race) starts a race scene in
	# that mode, for tests.
	var named := arg_value("--mode")
	if named != "":
		var index := Mode.keys().find(named.to_upper())
		if index >= 0:
			mode = index as Mode
	# The window's close button goes through quit() too.
	get_tree().auto_accept_quit = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit()


func _exit_tree() -> void:
	# Static variables outlive the scene tree; drop what they hold so nothing is reported as
	# leaked when the game quits.
	MenuStyle.release()
	SoundBank.release()


## Every [CourseInfo] in [param dir] (its `*.course.tres` files), sorted by
## [member CourseInfo.order], then by id. [method ResourceLoader.list_directory] lists the
## original file names in exported builds too, where the files themselves are renamed.
static func find_courses(dir: String) -> Array[CourseInfo]:
	var found: Array[CourseInfo] = []
	for file in ResourceLoader.list_directory(dir):
		if not file.ends_with(".course.tres"):
			continue
		var info := load(dir.path_join(file)) as CourseInfo
		if info == null:
			push_error("%s is not a CourseInfo." % dir.path_join(file))
			continue
		found.append(info)
	found.sort_custom(func(a: CourseInfo, b: CourseInfo) -> bool:
		return a.order < b.order if a.order != b.order else a.id < b.id)
	return found


## Every [CupInfo] in [param dir] (its `*.cup.tres` files), sorted by [member CupInfo.order],
## then by id.
static func find_cups(dir: String) -> Array[CupInfo]:
	var found: Array[CupInfo] = []
	for file in ResourceLoader.list_directory(dir):
		if not file.ends_with(".cup.tres"):
			continue
		var info := load(dir.path_join(file)) as CupInfo
		if info == null:
			push_error("%s is not a CupInfo." % dir.path_join(file))
			continue
		found.append(info)
	found.sort_custom(func(a: CupInfo, b: CupInfo) -> bool:
		return a.order < b.order if a.order != b.order else a.id < b.id)
	return found


## Every [Weather] in [param dir] (its `*.weather.tres` files), sorted by
## [member Weather.order], then by id.
static func find_weathers(dir: String) -> Array[Weather]:
	var found: Array[Weather] = []
	for file in ResourceLoader.list_directory(dir):
		if not file.ends_with(".weather.tres"):
			continue
		var weather := load(dir.path_join(file)) as Weather
		if weather == null:
			push_error("%s is not a Weather." % dir.path_join(file))
			continue
		found.append(weather)
	found.sort_custom(func(a: Weather, b: Weather) -> bool:
		return a.order < b.order if a.order != b.order else a.id < b.id)
	return found


## The rider called [param display_name] (any case), or null.
func rider_named(display_name: String) -> RiderProfile:
	for rider in riders:
		if rider.display_name.to_lower() == display_name.to_lower():
			return rider
	return null


## The craft with [param id] (any case), or null.
func craft_named(id: String) -> CraftProfile:
	for craft in crafts:
		if craft.id.to_lower() == id.to_lower():
			return craft
	return null


## The course with [param id], or null.
func course_named(id: String) -> CourseInfo:
	for info in courses:
		if info.id == id:
			return info
	return null


## The weathers a race on [param info] can have: its own list, or every weather.
func weathers_for(info: CourseInfo) -> Array[Weather]:
	return info.weathers if info != null and not info.weathers.is_empty() else weathers


## The weather with [param id] (any case), or null.
func weather_named(id: String) -> Weather:
	for weather in weathers:
		if weather.id.to_lower() == id.to_lower():
			return weather
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

## Starts [param new_mode]: the rider select screen comes first, or in a championship the cup
## select.
func start_mode(new_mode: Mode) -> void:
	mode = new_mode
	mode_chosen = true
	championship = null
	forecast = null
	_change(CUP_SELECT if mode == Mode.CHAMPIONSHIP else RIDER_SELECT)


## The cup select screen chose [param info]: the rider select comes next. The championship
## starts here, so its forecasts are drawn and the craft select can show the first race's.
func cup_chosen(info: CupInfo) -> void:
	cup = info
	championship = Championship.new(null, riders, cup.courses, cup, randi())
	_change(RIDER_SELECT)


## The rider select screen chose [param rider]: the craft select comes next, with the rider's
## default craft focused first.
func rider_chosen(rider: RiderProfile) -> void:
	player_rider = rider
	player_craft = rider.default_craft
	_change(CRAFT_SELECT)


## The craft select screen chose [param craft]: the course select comes next, or in a
## championship the next race (the first, or the next after the standings).
func craft_chosen(craft: CraftProfile) -> void:
	player_craft = craft
	if mode == Mode.CHAMPIONSHIP:
		if championship == null:
			_start_championship()
		if not championship.is_under_way():
			championship.player = player_rider
		next_championship_race()
	else:
		_change(COURSE_SELECT)


# Starts a championship in the cup chosen, or the first cup, for one begun past the cup
# select, as tests do.
func _start_championship() -> void:
	if cup == null:
		cup = cups[0]
	championship = Championship.new(player_rider, riders, cup.courses, cup, randi())


## The course select screen chose [param info]. A quick race gets the weather chosen there,
## or one drawn from the course's weathers.
func course_chosen(info: CourseInfo) -> void:
	course = info
	forecast = null
	if mode == Mode.QUICK_RACE:
		forecast = Forecast.new(quick_weather) if quick_weather != null else Forecast.pick(weathers_for(info), randi(), 3)
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
	forecast = championship.current_forecast()
	_change(RACE)


## From the standings: choose another craft for the next race.
func change_craft() -> void:
	_change(CRAFT_SELECT)


## Back from the craft select: the standings between championship races, else the rider
## select.
func back_from_craft_select() -> void:
	if mode == Mode.CHAMPIONSHIP and championship != null and championship.is_under_way():
		goto_standings()
	else:
		goto_rider_select()


func goto_rider_select() -> void:
	_change(RIDER_SELECT)


## Back from the rider select: the cup select in a championship, else the main menu.
func back_from_rider_select() -> void:
	if mode == Mode.CHAMPIONSHIP:
		_change(CUP_SELECT)
	else:
		goto_main_menu()


func goto_craft_select() -> void:
	_change(CRAFT_SELECT)


func goto_course_select() -> void:
	_change(COURSE_SELECT)


func goto_main_menu() -> void:
	championship = null
	forecast = null
	_change(MAIN_MENU)


## Quits the game. The current scene goes first, so its sounds stop before the audio
## server shuts down.
func quit() -> void:
	if _quitting:
		return
	_quitting = true
	var scene := get_tree().current_scene
	if scene != null:
		scene.queue_free()
	await get_tree().process_frame
	# The audio server frees a stopped sound on its next mix and the frame after, and frees
	# none at exit, so a sound still playing is reported as leaked. Wait for two mixes (one
	# may have been under way), or a second at most.
	var mixes := 0
	var last := AudioServer.get_time_since_last_mix()
	var give_up := Time.get_ticks_msec() + 1000
	while mixes < 2 and Time.get_ticks_msec() < give_up:
		await get_tree().process_frame
		var since := AudioServer.get_time_since_last_mix()
		if since < last:
			mixes += 1
		last = since
	await get_tree().process_frame
	get_tree().quit()


func _change(path: String) -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(path)


## The value after [param flag] on the command line (`-- --rider koa`), or "".
static func arg_value(flag: String) -> String:
	var args := OS.get_cmdline_user_args()
	var at := args.find(flag)
	return args[at + 1] if at >= 0 and at + 1 < args.size() else ""
