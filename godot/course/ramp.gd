@tool
class_name Ramp
extends StaticBody3D
## A floating jump ramp built from code: a wedge whose surface rises from under the water
## to a lip above it, with striped panels and posts. Racers ride up it on their speed (the
## jet has no water to push against on the ramp) and fly off the lip.
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
## Number of coloured bands across the slope.
@export_range(1, 20, 1) var stripes: int = 6:
	set(value):
		stripes = value
		_queue_build()
@export var stripe_color_a: Color = Color(0.98, 0.32, 0.04):
	set(value):
		stripe_color_a = value
		_queue_build()
@export var stripe_color_b: Color = Color(0.97, 0.96, 0.92):
	set(value):
		stripe_color_b = value
		_queue_build()
@export var side_color: Color = Color(0.12, 0.28, 0.62):
	set(value):
		side_color = value
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

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	# Slope, in bands of alternating colour.
	for s in stripes:
		var t0 := float(s) / stripes
		var t1 := float(s + 1) / stripes
		var color := stripe_color_a if s % 2 == 0 else stripe_color_b
		_quad(vertices, normals, colors, front_l.lerp(lip_l, t0), front_r.lerp(lip_r, t0),
				front_r.lerp(lip_r, t1), front_l.lerp(lip_l, t1), color)
	# A white lip edge so the jump point reads from far away.
	var trim := Vector3(0.0, 0.08, 0.0)
	_quad(vertices, normals, colors, lip_l - Vector3(0, 0, -0.01), lip_r - Vector3(0, 0, -0.01),
			lip_r + trim + Vector3(0, 0, -0.3), lip_l + trim + Vector3(0, 0, -0.3), stripe_color_b)
	# Sides, back and front.
	_quad(vertices, normals, colors, front_base_l, front_l, lip_l, back_base_l, side_color)
	_quad(vertices, normals, colors, front_base_r, back_base_r, lip_r, front_r, side_color)
	_quad(vertices, normals, colors, back_base_l, lip_l, lip_r, back_base_r, side_color.darkened(0.2))
	_quad(vertices, normals, colors, front_base_l, front_base_r, front_r, front_l, side_color.darkened(0.2))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.7
	mesh.surface_set_material(0, material)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	_add_part(mesh_instance)

	# Posts under the lip, down into the water.
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.18
	post_mesh.bottom_radius = 0.18
	post_mesh.height = top - base + 4.0
	post_mesh.radial_segments = 8
	var post_material := StandardMaterial3D.new()
	post_material.albedo_color = side_color.darkened(0.45)
	post_material.roughness = 0.8
	post_mesh.material = post_material
	for x in [-hw + 0.3, hw - 0.3]:
		var post := MeshInstance3D.new()
		post.mesh = post_mesh
		# Under the lip: the post's top stops just below the slope there.
		post.position = Vector3(x, (top + base - 4.0) * 0.5 - 0.3, -hl + 0.45)
		_add_part(post)

	var shape := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([front_l, front_r, lip_l, lip_r, front_base_l, front_base_r,
			back_base_l, back_base_r])
	shape.shape = hull
	_add_part(shape)


## Adds a flat quad a-b-c-d; the corners go counter-clockwise seen from the side it faces.
func _quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal := (b - a).cross(c - a).normalized()
	vertices.append_array(PackedVector3Array([a, c, b, a, d, c]))
	for k in 6:
		normals.append(normal)
		colors.append(color)


func _add_part(node: Node3D) -> void:
	node.set_meta(&"ramp_part", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
