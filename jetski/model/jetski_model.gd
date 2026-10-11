@tool
class_name JetSkiModel
extends Node3D
## Placeholder jet ski and rider built from code: a flat-shaded low-poly hull, a seat,
## handlebars, and a blocky rider whose body leans with the controls.
##
## [JetSki] calls [method set_pose] every frame. A replacement model only needs to be a
## Node3D scene, optionally with the same method; the physics never reads the model.
## Model space matches the craft: -Z forward, +Y up, origin on the keel at mid-length.

@export_group("Colours")
@export var hull_color: Color = Color(0.98, 0.78, 0.10):
	set(value):
		hull_color = value
		_queue_build()
@export var trim_color: Color = Color(0.10, 0.35, 0.85):
	set(value):
		trim_color = value
		_queue_build()
@export var bottom_color: Color = Color(0.94, 0.95, 0.97):
	set(value):
		bottom_color = value
		_queue_build()
@export var deck_color: Color = Color(0.22, 0.24, 0.28):
	set(value):
		deck_color = value
		_queue_build()
@export var seat_color: Color = Color(0.08, 0.10, 0.16):
	set(value):
		seat_color = value
		_queue_build()
@export var suit_color: Color = Color(0.85, 0.12, 0.14):
	set(value):
		suit_color = value
		_queue_build()
@export var vest_color: Color = Color(1.0, 0.86, 0.1):
	set(value):
		vest_color = value
		_queue_build()
@export var helmet_color: Color = Color(0.95, 0.96, 1.0):
	set(value):
		helmet_color = value
		_queue_build()
@export var skin_color: Color = Color(0.86, 0.66, 0.5):
	set(value):
		skin_color = value
		_queue_build()

@export_group("Pose")
## How far the rider's body tips forward at full forward lean, and back at full back lean.
@export_range(0.0, 60.0, 0.1, "degrees") var lean_forward_angle: float = 28.0
@export_range(0.0, 60.0, 0.1, "degrees") var lean_back_angle: float = 22.0
## How far the body leans into a full-lock turn.
@export_range(0.0, 45.0, 0.1, "degrees") var turn_lean_angle: float = 16.0
## Handlebar rotation at full lock.
@export_range(0.0, 60.0, 0.1, "degrees") var bar_angle: float = 24.0
## How quickly the pose follows the controls, per second.
@export_range(0.1, 50.0, 0.1) var pose_response: float = 10.0

# Hull cross-sections from bow to stern: z, half width, keel height, chine height, deck height.
const STATIONS: Array[Vector4] = [
	Vector4(-1.50, 0.03, 0.40, 0.44),
	Vector4(-1.28, 0.26, 0.17, 0.30),
	Vector4(-0.92, 0.45, 0.05, 0.19),
	Vector4(-0.40, 0.55, 0.0, 0.15),
	Vector4(0.40, 0.56, 0.0, 0.14),
	Vector4(1.10, 0.54, 0.02, 0.14),
	Vector4(1.42, 0.50, 0.04, 0.15),
]
const DECK_HEIGHTS: Array[float] = [0.50, 0.60, 0.62, 0.58, 0.55, 0.52, 0.48]

var _steer := 0.0
var _lean := 0.0
var _airborne := 0.0
var _target_steer := 0.0
var _target_lean := 0.0
var _target_airborne := 0.0
var _build_queued := false

var _parts: Dictionary[StringName, MeshInstance3D] = {}
var _handlebar: Node3D


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	var blend := 1.0 - exp(-pose_response * delta)
	_steer = lerpf(_steer, _target_steer, blend)
	_lean = lerpf(_lean, _target_lean, blend)
	_airborne = lerpf(_airborne, _target_airborne, blend)
	_apply_pose()


