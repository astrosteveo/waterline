@tool
class_name Pier
extends StaticBody3D
## A wooden pier: [member model], a plank deck on rows of piles, with a collision box solid
## from the seabed to the deck so craft can't pass under it. The node's origin is at the
## water's rest level at the landward end; the pier runs along its -Z axis.

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
## The pier's model: kiln's (art/models/harbor/pier.py), built as the default pier and
## stretched to this one, its piles' feet staying 6 m down.
@export var model: PackedScene = preload("res://assets/models/harbor/pier.glb"):
	set(value):
		model = value
		_queue_build()

## How far down the piles reach, below the water's rest level: the collision box's foot, where
## the model's piles' feet go.
const PILE_DEPTH := 6.0
## Half the deck's thickness: its top, the collision box's, is this far above [member deck_height].
const DECK_HALF := 0.15

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
	if model != null:
		# Stretched so the model's deck, as built (its DeckEnd marker, the far corner of the
		# deck's top), is this pier's, and its piles' feet (its PileFoot marker) stay down at
		# PILE_DEPTH.
		var drawn := SceneryModel.add(self, model, &"pier_part")
		var deck_end := SceneryModel.point(drawn, "DeckEnd")
		var pile_foot := SceneryModel.point(drawn, "PileFoot").y
		var stretch := Vector3(width / (deck_end.x * 2.0),
				(deck_height + DECK_HALF + PILE_DEPTH) / (deck_end.y - pile_foot), length / -deck_end.z)
		drawn.transform = Transform3D(Basis.from_scale(stretch), Vector3(0.0, -PILE_DEPTH - pile_foot * stretch.y, 0.0))
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, deck_height + DECK_HALF + PILE_DEPTH, length)
	shape.shape = box
	shape.position = Vector3(0.0, (deck_height + DECK_HALF - PILE_DEPTH) * 0.5, -length * 0.5)
	_add(shape)
	if lamp_spacing > 0.0:
		var count := maxi(int(length / lamp_spacing), 1)
		for i in count:
			var lamp := LampPost.new()
			# Inside the kerbs along the edges.
			lamp.position = Vector3((width * 0.5 - 0.45) * (1.0 if i % 2 == 0 else -1.0), deck_height + DECK_HALF,
					-lamp_spacing * (i + 0.5))
			_add(lamp)


func _add(node: Node3D) -> void:
	node.set_meta(&"pier_part", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
