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
		Game.goto_craft_select()


## Shows [param info]: its map, conditions and records, each with the rider and craft that set
## it.
func select(info: CourseInfo) -> void:
	selected = info
	_name.text = info.display_name.to_upper()
	_conditions.text = info.conditions
	_map.texture = info.map
	var records := Game.records
	match Game.mode:
		Game.Mode.TIME_TRIAL:
			_records.text = "RECORD   %s%s\nBEST LAP   %s%s" % [
					Race.format_time(records.best_race(info.id)),
					_credit(records.best_race_rider(info.id), records.best_race_craft(info.id)),
					Race.format_time(records.best_lap(info.id)),
					_credit(records.best_lap_rider(info.id), records.best_lap_craft(info.id))]
		Game.Mode.STUNT:
			_records.text = "BEST SCORE   %d%s" % [records.best_stunt_score(info.id),
					_credit(records.best_stunt_rider(info.id), records.best_stunt_craft(info.id))]
		_:
			_records.text = ""


## Who set a record: "  (RIDER, CRAFT)" for [param rider] on the craft with the id
## [param craft_id], the rider alone for a record from before craft ids were kept, and "" for
## no record. A craft that is no longer in [member Game.crafts] shows its id.
static func _credit(rider: String, craft_id: String) -> String:
	var names := PackedStringArray()
	if rider != "":
		names.append(rider.to_upper())
	if craft_id != "":
		var craft := Game.craft_named(craft_id)
		names.append((craft.display_name if craft != null else craft_id).to_upper())
	return "  (%s)" % ", ".join(names) if not names.is_empty() else ""


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

	# The list scrolls between the mode line and the controls hint, keeping the focused course
	# in view, so any number of courses fit. Up to seven show whole; with more, six and a half
	# rows show, so the cut-off one says the list goes on. The margin leaves room for the
	# buttons' slant and focus frame, which the scroll area clips.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.follow_focus = true
	root.add_child(scroll)
	scroll.position = Vector2(56, 222)
	var rows := float(Game.courses.size()) if Game.courses.size() <= 7 else 6.5
	# Rows of 86 px buttons 18 px apart, plus the margin above and below.
	scroll.size = Vector2(508, rows * (86 + 18) - 18 + 2 * 8)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override(&"margin_left", 24)
	margin.add_theme_constant_override(&"margin_right", 24)
	margin.add_theme_constant_override(&"margin_top", 8)
	margin.add_theme_constant_override(&"margin_bottom", 8)
	scroll.add_child(margin)
	var list := VBoxContainer.new()
	MenuStyle.hover_after_layout(list)
	list.name = "Courses"
	list.add_theme_constant_override(&"separation", 18)
	margin.add_child(list)
	for info in Game.courses:
		var button := MenuStyle.button(info.display_name.to_upper(), 42, Vector2(460, 86))
		button.name = info.id
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_entered.connect(select.bind(info))
		MenuStyle.focus_on_hover(button)
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
	# Wide enough for "BEST LAP   0:32.50  (MARINA, SWORDFISH)", so the panel keeps its width
	# from a course with records to one without.
	_records.custom_minimum_size = Vector2(640, 0)
	column.add_child(_records)

	var hint := MenuStyle.label("UP / DOWN: CHOOSE     ENTER / A: RACE     ESC / B: BACK", 28, MenuStyle.DIM)
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position.y -= 40
