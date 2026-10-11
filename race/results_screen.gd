class_name ResultsScreen
extends CanvasLayer
## The results at the end of a race: each racer's place, name, total time and best lap.
## Racers still out on the course show as racing and fill in as they finish; a disqualified
## racer shows DQ. "Race again" reloads the race scene.

## Emitted when the player picks "Race again".
signal race_again_pressed
## Emitted when the player picks "Quit".
signal quit_pressed

@export var race: Race
## Seconds after the player finishes before the results appear.
@export_range(0.0, 10.0, 0.1, "suffix:s") var delay: float = 3.3

const YELLOW := Color(1.0, 0.86, 0.12)
const WHITE := Color(1.0, 1.0, 1.0)
const DIM := Color(0.72, 0.8, 0.95)
const RED := Color(1.0, 0.3, 0.22)

var _font: FontVariation
var _root: Control
var _rows: VBoxContainer
var _again: Button
var _shown := false


func _ready() -> void:
	layer = 8
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.9
	_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.18, 1.0), Vector2.ZERO)
	_build()
	_root.visible = false
	if race != null:
		race.finished.connect(_on_race_finished.bind(false))
		race.all_finished.connect(_on_race_finished.bind(true))


## Shows the results now.
func open() -> void:
	if _shown:
		return
	_shown = true
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, ^"modulate:a", 1.0, 0.35)
	_refresh()
	_again.grab_focus()


func is_open() -> bool:
	return _shown


## Opens the results after [member delay]: when the player finishes, or, when watching a
## race, once everyone has ([param everyone]).
func _on_race_finished(everyone: bool) -> void:
	if race.watching != everyone:
		return
	if delay <= 0.0:
		open()
	else:
		get_tree().create_timer(delay, false).timeout.connect(open)


func _process(_delta: float) -> void:
	if _shown:
		_refresh()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.03, 0.12, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.12, 0.36, 0.92)
	style.border_color = YELLOW
	style.set_border_width_all(6)
	style.set_corner_radius_all(14)
	style.skew = Vector2(0.06, 0.0)
	style.content_margin_left = 64
	style.content_margin_right = 64
	style.content_margin_top = 36
	style.content_margin_bottom = 40
	panel.add_theme_stylebox_override(&"panel", style)
	_root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH

	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 18)
	panel.add_child(column)
	var title := _label("RESULTS", 72, YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	if race != null and race.course_scene != null:
		var course_name := _label("", 30, DIM)
		course_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(course_name)
		course_name.ready.connect(func() -> void:
			if race.course != null:
				course_name.text = race.course.course_name.to_upper())
	var header := _row_box()
	header.add_child(_cell("", 90, 26, DIM))
	header.add_child(_cell("RIDER", 300, 26, DIM))
	header.add_child(_cell("TIME", 220, 26, DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_cell("BEST LAP", 220, 26, DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	column.add_child(header)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override(&"separation", 6)
	column.add_child(_rows)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 40)
	column.add_child(buttons)
	_again = _button("RACE AGAIN")
	_again.pressed.connect(_on_again)
	buttons.add_child(_again)
	var quit := _button("QUIT")
	quit.pressed.connect(_on_quit)
	buttons.add_child(quit)


func _refresh() -> void:
	if race == null:
		return
	var order := race.racers.duplicate()
	order.sort_custom(func(a: RacerState, b: RacerState) -> bool: return a.place < b.place)
	while _rows.get_child_count() < order.size():
		var row := _row_box()
		row.add_child(_cell("", 90, 44, WHITE))
		row.add_child(_cell("", 300, 44, WHITE))
		row.add_child(_cell("", 220, 44, WHITE, HORIZONTAL_ALIGNMENT_RIGHT))
		row.add_child(_cell("", 220, 44, WHITE, HORIZONTAL_ALIGNMENT_RIGHT))
		_rows.add_child(row)
	for i in order.size():
		var racer: RacerState = order[i]
		var cells := _rows.get_child(i).get_children()
		var color := YELLOW if racer.is_player else WHITE
		var time_text := Race.format_time(racer.finish_time) if racer.finished else "RACING"
		if racer.disqualified:
			time_text = "DQ"
		_set_cell(cells[0], Race.ordinal(racer.place) if not racer.disqualified else "--", color)
		_set_cell(cells[1], racer.display_name.to_upper(), color)
		_set_cell(cells[2], time_text, RED if racer.disqualified else color)
		_set_cell(cells[3], Race.format_time(racer.best_lap()), color)


func _set_cell(cell: Node, text: String, color: Color) -> void:
	var label := cell as Label
	label.text = text
	label.add_theme_color_override(&"font_color", color)


func _row_box() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	return row


func _cell(text: String, width: float, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := _label(text, size, color)
	label.custom_minimum_size = Vector2(width, 0.0)
	label.horizontal_alignment = align
	return label


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.02, 0.05, 0.16))
	label.add_theme_constant_override(&"outline_size", maxi(size / 7, 4))
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_override(&"font", _font)
	button.add_theme_font_size_override(&"font_size", 38)
	button.custom_minimum_size = Vector2(300, 72)
	for state in [&"normal", &"hover", &"pressed", &"focus"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.skew = Vector2(0.15, 0.0)
		match state:
			&"normal":
				style.bg_color = Color(0.08, 0.24, 0.62)
			&"hover":
				style.bg_color = Color(0.12, 0.34, 0.8)
			&"pressed":
				style.bg_color = Color(0.9, 0.6, 0.05)
			&"focus":
				style.bg_color = Color(0, 0, 0, 0)
				style.border_color = YELLOW
				style.set_border_width_all(5)
				style.draw_center = false
		button.add_theme_stylebox_override(state, style)
	button.add_theme_color_override(&"font_color", WHITE)
	button.add_theme_color_override(&"font_focus_color", YELLOW)
	button.add_theme_color_override(&"font_hover_color", YELLOW)
	return button


func _on_again() -> void:
	race_again_pressed.emit()
	get_tree().reload_current_scene()


func _on_quit() -> void:
	quit_pressed.emit()
	get_tree().quit()
