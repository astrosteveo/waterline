class_name Standings
extends Node3D
## The championship standings after a race, under the cup's name: each rider's points from
## that race and in all, best first, then the next course and its forecast, with a choice of
## another craft for it, or the champion after the last race.

var _next: Button


func _ready() -> void:
	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	_build_ui()
	_next.grab_focus()


func _build_ui() -> void:
	var champ := Game.championship
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.03, 0.12, 0.45)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)
	var panel := MenuStyle.panel(64, 38)
	panel.name = "Panel"
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 14)
	panel.add_child(column)
	if champ == null:
		column.add_child(MenuStyle.label("NO CHAMPIONSHIP", 60, MenuStyle.YELLOW))
		_next = MenuStyle.button("MAIN MENU")
		_next.pressed.connect(Game.goto_main_menu)
		column.add_child(_next)
		return
	var order := champ.standings()
	var over := champ.is_over()
	if champ.cup != null:
		var cup := MenuStyle.label(champ.cup.display_name.to_upper(), 34, MenuStyle.CYAN)
		cup.name = "Cup"
		cup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(cup)
	var title := MenuStyle.label("CHAMPION: %s" % order[0].to_upper() if over else "STANDINGS", 68, MenuStyle.YELLOW)
	title.name = "Title"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	var sub := MenuStyle.label("AFTER RACE %d OF %d" % [champ.race_index, champ.courses.size()], 30, MenuStyle.DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(sub)
	var header := _row()
	header.add_child(_cell("", 90, 26, MenuStyle.DIM))
	header.add_child(_cell("RIDER", 300, 26, MenuStyle.DIM))
	header.add_child(_cell("THIS RACE", 200, 26, MenuStyle.DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_cell("POINTS", 180, 26, MenuStyle.DIM, HORIZONTAL_ALIGNMENT_RIGHT))
	column.add_child(header)
	var last: Dictionary = champ.results.back()["points"] if not champ.results.is_empty() else {}
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override(&"separation", 6)
	column.add_child(rows)
	for i in order.size():
		var name := order[i]
		var color := MenuStyle.YELLOW if champ.player != null and name == champ.player.display_name else MenuStyle.WHITE
		var row := _row()
		row.add_child(_cell(Race.ordinal(i + 1), 90, 44, color))
		row.add_child(_cell(name.to_upper(), 300, 44, color))
		row.add_child(_cell("+%d" % int(last.get(name, 0)), 200, 44, MenuStyle.CYAN, HORIZONTAL_ALIGNMENT_RIGHT))
		row.add_child(_cell(str(champ.points[name]), 180, 44, color, HORIZONTAL_ALIGNMENT_RIGHT))
		rows.add_child(row)
	if not over:
		var next := MenuStyle.label("NEXT: %s" % champ.current_course().display_name.to_upper(), 34, MenuStyle.CYAN)
		next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(next)
		var weather := MenuStyle.label("FORECAST: %s" % CraftSelect.forecast_text(champ), 30, MenuStyle.WHITE)
		weather.name = "Forecast"
		weather.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(weather)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override(&"separation", 40)
	column.add_child(buttons)
	if over:
		_next = MenuStyle.button("MAIN MENU")
		_next.name = "MainMenu"
		_next.pressed.connect(Game.goto_main_menu)
		buttons.add_child(_next)
	else:
		_next = MenuStyle.button("NEXT RACE")
		_next.name = "NextRace"
		_next.pressed.connect(Game.next_championship_race)
		buttons.add_child(_next)
		var craft := MenuStyle.button("CHANGE CRAFT")
		craft.name = "ChangeCraft"
		craft.pressed.connect(Game.change_craft)
		buttons.add_child(craft)
		var quit := MenuStyle.button("QUIT")
		quit.name = "Quit"
		quit.pressed.connect(Game.goto_main_menu)
		buttons.add_child(quit)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 24)
	return row


func _cell(text: String, width: float, size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := MenuStyle.label(text, size, color)
	label.custom_minimum_size = Vector2(width, 0.0)
	label.horizontal_alignment = align
	return label
