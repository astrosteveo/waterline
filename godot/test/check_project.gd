extends SceneTree
## Loads every script, scene and resource in the project, so GDScript compiles each script and
## each scene and resource loads the files it refers to. Quits with exit code 1 if Godot reported
## any error while loading (a parse error, a missing file, a broken reference) or a file did not
## load. Godot prints each error itself; this script prints a count at the end.
## test/check_project.sh runs it after importing the project, in CI and locally. On its own:
## [code]godot --headless --path . --script res://test/check_project.gd[/code]
## It only loads files: nothing goes into the scene tree, so no [code]_ready()[/code] runs
## (the autoloads do start, as in every Godot run).


## Counts the errors Godot reports. Godot can call a logger from any thread, so the count is
## guarded by a mutex.
class ErrorCounter extends Logger:
	var errors := 0
	var _mutex := Mutex.new()

	func _log_error(_function: String, _file: String, _line: int, _code: String,
			_rationale: String, _editor_notify: bool, error_type: int,
			_script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == ERROR_TYPE_WARNING:
			return
		_mutex.lock()
		errors += 1
		_mutex.unlock()


func _initialize() -> void:
	var counter := ErrorCounter.new()
	OS.add_logger(counter)
	var paths := PackedStringArray()
	_collect("res://", paths)
	var failed := PackedStringArray()
	for path in paths:
		if ResourceLoader.load(path) == null:
			failed.append(path)
	OS.remove_logger(counter)

	for path in failed:
		printerr("check_project: failed to load %s" % path)
	print("check_project: checked %d files: %d did not load, Godot reported %d errors." % [
			paths.size(), failed.size(), counter.errors])
	quit(1 if failed.size() > 0 or counter.errors > 0 else 0)


## Adds every loadable file under [param dir] to [param paths], skipping the folders Godot
## itself skips: hidden ones (.godot, .github) and ones with a .gdignore file.
func _collect(dir: String, paths: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		var sub_path := dir.path_join(sub)
		if sub.begins_with(".") or FileAccess.file_exists(sub_path.path_join(".gdignore")):
			continue
		_collect(sub_path, paths)
	for file in DirAccess.get_files_at(dir):
		if file.get_extension() in ["import", "uid"]:
			continue
		var path := dir.path_join(file)
		if ResourceLoader.exists(path):
			paths.append(path)
