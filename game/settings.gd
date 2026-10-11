extends Node
## The player's settings (autoload `Settings`): volumes, fullscreen and the controls,
## saved to `user://settings.cfg` and applied at start.
##
## A rebound control replaces the action's first keyboard event or first gamepad event in the
## Input Map, so the rest of the game, which reads only actions, needs no change.

const PATH := "user://settings.cfg"
## Volume sliders and the audio bus each sets.
const VOLUMES: Dictionary[String, StringName] = {"master": &"Master", "engine": &"Engine", "effects": &"Effects"}
## The actions the options screen lets the player rebind, with their names on screen.
const REBINDABLE: Dictionary[StringName, String] = {
	&"throttle": "THROTTLE",
	&"steer_left": "STEER LEFT",
	&"steer_right": "STEER RIGHT",
	&"lean_forward": "LEAN FORWARD",
	&"lean_back": "LEAN BACK",
	&"stunt": "STUNT",
	&"reset_craft": "RESET",
	&"toggle_camera": "CAMERA",
	&"pause": "PAUSE",
}

## Each volume from 0 to 1.
var volumes: Dictionary[String, float] = {"master": 0.8, "engine": 0.8, "effects": 0.8}
var fullscreen: bool = false

var _defaults: Dictionary[StringName, Array] = {}


func _ready() -> void:
	for action in REBINDABLE:
		_defaults[action] = InputMap.action_get_events(action).duplicate()
	load_from_disk()
	apply()


func set_volume(key: String, value: float) -> void:
	volumes[key] = clampf(value, 0.0, 1.0)
	_apply_volume(key)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_window()


## Replaces [param action]'s keyboard binding (or its gamepad binding, when
## [param event] is a gamepad event) with [param event], and takes it off any other
## rebindable action that had it.
func rebind(action: StringName, event: InputEvent) -> void:
	var pad := _is_pad(event)
	for other in REBINDABLE:
		for existing in InputMap.action_get_events(other):
			if _same(existing, event):
				InputMap.action_erase_event(other, existing)
	# Replace the first binding of the same kind where it stands, so it stays the one shown.
	var events := InputMap.action_get_events(action)
	var replaced := false
	for i in events.size():
		if _is_pad(events[i]) == pad:
			events[i] = event
			replaced = true
			break
	if not replaced:
		events.append(event)
	InputMap.action_erase_events(action)
	for kept in events:
		InputMap.action_add_event(action, kept)


## The binding shown on screen for [param action]: its first key, or its first gamepad input.
func binding_text(action: StringName, pad: bool) -> String:
	for event in InputMap.action_get_events(action):
		if _is_pad(event) == pad:
			return event_text(event)
	return "-"


static func event_text(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.keycode
		if code == KEY_NONE:
			code = DisplayServer.keyboard_get_keycode_from_physical(key.physical_keycode)
		return OS.get_keycode_string(code).to_upper()
	if event is InputEventJoypadButton:
		var names := ["A", "B", "X", "Y", "BACK", "GUIDE", "START", "L STICK", "R STICK", "LB", "RB",
				"D-PAD UP", "D-PAD DOWN", "D-PAD LEFT", "D-PAD RIGHT"]
		var index := (event as InputEventJoypadButton).button_index
		return names[index] if index >= 0 and index < names.size() else "BUTTON %d" % index
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		var axes := ["L STICK X", "L STICK Y", "R STICK X", "R STICK Y", "LT", "RT"]
		var axis_name: String = axes[motion.axis] if motion.axis >= 0 and motion.axis < axes.size() else "AXIS %d" % motion.axis
		if motion.axis >= 4:
			return axis_name
		return "%s %s" % [axis_name, "+" if motion.axis_value > 0.0 else "-"]
	return "?"


func reset_controls() -> void:
	for action in REBINDABLE:
		InputMap.action_erase_events(action)
		for event: InputEvent in _defaults[action]:
			InputMap.action_add_event(action, event)


func apply() -> void:
	for key in VOLUMES:
		_apply_volume(key)
	_apply_window()


func save() -> void:
	var config := ConfigFile.new()
	for key in volumes:
		config.set_value("audio", key, volumes[key])
	config.set_value("display", "fullscreen", fullscreen)
	for action in REBINDABLE:
		config.set_value("controls", action, InputMap.action_get_events(action))
	var error := config.save(PATH)
	if error != OK:
		push_error("Could not save %s (error %d)." % [PATH, error])


func load_from_disk() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		push_warning("Could not read %s; using the default settings." % PATH)
		return
	for key in volumes:
		volumes[key] = float(config.get_value("audio", key, volumes[key]))
	fullscreen = bool(config.get_value("display", "fullscreen", false))
	for action in REBINDABLE:
		var events: Variant = config.get_value("controls", action, null)
		if events is Array and not (events as Array).is_empty():
			InputMap.action_erase_events(action)
			for event: Variant in events:
				if event is InputEvent:
					InputMap.action_add_event(action, event)


func _apply_volume(key: String) -> void:
	var bus := AudioServer.get_bus_index(VOLUMES[key])
	if bus < 0:
		return
	var value := volumes[key]
	AudioServer.set_bus_mute(bus, value <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.001)))


func _apply_window() -> void:
	# Under a test harness the window size is fixed; only change it when asked to.
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode and (fullscreen or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN):
		DisplayServer.window_set_mode(mode)


static func _is_pad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


static func _same(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		var ka := a as InputEventKey
		var kb := b as InputEventKey
		return (ka.physical_keycode != KEY_NONE and ka.physical_keycode == kb.physical_keycode) \
				or (ka.keycode != KEY_NONE and ka.keycode == kb.keycode)
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return (a as InputEventJoypadButton).button_index == (b as InputEventJoypadButton).button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		var ma := a as InputEventJoypadMotion
		var mb := b as InputEventJoypadMotion
		return ma.axis == mb.axis and signf(ma.axis_value) == signf(mb.axis_value)
	return false
