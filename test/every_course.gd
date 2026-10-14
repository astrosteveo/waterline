extends Node
## Races four computer riders over every course in [member Game.courses], one after another,
## all laps, and records what went wrong.
##
## A rider fails a course if it doesn't finish within [member time_limit_per_lap] per lap,
## crashes, is disqualified or misses more than [member max_misses] buoys. Any engine error or
## warning during the run fails it too. Each course's lap times, misses and crashes per rider
## are printed as the race ends.
##
## Run it with gdh (test/scenarios/every_course.scenario.json): start this scene with a fixed
## seed, step until [member done], then check that [member failures] is empty.

## Most buoys a rider may miss in a race. Computer races measured 0 to 2 misses per rider.
@export var max_misses: int = 3
## Race time a race may take per lap before the riders still out count as not finishing.
@export_range(30.0, 600.0, 1.0, "suffix:s") var time_limit_per_lap: float = 150.0

## True once every course has been raced.
var done: bool = false
## Each problem found, as a line of text: "gull_cove: Koa crashed 1 time".
var failures: PackedStringArray = PackedStringArray()
## The ids of the courses raced so far.
var courses_raced: PackedStringArray = PackedStringArray()
## Per course id, per rider name: {"finished", "disqualified", "lap_times", "misses", "crashes"}.
var results: Dictionary = {}
## The race under way, or null.
var race: Race

var _logger := _WarningLogger.new()
var _index := -1


func _ready() -> void:
	OS.add_logger(_logger)
	Game.mode = Game.Mode.QUICK_RACE
	Game.player_rider = null
	Game.player_craft = null
	_next_course.call_deferred()


func _exit_tree() -> void:
	OS.remove_logger(_logger)
	Game.course = null


func _physics_process(_delta: float) -> void:
	if race == null or race.phase == Race.Phase.COUNTDOWN:
		return
	if race.race_time > time_limit_per_lap * race.laps:
		_finish_course()


func _next_course() -> void:
	_index += 1
	if _index >= Game.courses.size():
		Game.course = null
		_report_log()
		done = true
		print("every course: %s" % ("passed" if failures.is_empty() else "FAILED\n  " + "\n  ".join(failures)))
		return
	Game.course = Game.courses[_index]
	race = (load("res://race/race.tscn") as PackedScene).instantiate() as Race
	add_child(race)
	# The player's rider rides too, at its own skill, so all four are computer riders.
	race.autopilot(race.player, race.player_rider.ai_skill if race.player_rider != null else 0.85)
	race.all_finished.connect(_finish_course, CONNECT_ONE_SHOT)


func _finish_course() -> void:
	if race == null:
		return
	var id := Game.course.id
	var rows := {}
	print("%s, %d laps:" % [id, race.laps])
	for racer in race.racers:
		var times := PackedStringArray()
		for t in racer.lap_times:
			times.append(Race.format_time(t))
		print("  %-8s laps %s  misses %d  crashes %d%s" % [racer.display_name, ", ".join(times) if not times.is_empty() else "-",
				racer.buoys_missed, racer.crashes, "  DISQUALIFIED" if racer.disqualified else ""])
		rows[racer.display_name] = {
			"finished": racer.finished,
			"disqualified": racer.disqualified,
			"lap_times": Array(racer.lap_times),
			"misses": racer.buoys_missed,
			"crashes": racer.crashes,
		}
		if racer.disqualified:
			failures.append("%s: %s was disqualified" % [id, racer.display_name])
		elif not racer.finished:
			failures.append("%s: %s didn't finish (%d of %d laps in %.0f s)" % [id, racer.display_name,
					racer.laps_done, race.laps, race.race_time])
		if racer.crashes > 0:
			failures.append("%s: %s crashed %d time(s)" % [id, racer.display_name, racer.crashes])
		if racer.buoys_missed > max_misses:
			failures.append("%s: %s missed %d buoys" % [id, racer.display_name, racer.buoys_missed])
	results[id] = rows
	courses_raced.append(id)
	_report_log()
	race.queue_free()
	race = null
	_next_course.call_deferred()


## Adds the engine errors and warnings logged since the last call to [member failures].
func _report_log() -> void:
	var context := Game.courses[_index].id if _index < Game.courses.size() else "after the races"
	for line in _logger.take():
		failures.append("%s: %s" % [context, line])


## Keeps the engine's errors and warnings. The engine may log from any thread.
class _WarningLogger extends Logger:
	var _lines := PackedStringArray()
	var _mutex := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		var kind := "warning" if error_type == ERROR_TYPE_WARNING else "error"
		var text := rationale if rationale != "" else code
		_mutex.lock()
		_lines.append("engine %s: %s (%s:%d in %s)" % [kind, text, file, line, function])
		_mutex.unlock()

	func take() -> PackedStringArray:
		_mutex.lock()
		var lines := _lines
		_lines = PackedStringArray()
		_mutex.unlock()
		return lines
