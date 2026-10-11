class_name MainMenu
extends Node3D
## The main menu: the game's name over a slow flight round a course, and the modes.

var _buttons: Array[Button] = []


func _ready() -> void:
	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	_build_ui()
	_buttons[0].grab_focus()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var title := MenuStyle.label("WATERLINE", 150, MenuStyle.YELLOW)
	title.add_theme_constant_override(&"outline_size", 22)
	root.add_child(title)
	title.position = Vector2(96, 70)
	var subtitle := MenuStyle.label("JET SKI RACING ON A MOVING SEA", 32, MenuStyle.WHITE)
	root.add_child(subtitle)
	subtitle.position = Vector2(108, 290)

	var list := VBoxContainer.new()
	list.name = "Modes"
	list.add_theme_constant_override(&"separation", 16)
	root.add_child(list)
	list.position = Vector2(110, 380)
	var entries := [
		["CHAMPIONSHIP", func() -> void: Game.start_mode(Game.Mode.CHAMPIONSHIP)],
		["QUICK RACE", func() -> void: Game.start_mode(Game.Mode.QUICK_RACE)],
		["TIME TRIAL", func() -> void: Game.start_mode(Game.Mode.TIME_TRIAL)],
		["STUNT MODE", func() -> void: Game.start_mode(Game.Mode.STUNT)],
		["QUIT", func() -> void: get_tree().quit()],
	]
	for entry: Array in entries:
		var button := MenuStyle.button(entry[0], 42, Vector2(420, 78))
		button.name = (entry[0] as String).capitalize().replace(" ", "")
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(entry[1])
		button.mouse_entered.connect(button.grab_focus)
		list.add_child(button)
		_buttons.append(button)
	for i in _buttons.size():
		_buttons[i].focus_neighbor_top = _buttons[i - 1].get_path()
		_buttons[i].focus_neighbor_bottom = _buttons[(i + 1) % _buttons.size()].get_path()

	var hint := MenuStyle.label("UP / DOWN: CHOOSE     ENTER / A: SELECT", 28, MenuStyle.DIM)
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position.y -= 40
