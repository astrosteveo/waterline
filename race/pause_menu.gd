class_name PauseMenu
extends CanvasLayer
## The pause menu: the pause action (Escape, P, gamepad Start) stops the race and offers
## RESUME, RESTART, OPTIONS and QUIT TO MENU.

@export var race: Race

var _root: Control
var _resume: Button
var _options: OptionsPanel


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root.visible


func _unhandled_input(event: InputEvent) -> void:
	if _options != null:
		return
	if event.is_action_pressed(&"pause") or (is_open() and event.is_action_pressed(&"ui_cancel")):
		get_viewport().set_input_as_handled()
		if is_open():
			resume()
		elif _can_pause():
			pause()


func _can_pause() -> bool:
	if race == null or race.phase == Race.Phase.FINISHED:
		return false
	for node in race.get_children():
		if (node is ResultsScreen and (node as ResultsScreen).is_open()) or (node is SoloResults and (node as SoloResults).is_open()):
			return false
	return true


func pause() -> void:
	get_tree().paused = true
	_root.visible = true
	_resume.grab_focus()


func resume() -> void:
	_root.visible = false
	get_tree().paused = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.03, 0.12, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var panel := MenuStyle.panel(64, 38)
	_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 16)
	panel.add_child(column)
	var title := MenuStyle.label("PAUSED", 72, MenuStyle.YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	_resume = _add(column, "RESUME", resume)
	_add(column, "RESTART", func() -> void:
		get_tree().paused = false
		get_tree().reload_current_scene())
	_add(column, "OPTIONS", func() -> void:
		_options = OptionsPanel.new()
		_root.add_child(_options)
		panel.visible = false
		_options.closed.connect(func() -> void:
			_options = null
			panel.visible = true
			_resume.grab_focus()))
	_add(column, "QUIT TO MENU", func() -> void: Game.goto_main_menu())


func _add(column: VBoxContainer, text: String, action: Callable) -> Button:
	var button := MenuStyle.button(text, 38, Vector2(420, 72))
	button.name = text.capitalize().replace(" ", "")
	button.pressed.connect(action)
	column.add_child(button)
	return button
