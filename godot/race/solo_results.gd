class_name SoloResults
extends CanvasLayer
## The end of a time trial or a stunt run: a title, rows of results, and buttons to try
## again, pick another course or go back to the main menu.

## Seconds before the screen appears.
@export_range(0.0, 10.0, 0.1, "suffix:s") var delay: float = 2.5

var _root: Control
var _title: Label
var _rows: VBoxContainer
var _retry: Button
var _shown := false


func _ready() -> void:
	layer = 8
	_build()
	_root.visible = false


## True once the screen shows (after its delay) and takes input.
func is_open() -> bool:
	return _root.visible


## Shows [param title] and [param rows] (each [label, value, colour]) after [member delay].
func open(title: String, rows: Array) -> void:
	if _shown:
		return
	_shown = true
	_title.text = title
	for row: Array in rows:
		var line := HBoxContainer.new()
		line.add_theme_constant_override(&"separation", 24)
		var label := MenuStyle.label(str(row[0]), 38, MenuStyle.DIM)
		label.custom_minimum_size = Vector2(380, 0)
		line.add_child(label)
		var value := MenuStyle.label(str(row[1]), 44, row[2] if row.size() > 2 else MenuStyle.WHITE)
		value.custom_minimum_size = Vector2(300, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(value)
		_rows.add_child(line)
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, ^"modulate:a", 1.0, 0.35)
	_retry.grab_focus()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.03, 0.12, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)
	var panel := MenuStyle.panel(64, 38)
	_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	panel.add_child(column)
	_title = MenuStyle.label("", 72, MenuStyle.YELLOW)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 4)
	column.add_child(_rows)
	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 40)
	column.add_child(buttons)
	_retry = MenuStyle.button("RETRY")
	_retry.pressed.connect(func() -> void: get_tree().reload_current_scene())
	buttons.add_child(_retry)
	var courses := MenuStyle.button("COURSES")
	courses.pressed.connect(func() -> void: Game.goto_course_select())
	buttons.add_child(courses)
	var menu := MenuStyle.button("MAIN MENU")
	menu.pressed.connect(func() -> void: Game.goto_main_menu())
	buttons.add_child(menu)
