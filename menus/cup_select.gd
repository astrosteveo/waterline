class_name CupSelect
extends Node3D
## The cup select screen, the first screen of a championship: the cups down the left; the
## focused cup's courses, laps and how good the rivals are on the right. Confirming hands the
## cup to [method Game.cup_chosen], which opens the rider select; backing out returns to the
## main menu.

var selected: CupInfo

var _buttons: Array[Button] = []
var _name: Label
var _courses: Label
var _details: Label


func _ready() -> void:
	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	_build_ui()
	var start := Game.cup if Game.cup != null else Game.cups[0]
	_buttons[maxi(Game.cups.find(start), 0)].grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.goto_main_menu()


## Shows [param info]: its courses in order, the laps per race and the rivals' skill.
func select(info: CupInfo) -> void:
	selected = info
	_name.text = info.display_name.to_upper()
	var lines := PackedStringArray()
	for i in info.courses.size():
		lines.append("%d.  %s" % [i + 1, info.courses[i].display_name.to_upper()])
	_courses.text = "\n".join(lines)
	var laps := "%d LAPS A RACE" % info.laps if info.laps > 0 else "EACH COURSE'S OWN LAPS"
	_details.text = "%s\nRIVALS   %s" % [laps, rivals_text(info.skill_offset)]


## How the computer riders ride in a cup with [param skill_offset]: "NORMAL", "SHARPER (+10)".
static func rivals_text(skill_offset: float) -> String:
	var points := roundi(skill_offset * 100.0)
	if points == 0:
		return "NORMAL"
	return "%s (%+d)" % ["SHARPER" if points > 0 else "EASIER", points]


func confirm() -> void:
	if selected != null:
		Game.cup_chosen(selected)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var title := MenuStyle.label("CHOOSE A CUP", 76, MenuStyle.YELLOW)
	root.add_child(title)
	title.position = Vector2(72, 44)
	var mode := MenuStyle.label(Game.mode_name(), 32, MenuStyle.CYAN)
	root.add_child(mode)
	mode.position = Vector2(80, 150)

	var list := VBoxContainer.new()
	list.name = "Cups"
	list.add_theme_constant_override(&"separation", 18)
	root.add_child(list)
	list.position = Vector2(80, 230)
	for info in Game.cups:
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
	column.add_theme_constant_override(&"separation", 16)
	panel.add_child(column)
	_name = MenuStyle.label("", 58, MenuStyle.YELLOW)
	_name.name = "CupName"
	column.add_child(_name)
	_courses = MenuStyle.label("", 34, MenuStyle.WHITE)
	_courses.name = "Courses"
	_courses.custom_minimum_size = Vector2(560, 0)
	column.add_child(_courses)
	_details = MenuStyle.label("", 30, MenuStyle.CYAN)
	_details.name = "CupDetails"
	column.add_child(_details)

	var hint := MenuStyle.label("UP / DOWN: CHOOSE     ENTER / A: SELECT     ESC / B: BACK", 28, MenuStyle.DIM)
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position.y -= 40
