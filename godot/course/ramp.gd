@tool
class_name Ramp
extends StaticBody3D
## A floating jump ramp: a wedge whose surface rises from under the water to a lip above it.
## Racers ride up it on their speed (the jet has no water to push against on the ramp) and
## fly off the lip. The collision shape is built from [member width], [member length],
## [member bottom] and [member top]; [member model] is stretched so its slope lies on it.
##
## The node sits at the water's rest level; the ramp rises toward its local -Z. Start
## [member bottom] below the lowest wave trough so a craft always meets the slope, never
## the leading edge.

## Width of the ramp, in meters.
@export_range(1.0, 30.0, 0.1, "suffix:m") var width: float = 7.0:
	set(value):
		width = value
		_queue_build()
## Length of the slope, measured horizontally.
@export_range(2.0, 40.0, 0.1, "suffix:m") var length: float = 12.0:
	set(value):
		length = value
		_queue_build()
## Height of the leading edge relative to the water's rest level (negative: under water).
@export_range(-6.0, 2.0, 0.01, "suffix:m") var bottom: float = -2.0:
	set(value):
		bottom = value
		_queue_build()
## Height of the lip.
@export_range(0.0, 8.0, 0.01, "suffix:m") var top: float = 1.8:
	set(value):
		top = value
		_queue_build()
## The ramp's model: kiln's (art/models/course/ramp.py), built as the default ramp and
## stretched to this one.
@export var model: PackedScene = preload("res://assets/models/course/ramp.glb"):
	set(value):
		model = value
		_queue_build()
## Friction of the slope. Low, so a craft keeps its speed up the ramp.
@export_range(0.0, 1.0, 0.01) var friction: float = 0.05

var _build_queued := false


func _ready() -> void:
	_build()
	if not Engine.is_editor_hint():
		collision_layer = PhysicsLayers.SCENERY
		collision_mask = 0
		var material := PhysicsMaterial.new()
		material.friction = friction
		physics_material_override = material


## Height of the slope's surface at local z (the leading edge is at +length/2).
func surface_height(local_z: float) -> float:
	var t := clampf((length * 0.5 - local_z) / length, 0.0, 1.0)
	return lerpf(bottom, top, t)


## The slope's angle, in degrees.
func slope_degrees() -> float:
	return rad_to_deg(atan2(top - bottom, length))


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child in get_children(true):
		if child.has_meta(&"ramp_part"):
			child.free()
	var hw := width * 0.5
	var hl := length * 0.5
	var base := bottom - 0.4
	# The wedge: front edge low at +Z, lip high at -Z, flat underside at `base`.
	var front_l := Vector3(-hw, bottom, hl)
	var front_r := Vector3(hw, bottom, hl)
	var lip_l := Vector3(-hw, top, -hl)
	var lip_r := Vector3(hw, top, -hl)
	var front_base_l := Vector3(-hw, base, hl)
	var front_base_r := Vector3(hw, base, hl)
	var back_base_l := Vector3(-hw, base, -hl)
	var back_base_r := Vector3(hw, base, -hl)

	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([front_l, front_r, lip_l, lip_r, front_base_l, front_base_r,
			back_base_l, back_base_r])
	shape.shape = hull
	_add_part(shape)
	if model != null:
		# Stretched so the model's slope runs from this ramp's front edge to its lip. The slope as
		# built runs between the right-hand ends of its front edge and lip, its markers.
		var drawn := SceneryModel.add(self, model, &"ramp_part")
		var front := SceneryModel.point(drawn, "SlopeFront")
		var lip := SceneryModel.point(drawn, "SlopeLip")
		var stretch := Vector3(width / (front.x * 2.0), (top - bottom) / (lip.y - front.y), length / (front.z - lip.z))
		drawn.transform = Transform3D(Basis.from_scale(stretch),
				Vector3(0.0, bottom - front.y * stretch.y, length * 0.5 - front.z * stretch.z))


func _add_part(node: Node3D) -> void:
	node.set_meta(&"ramp_part", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
