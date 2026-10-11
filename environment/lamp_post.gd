@tool
class_name LampPost
extends Node3D
## A harbour lamp: a post with a glowing head and an omni light. Built from code; any child
## scene named "Model" can replace the meshes. Place it on a pier or a breakwater.

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
	if get_node_or_null(^"Model") == null:
		var post := MeshInstance3D.new()
		var post_mesh := CylinderMesh.new()
		post_mesh.top_radius = 0.07
		post_mesh.bottom_radius = 0.1
		post_mesh.height = height
		post_mesh.radial_segments = 6
		post_mesh.material = _material(Color(0.12, 0.13, 0.15), Color.BLACK)
		post.mesh = post_mesh
		post.position.y = height * 0.5
		_add(post)
		var head := MeshInstance3D.new()
		var head_mesh := SphereMesh.new()
		head_mesh.radius = 0.22
		head_mesh.height = 0.44
		head_mesh.radial_segments = 8
		head_mesh.rings = 4
		head_mesh.material = _material(light_color, light_color * 4.0)
		head.mesh = head_mesh
		head.position.y = height + 0.1
		_add(head)
	var light := OmniLight3D.new()
	light.light_color = light_color
	light.light_energy = light_energy
	light.omni_range = light_range
	light.omni_attenuation = 1.4
	light.position.y = height + 0.1
	_add(light)


func _add(node: Node3D) -> void:
	node.set_meta(&"lamp_part", true)
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node, false, Node.INTERNAL_MODE_FRONT)


func _material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.6
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
	return material