## Sets the pose to blend toward: steer and lean from -1 to 1, throttle 0 to 1.
func set_pose(steer: float, lean: float, _throttle: float, airborne: bool) -> void:
	_target_steer = clampf(steer, -1.0, 1.0)
	_target_lean = clampf(lean, -1.0, 1.0)
	_target_airborne = 1.0 if airborne else 0.0


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child in get_children(true):
		if child.has_meta(&"model_part"):
			child.free()
	_parts.clear()

	var hull := MeshInstance3D.new()
	hull.mesh = _build_hull_mesh()
	_add_part(&"hull", hull)

	_add_box(&"seat", Vector3(0.40, 0.20, 0.95), Vector3(0.0, 0.66, 0.42), seat_color)
	_add_box(&"hood", Vector3(0.62, 0.22, 0.55), Vector3(0.0, 0.70, -0.62), hull_color.darkened(0.08))
	_add_box(&"column", Vector3(0.14, 0.34, 0.14), Vector3(0.0, 0.88, -0.48), deck_color)
	_add_box(&"footwell_left", Vector3(0.20, 0.03, 0.9), Vector3(-0.34, 0.50, 0.3), deck_color.darkened(0.3))
	_add_box(&"footwell_right", Vector3(0.20, 0.03, 0.9), Vector3(0.34, 0.50, 0.3), deck_color.darkened(0.3))
	_add_box(&"nozzle", Vector3(0.22, 0.14, 0.12), Vector3(0.0, 0.14, 1.46), deck_color.darkened(0.4))

	_handlebar = Node3D.new()
	_handlebar.position = Vector3(0.0, 1.03, -0.42)
	_handlebar.set_meta(&"model_part", true)
	add_child(_handlebar, false, Node.INTERNAL_MODE_FRONT)
	var bar := MeshInstance3D.new()
	bar.mesh = _box_mesh(Vector3(0.74, 0.05, 0.05), deck_color.darkened(0.5))
	bar.set_meta(&"model_part", true)
	_handlebar.add_child(bar, false, Node.INTERNAL_MODE_FRONT)

	# Rider: boxes between joints, placed every frame by _apply_pose().
	for side in [&"left", &"right"]:
		_add_box(StringName("shin_" + side), Vector3(0.13, 1.0, 0.14), Vector3.ZERO, suit_color.darkened(0.2))
		_add_box(StringName("thigh_" + side), Vector3(0.16, 1.0, 0.17), Vector3.ZERO, suit_color)
		_add_box(StringName("upper_arm_" + side), Vector3(0.11, 1.0, 0.11), Vector3.ZERO, suit_color)
		_add_box(StringName("forearm_" + side), Vector3(0.09, 1.0, 0.09), Vector3.ZERO, suit_color.darkened(0.15))
		_add_box(StringName("boot_" + side), Vector3(0.13, 0.1, 0.28), Vector3.ZERO, deck_color.darkened(0.5))
		_add_box(StringName("glove_" + side), Vector3(0.09, 0.09, 0.11), Vector3.ZERO, deck_color.darkened(0.5))
	_add_box(&"torso", Vector3(0.36, 1.0, 0.22), Vector3.ZERO, suit_color)
	_add_box(&"vest", Vector3(0.42, 1.0, 0.27), Vector3.ZERO, vest_color)
	_add_sphere(&"head", 0.11, skin_color)
	_add_sphere(&"helmet", 0.135, helmet_color)
	_add_box(&"visor", Vector3(0.2, 0.07, 0.04), Vector3.ZERO, Color(0.05, 0.08, 0.12))
	_apply_pose()


func _apply_pose() -> void:
	if _parts.is_empty():
		return
	if _handlebar != null:
		_handlebar.rotation = Vector3(0.0, -_steer * deg_to_rad(bar_angle), 0.0)

	var pitch := deg_to_rad(lean_forward_angle) * maxf(_lean, 0.0) - deg_to_rad(lean_back_angle) * maxf(-_lean, 0.0)
	var roll := _steer * deg_to_rad(turn_lean_angle)
	# The spine tips about the pelvis: forward for a forward lean, sideways into the turn.
	var spine := Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.FORWARD, roll)
	var crouch := 0.06 * maxf(_lean, 0.0) - 0.08 * _airborne
	var pelvis := Vector3(_steer * 0.05, 1.12 - crouch, 0.38 + 0.06 * maxf(_lean, 0.0))
	var chest := pelvis + spine * Vector3(0.0, 0.46, -0.24)
	var neck := pelvis + spine * Vector3(0.0, 0.62, -0.30)
	var head := pelvis + spine * Vector3(0.0, 0.74, -0.33)
	var shoulder_offset := spine * Vector3(0.21, 0.0, 0.0)

	_place_between(&"torso", pelvis, neck)
	_place_between(&"vest", pelvis + spine * Vector3(0.0, 0.16, -0.07), chest + spine * Vector3(0.0, 0.05, 0.0))
	_set_part(&"head", Transform3D(spine, head))
	_set_part(&"helmet", Transform3D(spine, head + spine * Vector3(0.0, 0.025, 0.01)))
	_set_part(&"visor", Transform3D(spine, head + spine * Vector3(0.0, 0.0, -0.13)))

	var bar_basis := Basis(Vector3.UP, -_steer * deg_to_rad(bar_angle))
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var tag := "left" if i == 0 else "right"
		var foot := Vector3(0.30 * side, 0.56, 0.30)
		var hip := pelvis + spine * Vector3(0.11 * side, 0.0, 0.0)
		var knee := (hip + foot) * 0.5 + Vector3(0.06 * side, 0.0, -0.24 - 0.05 * _airborne)
		var shoulder := chest + shoulder_offset * side
		var hand := Vector3(0.0, 1.03, -0.42) + bar_basis * Vector3(0.33 * side, 0.0, 0.0)
		var elbow := (shoulder + hand) * 0.5 + Vector3(0.12 * side, -0.06, 0.06)
		_place_between(StringName("thigh_" + tag), hip, knee)
		_place_between(StringName("shin_" + tag), knee, foot)
		_set_part(StringName("boot_" + tag), Transform3D(Basis.IDENTITY, foot + Vector3(0.0, -0.02, -0.05)))
		_place_between(StringName("upper_arm_" + tag), shoulder, elbow)
		_place_between(StringName("forearm_" + tag), elbow, hand)
		_set_part(StringName("glove_" + tag), Transform3D(bar_basis, hand))


