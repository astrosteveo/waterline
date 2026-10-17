extends Node
## Writes every line the announcer can call to a JSON file, each line's id to the words the
## voice says, then quits. The voice tool (`tools/voice/voice_tool.py`) runs it:
## `godot --headless --path godot res://test/tools/announcer_lines.tscn -- OUT.json`.


func _ready() -> void:
	var lines := Announcer.game_lines()
	var out := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	out.store_string(JSON.stringify(lines, "  ", true))
	out.close()
	print("%d lines" % lines.size())
	get_tree().quit()
