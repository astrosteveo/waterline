class_name RiderSelect
extends CraftShowcase
## The rider select screen: the four riders down the left, the chosen rider on their default
## craft floating on the water behind, the craft's name and stats on the right. Confirming
## hands the rider to [method Game.rider_chosen], which opens the craft select; backing out
## returns to the main menu.

## Emitted when the player confirms a rider.
signal rider_chosen(rider: RiderProfile)
## Emitted when the player backs out.
signal cancelled

var selected: RiderProfile

var _name: Label
var _tagline: Label
var _craft_name: Label
var _bars: Array[StatBar] = []


func _ready() -> void:
	super()
	_build_ui()
	var start := Game.player_rider if Game.player_rider != null else Game.riders[0]
	_buttons[maxi(Game.riders.find(start), 0)].grab_focus()


## Shows [param rider]: the craft in the rider's colours, and the rider's default craft with
## its stats.
func select(rider: RiderProfile) -> void:
	selected = rider
	var craft := rider.default_craft
	show_craft(craft, rider)
	_name.text = rider.display_name.to_upper()
	_tagline.text = rider.tagline
	_craft_name.text = "RIDES THE %s" % craft.display_name.to_upper() if craft != null else ""
	for i in _bars.size():
		_bars[i].value = craft.rating(CraftProfile.STATS[i]) if craft != null else 3.0


## Moves on to the craft select with the selected rider.
func confirm() -> void:
	if selected == null:
		return
	rider_chosen.emit(selected)
	Game.rider_chosen(selected)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		cancelled.emit()
		Game.goto_main_menu()


func _build_ui() -> void:
	var root := _add_ui("CHOOSE YOUR RIDER", "UP / DOWN: CHOOSE     ENTER / A: SELECT     ESC / B: BACK")
	for rider in Game.riders:
		var button := _add_choice(root, rider.display_name.to_upper(), rider.display_name)
		button.focus_entered.connect(select.bind(rider))
		button.pressed.connect(confirm)
	_link_focus()

	# Right: the selected rider's name, line and stats.
	var column := _add_panel(root)
	_name = MenuStyle.label("", 64, MenuStyle.YELLOW)
	column.add_child(_name)
	_tagline = MenuStyle.label("", 26, MenuStyle.DIM)
	# Two lines tall, so the panel doesn't jump between short and long descriptions.
	_tagline.custom_minimum_size = Vector2(500, 70)
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_tagline)
	_craft_name = MenuStyle.label("", 28, MenuStyle.CYAN)
	column.add_child(_craft_name)
	for i in CraftProfile.STATS.size():
		_bars.append(_add_stat_row(column, CraftProfile.STAT_LABELS[i]))
