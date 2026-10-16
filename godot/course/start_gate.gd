@tool
class_name StartGate
extends Node3D
## The start and finish arch: two banded pylons standing in the water and a banner across the
## course between them, drawn by [member model], with the gate's name on the banner. Place it
## on the start line facing the direction of travel (-Z); the pylons stand [member span]
## apart, just outside the walls.

@export_range(4.0, 120.0, 0.1, "suffix:m") var span: float = 46.0:
	set(value):
		span = value
		_queue_build()
## Height of the banner's top edge above the water.
@export_range(3.0, 30.0, 0.1, "suffix:m") var height: float = 11.0:
	set(value):
		height = value
		_queue_build()
@export var banner_text: String = "WATERLINE":
	set(value):
		banner_text = value
		_queue_build()
## The gate's model: kiln's (art/models/course/start_gate.py). Its PylonLeft and PylonRight go
## to either side and stretch to the height, and its Banner goes to the top and stretches
## across.
@export var model: PackedScene = preload("res://assets/models/course/start_gate.glb"):
	set(value):
		model = value
		_queue_build()

## The model as built: the span, the banner's top and the pylons' feet.
const MODEL_SPAN := 46.0
const MODEL_HEIGHT := 13.0
const PYLON_BOTTOM := -4.0
## The pylons' width and the banner's height.
const PYLON_WIDTH := 1.6
const BANNER_HEIGHT := 2.4

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
		if child.has_meta(&"gate_part"):
			child.free()
	var pylon_height := height - PYLON_BOTTOM
	for side in [-1.0, 1.0]:
		var body := StaticBody3D.new()
		body.position = Vector3(side * span * 0.5, 0.0, 0.0)
		body.collision_layer = PhysicsLayers.SCENERY
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(PYLON_WIDTH, pylon_height, PYLON_WIDTH)
		shape.shape = box
		shape.position = Vector3(0.0, PYLON_BOTTOM + pylon_height * 0.5, 0.0)
		body.add_child(shape)
		_add_part(body)
	if model != null:
		var drawn := SceneryModel.add(self, model, &"gate_part")
		for side in [-1.0, 1.0]:
			var pylon := drawn.get_node("PylonLeft" if side < 0.0 else "PylonRight") as Node3D
			pylon.position = Vector3(side * span * 0.5, PYLON_BOTTOM, 0.0)
			pylon.scale = Vector3(1.0, pylon_height / (MODEL_HEIGHT - PYLON_BOTTOM), 1.0)
		var banner := drawn.get_node("Banner") as Node3D
		banner.position = Vector3(0.0, height - BANNER_HEIGHT * 0.5, 0.0)
		banner.scale = Vector3(span / MODEL_SPAN, 1.0, 1.0)
	for facing in [0.0, PI]:
		var label := Label3D.new()
		label.text = banner_text
		label.font_size = 160
		label.outline_size = 0
		label.pixel_size = 0.012
		label.modulate = Color(0.97, 0.97, 0.95)
		label.double_sided = false
		label.shaded = false
		label.rotation = Vector3(0.0, facing, 0.0)
		label.position = Vector3(0.0, height - BANNER_HEIGHT * 0.5, 0.0) \
				+ Basis(Vector3.UP, facing) * Vector3(0.0, 0.0, 0.2)
		_add_part(label)


func _add_part(node: Node3D) -> void:
	node.set_meta(&"gate_part", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
