class_name OptionsPanel
extends Control
## The options: volume sliders, fullscreen, the controls (each action's keyboard key and
## gamepad input, rebound by pressing the new one), and clearing the records. It works over
## the main menu and over the paused race; closing it saves the settings.

## Emitted when the panel closes.
signal closed

var _rows: Dictionary[StringName, Array] = {}
var _listening: Button
var _listening_action: StringName
var _listening_pad := false
var _first: Control
var _clear: Button
var _clear_armed := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	_first.grab_focus()


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.03, 0.12, 0.7)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := MenuStyle.panel(48, 30)
	panel.name = "Panel"
	add_child(panel)
	# Anchored at the centre and growing both ways, so it stays centred whatever its size.
	panel.set_anchors_preset(Control.PRESET_CENTER, true)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 16)
	panel.add_child(column)
	var title := MenuStyle.label("OPTIONS", 64, MenuStyle.YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override(&"separation", 56)
	column.add_child(sides)

	# Left: sound, display, resets.
	var left := VBoxContainer.new()
	left.add_theme_constant_override(&"separation", 12)
	sides.add_child(left)
	left.add_child(MenuStyle.label("SOUND", 32, MenuStyle.CYAN))
	for key in Settings.VOLUMES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 16)
		var label := MenuStyle.label(key.to_upper(), 28)
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var slider := HSlider.new()
		slider.name = "Volume" + key.capitalize()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.value = roundf(Settings.volumes[key] * 100.0)
		slider.custom_minimum_size = Vector2(300, 36)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider)
		var value := MenuStyle.label("%d" % slider.value, 28, MenuStyle.YELLOW)
		value.custom_minimum_size = Vector2(60, 0)
		row.add_child(value)
		slider.value_changed.connect(func(v: float) -> void:
			Settings.set_volume(key, v / 100.0)
			value.text = "%d" % v)
		left.add_child(row)
		if _first == null:
			_first = slider
	left.add_child(MenuStyle.label("DISPLAY", 32, MenuStyle.CYAN))
	var fullscreen := MenuStyle.button("", 28, Vector2(380, 56))
	fullscreen.name = "Fullscreen"
	fullscreen.text = "FULLSCREEN: %s" % ("ON" if Settings.fullscreen else "OFF")
	fullscreen.pressed.connect(func() -> void:
		Settings.set_fullscreen(not Settings.fullscreen)
		fullscreen.text = "FULLSCREEN: %s" % ("ON" if Settings.fullscreen else "OFF"))
	left.add_child(fullscreen)
	var reset := MenuStyle.button("RESET CONTROLS", 28, Vector2(380, 56))
	reset.name = "ResetControls"
	reset.pressed.connect(func() -> void:
		Settings.reset_controls()
		_refresh())
	left.add_child(reset)
	_clear = MenuStyle.button("CLEAR RECORDS", 28, Vector2(380, 56))
	_clear.name = "ClearRecords"
	_clear.pressed.connect(_on_clear)
	_clear.focus_exited.connect(func() -> void:
		_clear_armed = false
		_clear.text = "CLEAR RECORDS")
	left.add_child(_clear)

	# Right: the controls.
	var right := VBoxContainer.new()
	right.add_theme_constant_override(&"separation", 6)
	sides.add_child(right)
	right.add_child(MenuStyle.label("CONTROLS", 32, MenuStyle.CYAN))
	var header := HBoxContainer.new()
	header.add_theme_constant_override(&"separation", 12)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(230, 0)
	header.add_child(spacer)
	for text in ["KEYBOARD", "GAMEPAD"]:
		var cell := MenuStyle.label(text, 22, MenuStyle.DIM)
		cell.custom_minimum_size = Vector2(230, 0)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header.add_child(cell)
	right.add_child(header)
	for action in Settings.REBINDABLE:
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 12)
		var label := MenuStyle.label(Settings.REBINDABLE[action], 26)
		label.custom_minimum_size = Vector2(230, 0)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		var key := MenuStyle.button("", 22, Vector2(230, 44))
		key.name = "Key_" + action
		key.pressed.connect(_listen.bind(key, action, false))
		row.add_child(key)
		var pad := MenuStyle.button("", 22, Vector2(230, 44))
		pad.name = "Pad_" + action
		pad.pressed.connect(_listen.bind(pad, action, true))
		row.add_child(pad)
		_rows[action] = [key, pad]
		right.add_child(row)
	_refresh()

	var back := MenuStyle.button("BACK", 34, Vector2(300, 64))
	back.name = "Back"
	back.pressed.connect(close)
	var back_row := HBoxContainer.new()
	back_row.alignment = BoxContainer.ALIGNMENT_CENTER
	back_row.add_child(back)
	column.add_child(back_row)
	var hint := MenuStyle.label("ENTER / A ON A CONTROL, THEN PRESS THE NEW KEY OR BUTTON     ESC: CANCEL", 22, MenuStyle.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _refresh() -> void:
	for action in _rows:
		var buttons: Array = _rows[action]
		(buttons[0] as Button).text = Settings.binding_text(action, false)
		(buttons[1] as Button).text = Settings.binding_text(action, true)


func _listen(button: Button, action: StringName, pad: bool) -> void:
	_listening = button
	_listening_action = action
	_listening_pad = pad
	button.text = "PRESS A BUTTON..." if pad else "PRESS A KEY..."


func _input(event: InputEvent) -> void:
	if _listening == null:
		return
	if not event.is_pressed() or event.is_echo():
		return
	var chosen: InputEvent = null
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		chosen = null
	elif _listening_pad and event is InputEventJoypadButton:
		var button := InputEventJoypadButton.new()
		button.button_index = (event as InputEventJoypadButton).button_index
		chosen = button
	elif _listening_pad and event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
		var motion := InputEventJoypadMotion.new()
		motion.axis = (event as InputEventJoypadMotion).axis
		motion.axis_value = signf((event as InputEventJoypadMotion).axis_value)
		chosen = motion
	elif not _listening_pad and event is InputEventKey:
		var key := InputEventKey.new()
		key.physical_keycode = (event as InputEventKey).physical_keycode
		chosen = key
	else:
		return
	if chosen != null:
		Settings.rebind(_listening_action, chosen)
	get_viewport().set_input_as_handled()
	var button := _listening
	_listening = null
	_refresh()
	button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if _listening == null and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_clear() -> void:
	if not _clear_armed:
		_clear_armed = true
		_clear.text = "PRESS AGAIN TO CLEAR"
		return
	_clear_armed = false
	Game.records.clear()
	_clear.text = "RECORDS CLEARED"


## Saves and closes.
func close() -> void:
	Settings.save()
	closed.emit()
	queue_free()
