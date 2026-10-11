@tool
class_name Pier
extends StaticBody3D
## A wooden pier: a plank deck on rows of piles, solid from the seabed to the deck so craft
## can't pass under it. Built from code. The node's origin is at the water's rest level at
## the landward end; the pier runs along its -Z axis.

@export_range(2.0, 200.0, 0.1, "suffix:m") var length: float = 30.0:
	set(value):
		length = value
		_queue_build()
@export_range(1.0, 20.0, 0.1, "suffix:m") var width: float = 4.0:
	set(value):
		width = value
		_queue_build()
## Height of the deck above the water's rest level.
@export_range(0.2, 6.0, 0.01, "suffix:m") var deck_height: float = 1.6:
	set(value):
		deck_height = value
		_queue_build()
## Lamp posts along each side, this far apart (0 for none).
@export_range(0.0, 60.0, 0.1, "suffix:m") var lamp_spacing: float = 0.0:
	set(value):
		lamp_spacing = value
		_queue_build()

var _build_queued := false


func _ready() -> void:
	collision_layer = PhysicsLayers.SCENERY
	collision_mask = 0
	_build()


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child in get_children(true):
		if child.has_meta(&"pier_part"):
			child.free()
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.2)
	wood.roughness = 0.85
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.22, 0.16, 0.11)
	dark.roughness = 0.9
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(width, 0.3, length)
	deck_mesh.material = wood
	deck.mesh = deck_mesh
	deck.position = Vector3(0.0, deck_height, -length * 0.5)
	_add(deck)
	var piles := maxi(int(length / 4.0), 1)
	for i in piles + 1:
		for side in [-1.0, 1.0]:
			var pile := MeshInstance3D.new()
			var pile_mesh := CylinderMesh.new()
			pile_mesh.top_radius = 0.18
			pile_mesh.bottom_radius = 0.18
			pile_mesh.height = deck_height + 6.0
			pile_mesh.radial_segments = 6
			pile_mesh.material = dark
			pile.mesh = pile_mesh
			pile.position = Vector3(side * (width * 0.5 - 0.15), (deck_height - 6.0) * 0.5, -length * i / piles)
			_add(pile)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, deck_height + 6.15, length)
	shape.shape = box
	shape.position = Vector3(0.0, (deck_height + 0.15 - 6.0) * 0.5, -length * 0.5)
	_add(shape)
	if lamp_spacing > 0.0:
		var count := maxi(int(length / lamp_spacing), 1)
		for i in count:
			var lamp := LampPost.new()
			lamp.position = Vector3((width * 0.5 - 0.3) * (1.0 if i % 2 == 0 else -1.0), deck_height + 0.15,
					-lamp_spacing * (i + 0.5))
			_add(lamp)


func _add(node: Node3D) -> void:
	node.set_meta(&"pier_part", true)
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers = 1
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
