class_name CraftSelect
extends CraftShowcase
## The craft select screen, after the rider select: the craft down the left, the focused craft
## floating on the water in the chosen rider's colours, and the craft's name, line and four
## stats on the right. The craft in [member Game.player_craft] has the focus first: the
## rider's default craft after the rider select, the craft chosen here when coming back from
## the course select. Confirming hands the craft to [method Game.craft_chosen], which opens
## the course select (or the championship's next race); backing out returns to the rider
## select, or between championship races to the standings. In a championship it shows the
## next race's course and forecast.

## Emitted when the player confirms a craft.
signal craft_chosen(craft: CraftProfile)
## Emitted when the player backs out.
signal cancelled

var selected: CraftProfile
## The rider the craft is for: [member Game.player_rider], or the first rider when the screen
## runs on its own.
var rider: RiderProfile

var _name: Label
var _tagline: Label
var _own: Label
var _bars: Array[StatBar] = []


func _ready() -> void:
	super()
	rider = Game.player_rider if Game.player_rider != null else Game.riders[0]
	_build_ui()
	var start := Game.player_craft if Game.player_craft != null else rider.default_craft
	_buttons[maxi(Game.crafts.find(start), 0)].grab_focus()


## Shows [param craft] on the water in the rider's colours, with its stats.
func select(craft: CraftProfile) -> void:
	selected = craft
	show_craft(craft, rider)
	_name.text = craft.display_name.to_upper()
	_tagline.text = craft.tagline
	_own.text = "%s'S OWN CRAFT" % rider.display_name.to_upper() if craft == rider.default_craft else ""
	for i in _bars.size():
		_bars[i].value = craft.rating(CraftProfile.STATS[i])


## Moves on with the selected craft.
func confirm() -> void:
	if selected == null:
		return
	craft_chosen.emit(selected)
	Game.craft_chosen(selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
		Game.back_from_craft_select()


func _build_ui() -> void:
	var root := _add_ui("CHOOSE YOUR CRAFT", "UP / DOWN: CHOOSE     ENTER / A: SELECT     ESC / B: BACK")
	var champ := Game.championship
	if Game.mode == Game.Mode.CHAMPIONSHIP and champ != null and not champ.is_over():
		# Under the list: the race the craft is for, and its weather.
		var panel := MenuStyle.panel(36, 20)
		panel.name = "NextRace"
		root.add_child(panel)
		panel.position = Vector2(72, 700)
		var lines := VBoxContainer.new()
		panel.add_child(lines)
		lines.add_child(MenuStyle.label("RACE %d: %s" % [champ.race_index + 1, champ.current_course().display_name.to_upper()],
				34, MenuStyle.YELLOW))
		var forecast := MenuStyle.label("FORECAST: %s" % forecast_text(champ), 30, MenuStyle.WHITE)
		forecast.name = "Forecast"
		lines.add_child(forecast)
	for craft in Game.crafts:
		var button := _add_choice(root, craft.display_name.to_upper(), craft.id)
		button.focus_entered.connect(select.bind(craft))
		button.pressed.connect(confirm)
	_link_focus()

	# Right: the focused craft's name, line and stats.
	var column := _add_panel(root)
	_name = MenuStyle.label("", 64, MenuStyle.YELLOW)
	column.add_child(_name)
	_tagline = MenuStyle.label("", 26, MenuStyle.DIM)
	# Two lines tall, so the panel doesn't jump between short and long descriptions.
	_tagline.custom_minimum_size = Vector2(500, 70)
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_tagline)
	_own = MenuStyle.label("", 28, MenuStyle.CYAN)
	# Keeps its height when empty, so the stats don't move.
	_own.custom_minimum_size = Vector2(0, 40)
	column.add_child(_own)
	for i in CraftProfile.STATS.size():
		_bars.append(_add_stat_row(column, CraftProfile.STAT_LABELS[i]))


## The weather of [param champ]'s next race: "CLEAR, THEN STORM ON LAP 2".
static func forecast_text(champ: Championship) -> String:
	var forecast := champ.current_forecast()
	return forecast.describe(champ.laps) if forecast != null else "AS USUAL"
