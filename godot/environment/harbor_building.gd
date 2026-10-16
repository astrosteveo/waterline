@tool
class_name HarborBuilding
extends Node3D
## A harbour building for the shore: [member model], in its own wall and roof colours, with
## windows that glow at night.

## The building's model: one of kiln's (art/models/harbor/: boathouse, house_square,
## house_tall, office, shed, warehouse). Its Wall, Roof and Window materials take the colours
## below; its WindowDark panes stay dark, as rooms nobody is in.
@export var model: PackedScene = preload("res://assets/models/harbor/house_square.glb"):
	set(value):
		model = value
		_queue_build()
@export var wall_color: Color = Color(0.85, 0.8, 0.7):
	set(value):
		wall_color = value
		_queue_build()
@export var roof_color: Color = Color(0.55, 0.2, 0.15):
	set(value):
		roof_color = value
		_queue_build()
## Window glow; black for unlit windows (daytime).
@export var window_glow: Color = Color(1.0, 0.75, 0.4):
	set(value):
		window_glow = value
		_queue_build()

## The colour of a pane with no light behind it.
const DARK_GLASS := Color(0.15, 0.2, 0.3)

var _build_queued := false


func _ready() -> void:
	_build()


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child in get_children(true):
		if child.has_meta(&"building_part"):
			child.free()
	if model == null:
		return
	var drawn := SceneryModel.add(self, model, &"building_part")
	SceneryModel.paint(drawn, "Wall", wall_color)
	SceneryModel.paint(drawn, "Roof", roof_color)
	if window_glow != Color.BLACK:
		SceneryModel.paint(drawn, "Window", window_glow, window_glow, 3.0)
	else:
		SceneryModel.paint(drawn, "Window", DARK_GLASS)
