@tool
class_name Rock
extends StaticBody3D
## A low-poly rock built from code: a subdivided icosahedron pushed in and out by noise,
## flat shaded, with a convex collision shape. Different seeds give different rocks.

@export_range(0.2, 50.0, 0.1, "suffix:m") var radius: float = 3.0:
	set(value):
		radius = value
		_queue_build()
## Stretch along the vertical axis; above 1 for pillars, below 1 for flat boulders.
@export_range(0.2, 6.0, 0.01) var height_scale: float = 1.0:
	set(value):
		height_scale = value
		_queue_build()
## How lumpy the rock is, as a share of its radius.
@export_range(0.0, 0.6, 0.01) var roughness: float = 0.22:
	set(value):
		roughness = value
		_queue_build()
@export var rock_seed: int = 1:
	set(value):
		rock_seed = value
		_queue_build()
@export var color: Color = Color(0.5, 0.46, 0.41):
	set(value):
		color = value
		_queue_build()

var _mesh_instance: MeshInstance3D
var _collision: CollisionShape3D
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
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mesh"
		add_child(_mesh_instance, false, Node.INTERNAL_MODE_FRONT)
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "Shape"
		add_child(_collision, false, Node.INTERNAL_MODE_FRONT)

	var noise := FastNoiseLite.new()
	noise.seed = rock_seed
	noise.frequency = 0.9 / maxf(radius, 0.1)
	noise.fractal_octaves = 2
	var points := _icosphere(2)
	for i in points.size():
		var p := points[i]
		var lump := 1.0 + noise.get_noise_3dv(p * radius) * roughness * 2.0
		points[i] = Vector3(p.x * radius * lump, p.y * radius * height_scale * lump, p.z * radius * lump)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var faces := _ico_faces
	for f in range(0, faces.size(), 3):
		# The face list winds counter-clockwise seen from outside; Godot's front faces
		# wind clockwise, so emit each triangle as a, c, b.
		var a := points[faces[f]]
		var b := points[faces[f + 1]]
		var c := points[faces[f + 2]]
		var normal := (b - a).cross(c - a).normalized()
		var shade := color.darkened(0.12 * absf(noise.get_noise_3dv((a + b + c) * 3.0)))
		for p in [a, c, b]:
			vertices.append(p)
			normals.append(normal)
			colors.append(shade)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var built := ArrayMesh.new()
	built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	built.surface_set_material(0, material)
	_mesh_instance.mesh = built
	var hull := ConvexPolygonShape3D.new()
	hull.points = points
	_collision.shape = hull


static var _ico_faces := PackedInt32Array()


## Unit icosphere vertices, subdivided [param levels] times. Fills the shared face list.
static func _icosphere(levels: int) -> PackedVector3Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var verts: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in verts.size():
		verts[i] = verts[i].normalized()
	var faces: Array[int] = [
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	]
	for level in levels:
		var midpoints := {}
		var next: Array[int] = []
		for f in range(0, faces.size(), 3):
			var a := faces[f]
			var b := faces[f + 1]
			var c := faces[f + 2]
			var ab := _midpoint(verts, midpoints, a, b)
			var bc := _midpoint(verts, midpoints, b, c)
			var ca := _midpoint(verts, midpoints, c, a)
			next.append_array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca])
		faces = next
	_ico_faces = PackedInt32Array(faces)
	return PackedVector3Array(verts)


static func _midpoint(verts: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if cache.has(key):
		return cache[key]
	verts.append(((verts[a] + verts[b]) * 0.5).normalized())
	cache[key] = verts.size() - 1
	return verts.size() - 1
