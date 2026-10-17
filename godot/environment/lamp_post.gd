@tool
class_name LampPost
extends Node3D
## A harbour lamp: [member model], a post with a lantern that glows in the light's colour,
## and an omni light. Place it on a pier or a breakwater.

@export_range(1.0, 12.0, 0.1, "suffix:m") var height: float = 4.5:
	set(value):
		height = value
		_queue_build()
@export var light_color: Color = Color(1.0, 0.78, 0.45):
	set(value):
		light_color = value
		_queue_build()
@export_range(0.0, 16.0, 0.1) var light_energy: float = 3.0:
	set(value):
		light_energy = value
		_queue_build()
@export_range(1.0, 60.0, 0.1, "suffix:m") var light_range: float = 20.0:
	set(value):
		light_range = value
		_queue_build()
## The lamp's model: kiln's (art/models/harbor/lamp_post.py), scaled to [member height]. Its
## Lamp material glows in [member light_color], and the light goes at its Light marker.
@export var model: PackedScene = preload("res://assets/models/harbor/lamp_post.glb"):
	set(value):
		model = value
		_queue_build()

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
		if child.has_meta(&"lamp_part"):
			child.free()
	var light_at := Vector3(0.0, height + 0.1, 0.0)
	if model != null:
		var drawn := SceneryModel.add(self, model, &"lamp_part")
		# Scaled so the top of its post (its PostTop marker) is at the height.
		drawn.scale = Vector3.ONE * height / SceneryModel.point(drawn, "PostTop").y
		SceneryModel.paint(drawn, "Lamp", light_color, light_color, 4.0)
		for mesh in SceneryModel.meshes(drawn):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		light_at = drawn.scale * (drawn.get_node("Light") as Node3D).position
	var light := OmniLight3D.new()
	light.light_color = light_color
	light.light_energy = light_energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.position = light_at
	_add(light)


func _add(node: Node3D) -> void:
	node.set_meta(&"lamp_part", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
