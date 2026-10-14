class_name RiderSelect
extends CraftShowcase
## The rider select screen: the four riders down the left, the focused rider on their default
## craft floating on the water behind, and the rider's name, line and weight on the right. How
## the craft rides belongs to the craft, which the craft select screen chooses next. Confirming
## hands the rider to [method Game.rider_chosen], which opens the craft select; backing out
## returns to the main menu (in a championship, to the cup select).

## Emitted when the player confirms a rider.
signal rider_chosen(rider: RiderProfile)
## Emitted when the player backs out.
signal cancelled

var selected: RiderProfile

var _name: Label
var _tagline: Label
var _weight: StatBar


func _ready() -> void:
	super()
	_build_ui()
	var start := Game.player_rider if Game.player_rider != null else Game.riders[0]
	_buttons[maxi(Game.riders.find(start), 0)].grab_focus()


## Shows [param rider] on their default craft, in their colours, with their weight.
func select(rider: RiderProfile) -> void:
	selected = rider
	show_craft(rider.default_craft, rider)
	_name.text = rider.display_name.to_upper()
	_tagline.text = rider.tagline
	_weight.value = rider.weight_rating()


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
		Game.back_from_rider_select()


func _build_ui() -> void:
	var root := _add_ui("CHOOSE YOUR RIDER", "UP / DOWN: CHOOSE     ENTER / A: SELECT     ESC / B: BACK")
	for rider in Game.riders:
		var button := _add_choice(root, rider.display_name.to_upper(), rider.display_name)
		button.focus_entered.connect(select.bind(rider))
		button.pressed.connect(confirm)
	_link_focus()

	# Right: the focused rider's name, line and weight.
	var column := _add_panel(root)
	_name = MenuStyle.label("", 64, MenuStyle.YELLOW)
	column.add_child(_name)
	_tagline = MenuStyle.label("", 26, MenuStyle.DIM)
	# Two lines tall, so the panel doesn't jump between short and long descriptions.
	_tagline.custom_minimum_size = Vector2(500, 70)
	_tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_tagline)
	_weight = _add_stat_row(column, "WEIGHT")
	var note := MenuStyle.label("A heavier rider pushes other craft aside and is pushed less.", 22, MenuStyle.DIM)
	note.custom_minimum_size = Vector2(500, 0)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)
