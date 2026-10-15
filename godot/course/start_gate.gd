@tool
class_name StartGate
extends Node3D
## The start and finish arch, built from code: two striped pylons standing in the water
## and a banner across the course between them. Place it on the start line facing the
## direction of travel (-Z); the pylons stand [member span] apart, just outside the walls.

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
@export var pylon_color: Color = Color(0.93, 0.13, 0.10):
	set(value):
		pylon_color = value
		_queue_build()
@export var banner_color: Color = Color(0.10, 0.30, 0.80):
	set(value):
		banner_color = value
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
		if child.has_meta(&"gate_part"):
			child.free()
	var white := Color(0.97, 0.97, 0.95)
	var pylon_bottom := -4.0
	var pylon_height := height - pylon_bottom
	for side in [-1.0, 1.0]:
		var x: float = side * span * 0.5
		var body := StaticBody3D.new()
		body.position = Vector3(x, 0.0, 0.0)
		body.collision_layer = PhysicsLayers.SCENERY
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.6, pylon_height, 1.6)
		shape.shape = box
		shape.position = Vector3(0.0, pylon_bottom + pylon_height * 0.5, 0.0)
		body.add_child(shape)
		_add_part(body)
		# Pylon: bands of colour and white, so it reads as a marker.
		var bands := 7
		for b in bands:
			var band_height := pylon_height / bands
			var color := pylon_color if b % 2 == 0 else white
			body.add_child(_box(Vector3(1.6, band_height, 1.6),
					Vector3(0.0, pylon_bottom + band_height * (b + 0.5), 0.0), color))
		body.add_child(_box(Vector3(2.2, 0.4, 2.2), Vector3(0.0, height + 0.2, 0.0), white))
	# Banner and a chequered strip under it.
	var banner_height := 2.4
	_add_part(_box(Vector3(span, banner_height, 0.35), Vector3(0.0, height - banner_height * 0.5, 0.0), banner_color))
	var squares := int(span / 1.2)
	var square := span / squares
	for row in 2:
		for i in squares:
			var color := white if (i + row) % 2 == 0 else Color(0.08, 0.08, 0.1)
			_add_part(_box(Vector3(square, 0.6, 0.38),
					Vector3(-span * 0.5 + square * (i + 0.5), height - banner_height - 0.3 - row * 0.6, 0.0), color))
	for facing in [0.0, PI]:
		var label := Label3D.new()
		label.text = banner_text
		label.font_size = 160
		label.outline_size = 0
		label.pixel_size = 0.012
		label.modulate = white
		label.double_sided = false
		label.shaded = false
		label.rotation = Vector3(0.0, facing, 0.0)
		label.position = Vector3(0.0, height - banner_height * 0.5, 0.0) \
				+ Basis(Vector3.UP, facing) * Vector3(0.0, 0.0, 0.2)
		_add_part(label)


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	return node


func _add_part(node: Node3D) -> void:
	node.set_meta(&"gate_part", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
