@tool
class_name HarborBuilding
extends Node3D
## A low-poly harbour building for the shore: a box with a pitched roof and rows of windows
## that glow at night. Built from code; any child scene named "Model" can replace it.

@export var size: Vector3 = Vector3(10.0, 6.0, 8.0):
	set(value):
		size = value
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
@export var building_seed: int = 1:
	set(value):
		building_seed = value
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
		if child.has_meta(&"building_part"):
			child.free()
	if get_node_or_null(^"Model") != null:
		return
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(wall_color, Color.BLACK)
	body.mesh = box
	body.position.y = size.y * 0.5
	_add(body)
	var roof := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(size.x + 0.6, size.y * 0.35, size.z + 0.6)
	prism.material = _material(roof_color, Color.BLACK)
	roof.mesh = prism
	roof.position.y = size.y + size.y * 0.175
	_add(roof)
	# Windows: a few lit and a few dark on each long face.
	var rng := RandomNumberGenerator.new()
	rng.seed = building_seed
	var lit := _material(window_glow, window_glow * 3.0) if window_glow != Color.BLACK else _material(Color(0.15, 0.2, 0.3), Color.BLACK)
	var dark := _material(Color(0.08, 0.1, 0.14), Color.BLACK)
	var columns := maxi(int(size.x / 2.5), 1)
	var rows := maxi(int(size.y / 2.6), 1)
	for face in [-1.0, 1.0]:
		for r in rows:
			for c in columns:
				var window := MeshInstance3D.new()
				var pane := BoxMesh.new()
				pane.size = Vector3(1.0, 1.2, 0.08)
				pane.material = lit if rng.randf() < 0.55 else dark
				window.mesh = pane
				window.position = Vector3((c + 0.5) / columns * size.x - size.x * 0.5, 1.6 + r * 2.6, face * (size.z * 0.5 + 0.03))
				_add(window)


func _add(node: MeshInstance3D) -> void:
	node.set_meta(&"building_part", true)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(node, false, Node.INTERNAL_MODE_FRONT)


func _material(albedo: Color, emission: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.8
	if emission != Color.BLACK:
		material.emission_enabled = true
		material.emission = emission
	return material
