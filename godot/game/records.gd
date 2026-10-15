class_name Records
extends RefCounted
## Best times and scores, saved to `user://records.cfg`, and time-trial ghosts, saved to
## `user://ghosts/<course>.ghost`. Each course keeps its best race time, best lap and best stunt
## score, each with the name of the rider and the id of the craft ([member CraftProfile.id])
## that set it. A record saved before craft ids were kept has no craft: its id reads as "".

const PATH := "user://records.cfg"
const GHOST_DIR := "user://ghosts"
## Bumped when the ghost format changes; older ghosts are ignored. Adding the "craft" key
## didn't bump it, because a ghost without one still plays, on the default craft.
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


## The name of the rider who set the race record on [param course], or "".
func best_race_rider(course: String) -> String:
	return str(_config.get_value("time_trial", course + "_race_rider", ""))


## The id of the craft that set the race record on [param course], or "".
func best_race_craft(course: String) -> String:
	return str(_config.get_value("time_trial", course + "_race_craft", ""))


## The best lap on [param course], or INF.
func best_lap(course: String) -> float:
	return float(_config.get_value("time_trial", course + "_lap", INF))


## The name of the rider who set the lap record on [param course], or "".
func best_lap_rider(course: String) -> String:
	return str(_config.get_value("time_trial", course + "_lap_rider", ""))


## The id of the craft that set the lap record on [param course], or "".
func best_lap_craft(course: String) -> String:
	return str(_config.get_value("time_trial", course + "_lap_craft", ""))


## The best stunt score on [param course], or 0.
func best_stunt_score(course: String) -> int:
	return int(_config.get_value("stunt", course + "_score", 0))


## The name of the rider who set the best stunt score on [param course], or "".
func best_stunt_rider(course: String) -> String:
	return str(_config.get_value("stunt", course + "_rider", ""))


## The id of the craft that set the best stunt score on [param course], or "".
func best_stunt_craft(course: String) -> String:
	return str(_config.get_value("stunt", course + "_craft", ""))


## Records a time trial ridden by [param rider] on the craft with the id [param craft].
## Returns which records it set: race and/or lap.
func submit_time_trial(course: String, rider: String, craft: String, race_time: float,
		lap_times: PackedFloat64Array) -> Dictionary:
	var result := {"race": false, "lap": false}
	if race_time < best_race(course):
		_config.set_value("time_trial", course + "_race", race_time)
		_config.set_value("time_trial", course + "_race_rider", rider)
		_config.set_value("time_trial", course + "_race_craft", craft)
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
		_config.set_value("time_trial", course + "_lap_craft", craft)
		result["lap"] = true
	if result["race"] or result["lap"]:
		save()
	return result


## Records a stunt score by [param rider] on the craft with the id [param craft]. Returns true
## if it is a new best.
func submit_stunt_score(course: String, rider: String, craft: String, score: int) -> bool:
	if score <= best_stunt_score(course):
		return false
	_config.set_value("stunt", course + "_score", score)
	_config.set_value("stunt", course + "_rider", rider)
	_config.set_value("stunt", course + "_craft", craft)
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


## Saves a ghost for [param course]: a dictionary from [method GhostRecorder.data].
func save_ghost(course: String, ghost: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(GHOST_DIR)
	var file := FileAccess.open_compressed(_ghost_path(course), FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("Could not save the ghost for %s (error %d)." % [course, FileAccess.get_open_error()])
		return
	ghost["version"] = GHOST_VERSION
	file.store_var(ghost)


## The saved ghost for [param course], or an empty dictionary. A ghost saved before craft ids
## were kept has no "craft" key.
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
