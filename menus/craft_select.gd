class_name CraftSelect
extends CraftShowcase
## The craft select screen, after the rider select: the craft down the left, the focused craft
## floating on the water in the chosen rider's colours, and the craft's name, line and four
## stats on the right. The craft in [member Game.player_craft] has the focus first: the
## rider's default craft after the rider select, the craft chosen here when coming back from
## the course select. Confirming hands the craft to [method Game.craft_chosen], which opens
## the course select (or the championship's first race); backing out returns to the rider
## select.

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
		Game.goto_rider_select()


func _build_ui() -> void:
	var root := _add_ui("CHOOSE YOUR CRAFT", "UP / DOWN: CHOOSE     ENTER / A: SELECT     ESC / B: BACK")
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
