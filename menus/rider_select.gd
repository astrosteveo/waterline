class_name RiderSelect
extends Node3D
## The rider select screen: the four riders down the left, the chosen rider's craft
## floating on the water behind, the rider's default craft and its stats on the right. Confirming hands the rider to
## [method Game.rider_chosen], which moves on to the course select (or the championship's
## first race); backing out returns to the main menu.

## Emitted when the player confirms a rider.
signal rider_chosen(rider: RiderProfile)
## Emitted when the player backs out.
signal cancelled

## The water and scenery behind the menu.
@export var backdrop_scene: PackedScene = preload("res://levels/gull_cove.tscn")
## How fast the camera circles the craft, in radians per second.
@export var orbit_speed: float = 0.18

var selected: RiderProfile

var _camera: Camera3D
var _craft: JetSki
var _anchor := Transform3D.IDENTITY
var _buttons: Array[Button] = []
var _name: Label
var _tagline: Label
var _craft_name: Label
var _bars: Array[StatBar] = []
var _orbit := 0.6


func _ready() -> void:
	var backdrop := backdrop_scene.instantiate()
	add_child(backdrop)
	move_child(backdrop, 0)
	var course := backdrop as Course
	_anchor = course.grid_transform(1, 4) if course != null else Transform3D.IDENTITY
	_craft = preload("res://jetski/jetski.tscn").instantiate() as JetSki
	_craft.name = "Craft"
	_craft.transform = _anchor
	_craft.crashes_enabled = false
	add_child(_craft)
	_craft.hold(_anchor)
	_camera = Camera3D.new()
	# Moved in _process.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 55.0
	_camera.far = 6000.0
	add_child(_camera)
	_camera.make_current()
	_build_ui()
	var start := Game.player_rider if Game.player_rider != null else Game.riders[0]
	_buttons[maxi(Game.riders.find(start), 0)].grab_focus()


func _process(delta: float) -> void:
	_orbit += orbit_speed * delta
	var focus := _craft.get_global_transform_interpolated().origin + Vector3.UP * 0.7
	var heading := -_anchor.basis.z
	var around := heading.rotated(Vector3.UP, _orbit)
	# The craft sits in the middle, between the rider list and the stats.
	_camera.global_position = focus + around * 6.4 + Vector3.UP * 1.3
	_camera.look_at(focus + Vector3.DOWN * 0.3, Vector3.UP)


## Shows [param rider]: the craft in the rider's colours, and the rider's default craft with
## its stats.
func select(rider: RiderProfile) -> void:
	selected = rider
	rider.apply_colors(_craft.get_node_or_null(^"Model"))
	_name.text = rider.display_name.to_upper()
	_tagline.text = rider.tagline
	var craft := rider.default_craft
	_craft_name.text = "RIDES THE %s" % craft.display_name.to_upper() if craft != null else ""
	for i in _bars.size():
		_bars[i].value = craft.rating(CraftProfile.STATS[i]) if craft != null else 3.0


## Starts the race with the selected rider.
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
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var title := MenuStyle.label("CHOOSE YOUR RIDER", 76, MenuStyle.YELLOW)
	root.add_child(title)
	title.position = Vector2(72, 44)
	var mode := MenuStyle.label(Game.mode_name(), 32, MenuStyle.CYAN)
	root.add_child(mode)
	mode.position = Vector2(80, 150)

	# Left: the riders.
	var list := VBoxContainer.new()
	list.name = "Riders"
	list.add_theme_constant_override(&"separation", 18)
	root.add_child(list)
	list.position = Vector2(80, 230)
	for rider in Game.riders:
		var button := MenuStyle.button(rider.display_name.to_upper(), 46, Vector2(360, 86))
		button.name = rider.display_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_entered.connect(select.bind(rider))
		button.mouse_entered.connect(button.grab_focus)
		button.pressed.connect(confirm)
		list.add_child(button)
		_buttons.append(button)
	for i in _buttons.size():
		_buttons[i].focus_neighbor_top = _buttons[i - 1].get_path()
		_buttons[i].focus_neighbor_bottom = _buttons[(i + 1) % _buttons.size()].get_path()
		_buttons[i].focus_neighbor_left = _buttons[i].get_path()
		_buttons[i].focus_neighbor_right = _buttons[i].get_path()

	# Right: the selected rider's name, line and stats.
	var panel := MenuStyle.panel(48, 30)
	panel.name = "Stats"
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position.x -= 64
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	panel.add_child(column)
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
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 20)
		var stat := MenuStyle.label(CraftProfile.STAT_LABELS[i], 28, MenuStyle.WHITE)
		stat.custom_minimum_size = Vector2(230, 0)
		row.add_child(stat)
		var bar := StatBar.new()
		bar.custom_minimum_size = Vector2(270, 30)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		_bars.append(bar)
		column.add_child(row)

	var hint := MenuStyle.label("UP / DOWN: CHOOSE     ENTER / A: SELECT     ESC / B: BACK", 28, MenuStyle.DIM)
	root.add_child(hint)
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.position.y -= 40
