class_name Records
extends RefCounted
## Best times and scores, saved to `user://records.cfg`, and time-trial ghosts, saved to
## `user://ghosts/<course>.ghost`. Each course keeps its best race time and best lap (with the
## rider who set them) and its best stunt score.

const PATH := "user://records.cfg"
const GHOST_DIR := "user://ghosts"
## Bumped when the ghost format changes; older ghosts are ignored.
const GHOST_VERSION := 1

var _config := ConfigFile.new()


func _init() -> void:
	load_from_disk()


func load_from_disk() -> void:
	_config = ConfigFile.new()
	if FileAccess.file_exists(PATH):
		var error := _config.load(PATH)
		if error != OK:
			push_warning("Could not read %s (error %d); starting with no records." % [PATH, error])
			_config = ConfigFile.new()


func save() -> void:
	var error := _config.save(PATH)
	if error != OK:
		push_error("Could not save %s (error %d)." % [PATH, error])


## The best race time on [param course], or INF.
func best_race(course: String) -> float:
	return float(_config.get_value("time_trial", course + "_race", INF))


## The race record's time at the end of each lap (cumulative), or an empty array.
func race_splits(course: String) -> PackedFloat64Array:
	return PackedFloat64Array(_config.get_value("time_trial", course + "_splits", PackedFloat64Array()))


func best_race_rider(course: String) -> String:
	return str(_config.get_value("time_trial", course + "_race_rider", ""))


## The best lap on [param course], or INF.
func best_lap(course: String) -> float:
	return float(_config.get_value("time_trial", course + "_lap", INF))


## The best stunt score on [param course], or 0.
func best_stunt_score(course: String) -> int:
	return int(_config.get_value("stunt", course + "_score", 0))


## Records a time trial. Returns which records it set: race and/or lap.
func submit_time_trial(course: String, rider: String, race_time: float, lap_times: PackedFloat64Array) -> Dictionary:
	var result := {"race": false, "lap": false}
	if race_time < best_race(course):
		_config.set_value("time_trial", course + "_race", race_time)
		_config.set_value("time_trial", course + "_race_rider", rider)
		var splits := PackedFloat64Array()
		var total := 0.0
		for t in lap_times:
			total += t
			splits.append(total)
		_config.set_value("time_trial", course + "_splits", splits)
		result["race"] = true
	var best := INF
	for t in lap_times:
		best = minf(best, t)
	if best < best_lap(course):
		_config.set_value("time_trial", course + "_lap", best)
		_config.set_value("time_trial", course + "_lap_rider", rider)
		result["lap"] = true
	if result["race"] or result["lap"]:
		save()
	return result


## Records a stunt score. Returns true if it is a new best.
func submit_stunt_score(course: String, rider: String, score: int) -> bool:
	if score <= best_stunt_score(course):
		return false
	_config.set_value("stunt", course + "_score", score)
	_config.set_value("stunt", course + "_rider", rider)
	save()
	return true


## Clears every record and ghost.
func clear() -> void:
	_config = ConfigFile.new()
	save()
	var dir := DirAccess.open(GHOST_DIR)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)


## Saves a ghost for [param course]: a dictionary from [GhostRecorder].
func save_ghost(course: String, ghost: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	var file := FileAccess.open_compressed(_ghost_path(course), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("Could not save the ghost for %s (error %d)." % [course, FileAccess.get_open_error()])
		return
	ghost["version"] = GHOST_VERSION
	file.store_var(ghost)


## The saved ghost for [param course], or an empty dictionary.
func load_ghost(course: String) -> Dictionary:
	var path := _ghost_path(course)
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return {}
	var data: Variant = file.get_var()
	if data is Dictionary and int((data as Dictionary).get("version", 0)) == GHOST_VERSION:
		return data
	return {}


func _ghost_path(course: String) -> String:
	return "%s/%s.ghost" % [GHOST_DIR, course]
