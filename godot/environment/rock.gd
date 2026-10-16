@tool
class_name Rock
extends StaticBody3D
## A rock: [member model] fitted to [member radius] across and [member height_scale] times
## that up, around the node's origin, and turned by [member rock_seed], with a convex
## collision shape round what is drawn.

@export_range(0.2, 50.0, 0.1, "suffix:m") var radius: float = 3.0:
	set(value):
		radius = value
		_queue_build()
## Stretch along the vertical axis; above 1 for pillars, below 1 for flat boulders.
@export_range(0.2, 6.0, 0.01) var height_scale: float = 1.0:
	set(value):
		height_scale = value
		_queue_build()
## Turns the rock about its vertical axis, so rocks of the same model differ.
@export var rock_seed: int = 1:
	set(value):
		rock_seed = value
		_queue_build()
## The rock's model: one of kiln's (art/models/rocks/), drawn in kiln's rock texture. Pick one
## shaped like the rock (a slab for a flat rock, a pillar for a tall one) so the fit stretches
## it little.
@export var model: PackedScene = preload("res://assets/models/rocks/boulder_a.glb"):
	set(value):
		model = value
		_queue_build()

## How far computer riders keep from a rock's centre, as a share of its radius: room for
## its lumps and to spare.
const AVOID_SCALE := 1.44

var _build_queued := false


func _ready() -> void:
	_build()


## How far computer riders keep from the rock's centre (see [method Course.obstacles]).
func avoid_radius() -> float:
	return radius * AVOID_SCALE


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child in get_children(true):
		if child.has_meta(&"rock_part"):
			child.free()
	if model == null:
		return
	var drawn := SceneryModel.add(self, model, &"rock_part")
	drawn.rotation.y = rock_seed * 2.39996
	# Fit the turned model's box to the rock's: radius across, radius * height_scale up.
	var unique := {}
	for point in SceneryModel.points(drawn):
		unique[point] = true
	var points := PackedVector3Array(unique.keys())
	var low := points[0]
	var high := points[0]
	for point in points:
		low = low.min(point)
		high = high.max(point)
	var centre := (low + high) * 0.5
	var stretch := Vector3(radius, radius * height_scale, radius) / ((high - low) * 0.5)
	drawn.transform = Transform3D(Basis.from_scale(stretch) * drawn.basis, -centre * stretch)
	for i in points.size():
		points[i] = (points[i] - centre) * stretch
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	shape.shape = hull
	shape.set_meta(&"rock_part", true)
	add_child(shape, false, Node.INTERNAL_MODE_FRONT)