## Stretches a unit-height box part between two points.
func _place_between(part: StringName, from: Vector3, to: Vector3) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 0.001:
		return
	var y := axis / length
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	_set_part(part, Transform3D(Basis(x, y * length, z), (from + to) * 0.5))


func _set_part(part: StringName, xform: Transform3D) -> void:
	var node: MeshInstance3D = _parts.get(part)
	if node != null:
		node.transform = xform


func _add_part(part: StringName, node: MeshInstance3D) -> void:
	node.name = String(part)
	node.set_meta(&"model_part", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
	_parts[part] = node


func _add_box(part: StringName, size: Vector3, at: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _box_mesh(size, color)
	node.position = at
	_add_part(part, node)


func _add_sphere(part: StringName, radius: float, color: Color) -> void:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	sphere.material = _material(color)
	node.mesh = sphere
	_add_part(part, node)


func _box_mesh(size: Vector3, color: Color) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	return box


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	return material


## Builds the hull from its cross-sections, flat shaded, coloured by band.
func _build_hull_mesh() -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	for s in STATIONS.size():
		var st := STATIONS[s]
		var z := st.x
		var w := st.y
		var deck := DECK_HEIGHTS[s]
		rings.append(PackedVector3Array([
			Vector3(-w * 0.80, deck, z),          # deck edge, left
			Vector3(-w, deck - 0.07, z),          # gunwale, left
			Vector3(-w * 0.97, st.w, z),          # chine, left
			Vector3(0.0, st.z, z),                # keel
			Vector3(w * 0.97, st.w, z),           # chine, right
			Vector3(w, deck - 0.07, z),           # gunwale, right
			Vector3(w * 0.80, deck, z),           # deck edge, right
			Vector3(0.0, deck + 0.025, z),        # deck centre
		]))
	# Colour of each band between consecutive ring points.
	var band_colors: Array[Color] = [trim_color, hull_color, bottom_color, bottom_color,
			hull_color, trim_color, deck_color, deck_color]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for s in rings.size() - 1:
		var a := rings[s]
		var b := rings[s + 1]
		var centre := Vector3(0.0, 0.3, (a[0].z + b[0].z) * 0.5)
		for k in 8:
			var k2 := (k + 1) % 8
			_add_triangle(vertices, normals, colors, a[k], b[k], b[k2], centre, band_colors[k])
			_add_triangle(vertices, normals, colors, a[k], b[k2], a[k2], centre, band_colors[k])
	# Transom: close the stern with a fan.
	var stern := rings[rings.size() - 1]
	var stern_centre := Vector3(0.0, 0.3, stern[0].z)
	var outward := stern_centre - Vector3(0.0, 0.3, 0.0)
	for k in 8:
		_add_triangle(vertices, normals, colors, stern_centre, stern[k], stern[(k + 1) % 8],
				stern_centre - outward, deck_color.darkened(0.2))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.6
	mesh.surface_set_material(0, material)
	return mesh


## Adds a flat-shaded triangle facing away from [param inside].
func _add_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, inside: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-10:
		return
	normal = normal.normalized()
	if normal.dot((a + b + c) / 3.0 - inside) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	vertices.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))
	colors.append_array(PackedColorArray([color, color, color]))
