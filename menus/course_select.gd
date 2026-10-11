class_name CourseSelect
extends Node3D
## The course select screen: the courses down the left; the focused course's map,
## conditions and records on the right. Confirming starts the race there.

var selected: CourseInfo

var _buttons: Array[Button] = []
var _name: Label
var _conditions: Label
var _map: TextureRect
var _records: Label


func _ready() -> void:
	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	_build_ui()
	var start := Game.course if Game.course != null else Game.courses[0]
	_buttons[maxi(Game.courses.find(start), 0)].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.goto_rider_select()


## Shows [param info]: its map, conditions and records.
func select(info: CourseInfo) -> void:
	selected = info
	_name.text = info.display_name.to_upper()
	_conditions.text = info.conditions
	var map_path := info.scene.replace(".tscn", "_map.png")
	_map.texture = load(map_path) as Texture2D if ResourceLoader.exists(map_path) else null
	var records := Game.records
	match Game.mode:
		Game.Mode.TIME_TRIAL:
			var rider := records.best_race_rider(info.id)
			_records.text = "RECORD   %s%s\nBEST LAP   %s" % [Race.format_time(records.best_race(info.id)),
					"  (%s)" % rider.to_upper() if rider != "" else "", Race.format_time(records.best_lap(info.id))]
		Game.Mode.STUNT:
			_records.text = "BEST SCORE   %d" % records.best_stunt_score(info.id)
		_:
			_records.text = ""


func confirm() -> void:
	if selected != null:
		Game.course_chosen(selected)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var title := MenuStyle.label("CHOOSE A COURSE", 76, MenuStyle.YELLOW)
	root.add_child(title)
	title.position = Vector2(72, 44)
	var mode := MenuStyle.label(Game.mode_name(), 32, MenuStyle.CYAN)
	root.add_child(mode)
	mode.position = Vector2(80, 150)

	var list := VBoxContainer.new()
	list.name = "Courses"
	list.add_theme_constant_override(&"separation", 18)
	root.add_child(list)
	list.position = Vector2(80, 230)
	for info in Game.courses:
		var button := MenuStyle.button(info.display_name.to_upper(), 42, Vector2(460, 86))
		button.name = info.id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_entered.connect(select.bind(info))
		button.mouse_entered.connect(button.grab_focus)
		button.pressed.connect(confirm)
		list.add_child(button)
		_buttons.append(button)
	for i in _buttons.size():
		_buttons[i].focus_neighbor_top = _buttons[i - 1].get_path()
		_buttons[i].focus_neighbor_bottom = _buttons[(i + 1) % _buttons.size()].get_path()
		_buttons[i].focus_neighbor_left = _buttons[i].get_path()
		_buttons[i].focus_neighbor_right = _buttons[i].get_path()

	var panel := MenuStyle.panel(44, 30)
	panel.name = "Details"
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position.x -= 72
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 12)
	panel.add_child(column)
	_name = MenuStyle.label("", 58, MenuStyle.YELLOW)
	column.add_child(_name)
	_map = TextureRect.new()
	_map.custom_minimum_size = Vector2(560, 380)
	_map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(_map)
	_conditions = MenuStyle.label("", 28, MenuStyle.WHITE)
	# Two lines tall, so the panel keeps its height from course to course.
	_conditions.custom_minimum_size = Vector2(560, 74)
	_conditions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_conditions)
	_records = MenuStyle.label("", 30, MenuStyle.CYAN)
	column.add_child(_records)

	var hint := MenuStyle.label("UP / DOWN: CHOOSE     ENTER / A: RACE     ESC / B: BACK", 28, MenuStyle.DIM)
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position.y -= 40
