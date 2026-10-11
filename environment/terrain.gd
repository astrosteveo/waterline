@tool
class_name Terrain
extends MeshInstance3D
## Seabed and islands built from code: a flat-shaded height field coloured by height and
## slope, with a matching collision shape.
##
## Islands and shoals are bumps on a noisy sea floor. Each entry of [member islands] is
## Vector4(centre x, centre z, radius, peak height); a negative peak makes an underwater
## sandbar, which shows up in the water's depth colour.

## Width and depth of the terrain in meters, centred on the node.
@export_range(10.0, 4000.0, 1.0, "suffix:m") var size: float = 600.0:
	set(value):
		size = value
		_queue_build()
## Grid cells along each side.
@export_range(4, 400, 1) var cells: int = 150:
	set(value):
		cells = value
		_queue_build()
## Height of the open sea floor.
@export var floor_height: float = -16.0:
	set(value):
		floor_height = value
		_queue_build()
## Size of the random bumps on the floor, in meters.
@export var floor_roughness: float = 1.5:
	set(value):
		floor_roughness = value
		_queue_build()
## Vector4(centre x, centre z, radius, peak height) for each island or shoal.
@export var islands: Array[Vector4] = []:
	set(value):
		islands = value
		_queue_build()
## How ragged the coastlines are, as a share of each radius.
@export_range(0.0, 0.8, 0.01) var coast_noise: float = 0.3:
	set(value):
		coast_noise = value
		_queue_build()
@export var noise_seed: int = 7:
	set(value):
		noise_seed = value
		_queue_build()
## Build a StaticBody3D with a trimesh shape when the game runs.
@export var with_collision: bool = true
## Seabed lower than this doesn't receive shadows: a craft's shadow 15 m down would show
## through the water as a dark smudge. Shallows and beaches still do.
@export var shadow_cutoff_height: float = -2.0:
	set(value):
		shadow_cutoff_height = value
		_queue_build()

@export_group("Colours")
@export var seabed_color: Color = Color(0.78, 0.72, 0.52)
@export var sand_color: Color = Color(0.96, 0.87, 0.62)
@export var grass_color: Color = Color(0.36, 0.66, 0.27)
@export var rock_color: Color = Color(0.52, 0.48, 0.43)

var _noise := FastNoiseLite.new()
var _build_queued := false


func _ready() -> void:
	_build()
	if with_collision and not Engine.is_editor_hint():
		_add_collision()


## Terrain height at a world-space horizontal position.
func height_at(x: float, z: float) -> float:
	var local := to_local(Vector3(x, 0.0, z))
	return global_position.y + _height(local.x, local.z)


func _height(x: float, z: float) -> float:
	var h := floor_height + _noise.get_noise_2d(x * 0.6, z * 0.6) * floor_roughness
	for island in islands:
		var radius := maxf(island.z, 0.01)
		var dx := x - island.x
		var dz := z - island.y
		var ragged := 1.0 + _noise.get_noise_2d(x * 2.2 + 400.0, z * 2.2 - 300.0) * coast_noise
		var d := sqrt(dx * dx + dz * dz) / (radius * ragged)
		if d >= 1.0:
			continue
		# A rounded mound: flat-ish on top, sloping beaches round the edge.
		var t := 1.0 - d
		var shape := t * t * (3.0 - 2.0 * t)
		var peak := island.w + _noise.get_noise_2d(x * 3.0 - 90.0, z * 3.0 + 50.0) * absf(island.w) * 0.25
		h = maxf(h, lerpf(floor_height, peak, shape))
	return h


func _color(height: float, slope: float) -> Color:
	if slope > 0.75 and height > -0.5:
		return rock_color
	if height < -0.8:
		return seabed_color.lerp(seabed_color.darkened(0.25), clampf(-height / 20.0, 0.0, 1.0))
	if height < 1.6:
		return sand_color
	if slope > 0.5 or height > 9.0:
		return rock_color
	return grass_color


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	_noise.seed = noise_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.01
	_noise.fractal_octaves = 3

	var n := cells + 1
	var step := size / cells
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	for j in n:
		for i in n:
			heights[j * n + i] = _height(-size * 0.5 + i * step, -size * 0.5 + j * step)

	# Two surfaces: [0] receives shadows, [1] (deep seabed) doesn't.
	var vertices: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var normals: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var colors: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray()]
	for j in cells:
		for i in cells:
			var x0 := -size * 0.5 + i * step
			var z0 := -size * 0.5 + j * step
			var p00 := Vector3(x0, heights[j * n + i], z0)
			var p10 := Vector3(x0 + step, heights[j * n + i + 1], z0)
			var p01 := Vector3(x0, heights[(j + 1) * n + i], z0 + step)
			var p11 := Vector3(x0 + step, heights[(j + 1) * n + i + 1], z0 + step)
			# Alternate the diagonal so the low-poly facets don't all line up.
			var triangles: Array[PackedVector3Array]
			if (i + j) % 2 == 0:
				triangles = [PackedVector3Array([p00, p10, p11]), PackedVector3Array([p00, p11, p01])]
			else:
				triangles = [PackedVector3Array([p00, p10, p01]), PackedVector3Array([p10, p11, p01])]
			for tri in triangles:
				var normal := (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				var centre_height := (tri[0].y + tri[1].y + tri[2].y) / 3.0
				var color := _color(centre_height, 1.0 - normal.y)
				var top := maxf(tri[0].y, maxf(tri[1].y, tri[2].y))
				var surface := 1 if top < shadow_cutoff_height else 0
				vertices[surface].append_array(tri)
				normals[surface].append_array(PackedVector3Array([normal, normal, normal]))
				colors[surface].append_array(PackedColorArray([color, color, color]))

	var built := ArrayMesh.new()
	for surface in 2:
		if vertices[surface].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices[surface]
		arrays[Mesh.ARRAY_NORMAL] = normals[surface]
		arrays[Mesh.ARRAY_COLOR] = colors[surface]
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = 0.95
		material.disable_receive_shadows = surface == 1
		built.surface_set_material(built.get_surface_count() - 1, material)
	mesh = built


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
