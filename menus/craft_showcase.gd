class_name CraftShowcase
extends Node3D
## The base of the rider select and craft select screens: a course behind, one craft floating
## on the water in a rider's colours ([method show_craft]) with the camera circling it, a list
## of choices down the left and a panel on the right. A screen that extends it calls
## [code]super()[/code] in [method _ready], then builds its UI with [method _add_ui],
## [method _add_choice], [method _link_focus], [method _add_panel] and [method _add_stat_row].

## The water and scenery behind the menu.
@export var backdrop_scene: PackedScene = preload("res://levels/gull_cove.tscn")
## How fast the camera circles the craft, in radians per second.
@export var orbit_speed: float = 0.18

## The scene shown for a craft with no scene of its own, or for no craft.
const DEFAULT_CRAFT := preload("res://jetski/jetski.tscn")

## The list's buttons, top to bottom.
var _buttons: Array[Button] = []
var _camera: Camera3D
var _craft: JetSki
var _anchor := Transform3D.IDENTITY
var _orbit := 0.6


func _ready() -> void:
	var backdrop := backdrop_scene.instantiate()
	add_child(backdrop)
	move_child(backdrop, 0)
	var course := backdrop as Course
	_anchor = course.grid_transform(1, 4) if course != null else Transform3D.IDENTITY
	_camera = Camera3D.new()
	# Moved in _process.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.fov = 55.0
	_camera.far = 6000.0
	add_child(_camera)
	_camera.make_current()


func _process(delta: float) -> void:
	if _craft == null:
		return
	_orbit += orbit_speed * delta
	var focus := _craft.get_global_transform_interpolated().origin + Vector3.UP * 0.7
	var heading := -_anchor.basis.z
	var around := heading.rotated(Vector3.UP, _orbit)
	# The craft sits in the middle, between the list and the panel.
	_camera.global_position = focus + around * 6.4 + Vector3.UP * 1.3
	_camera.look_at(focus + Vector3.DOWN * 0.3, Vector3.UP)


## Puts [param craft]'s scene on the water ([constant DEFAULT_CRAFT] when it has none) in
## [param rider]'s colours. The craft already there stays when it comes from the same scene.
func show_craft(craft: CraftProfile, rider: RiderProfile) -> void:
	var scene := craft.scene if craft != null and craft.scene != null else DEFAULT_CRAFT
	if _craft == null or _craft.scene_file_path != scene.resource_path:
		if _craft != null:
			remove_child(_craft)
			_craft.queue_free()
		_craft = scene.instantiate() as JetSki
		_craft.name = "Craft"
		_craft.transform = _anchor
		_craft.crashes_enabled = false
		add_child(_craft)
		_craft.hold(_anchor)
	if rider != null:
		rider.apply_colors(_craft.get_node_or_null(^"Model"))


## Adds the screen's UI layer with [param title] and the mode at the top left and
## [param hint] at the bottom. Returns the full-screen control that holds them, for the rest.
func _add_ui(title: String, hint: String) -> Control:
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var heading := MenuStyle.label(title, 76, MenuStyle.YELLOW)
	root.add_child(heading)
	heading.position = Vector2(72, 44)
	var mode := MenuStyle.label(Game.mode_name(), 32, MenuStyle.CYAN)
	root.add_child(mode)
	mode.position = Vector2(80, 150)

	var list := VBoxContainer.new()
	MenuStyle.hover_after_layout(list)
	list.name = "List"
	list.add_theme_constant_override(&"separation", 18)
	root.add_child(list)
	list.position = Vector2(80, 230)

	var footer := MenuStyle.label(hint, 28, MenuStyle.DIM)
	root.add_child(footer)
	footer.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	footer.grow_horizontal = Control.GROW_DIRECTION_BOTH
	footer.grow_vertical = Control.GROW_DIRECTION_BEGIN
	footer.position.y -= 40
	return root


## Adds a button showing [param text] to the list down the left, named [param node_name].
## Moving the mouse over it focuses it. Call [method _link_focus] after the last one.
func _add_choice(root: Control, text: String, node_name: String) -> Button:
	var button := MenuStyle.button(text, 46, Vector2(400, 86))
	button.name = node_name
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	MenuStyle.focus_on_hover(button)
	root.get_node(^"List").add_child(button)
	_buttons.append(button)
	return button


## Makes up and down move through the list, wrapping round at either end, and left and
## right stay put.
func _link_focus() -> void:
	for i in _buttons.size():
		_buttons[i].focus_neighbor_top = _buttons[i - 1].get_path()
		_buttons[i].focus_neighbor_bottom = _buttons[(i + 1) % _buttons.size()].get_path()
		_buttons[i].focus_neighbor_left = _buttons[i].get_path()
		_buttons[i].focus_neighbor_right = _buttons[i].get_path()


## Adds the panel on the right. Returns the column to fill.
func _add_panel(root: Control) -> VBoxContainer:
	var panel := MenuStyle.panel(48, 30)
	panel.name = "Panel"
	root.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.position.x -= 64
	var column := VBoxContainer.new()
	column.add_theme_constant_override(&"separation", 10)
	panel.add_child(column)
	return column


## Adds a row with [param text] and a [StatBar] to [param column]. Returns the bar.
func _add_stat_row(column: VBoxContainer, text: String) -> StatBar:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 20)
	var stat := MenuStyle.label(text, 28, MenuStyle.WHITE)
	stat.custom_minimum_size = Vector2(230, 0)
	row.add_child(stat)
	var bar := StatBar.new()
	bar.custom_minimum_size = Vector2(270, 30)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	column.add_child(row)
	return bar
