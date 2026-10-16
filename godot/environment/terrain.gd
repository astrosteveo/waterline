@tool
class_name Terrain
extends MeshInstance3D
## Seabed and islands built from code: a flat-shaded height field with a matching collision
## shape, drawn in kiln's sand, grass and rock textures by height and slope.
##
## Islands and shoals are bumps on a noisy sea floor. Each entry of [member islands] is
## Vector4(centre x, centre z, radius, peak height); a negative peak makes an underwater
## sandbar, which shows up in the water's depth colour. Each vertex's colour says what the
## ground there is made of, for [member material] (see terrain.gdshaderinc). Palm trees grow
## on the islands [member palm_spacing] apart.

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

## The terrain's material: terrain.gdshader with its textures. The deep seabed is drawn in a
## copy of it on [constant DEEP_SHADER].
@export var material: ShaderMaterial = preload("res://environment/materials/terrain.tres"):
	set(value):
		material = value
		_queue_build()

@export_group("Palms")
## How far apart palm trees grow on the islands, on gentle ground from the top of the beach up
## the hills (0 for none). They are drawn but not solid: a craft never reaches them.
@export_range(0.0, 100.0, 0.1, "suffix:m") var palm_spacing: float = 0.0:
	set(value):
		palm_spacing = value
		_queue_build()
## The palms, one picked at random for each spot: kiln's (art/models/plants/), each one mesh.
@export var palm_models: Array[PackedScene] = [preload("res://assets/models/plants/palm_a.glb"),
		preload("res://assets/models/plants/palm_b.glb"), preload("res://assets/models/plants/palm_c.glb")]:
	set(value):
		palm_models = value
		_queue_build()

## Palms grow between these heights above the water's rest level, where the ground slopes
## less than [constant PALM_STEEPEST] (1 minus the ground normal's height).
const PALM_LOWEST := 1.2
const PALM_HIGHEST := 8.0
const PALM_STEEPEST := 0.3
## How far a palm's foot sinks into the ground, so it doesn't float on a slope.
const PALM_SINK := 0.3
## The same look as terrain.gdshader without receiving shadows, for the deep seabed.
const DEEP_SHADER := preload("res://environment/terrain_deep.gdshader")
## How deep the seabed is when it is darkest, in metres.
const DARKEST_DEPTH := 20.0

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


## What the ground at this height and slope is made of, as terrain.gdshaderinc reads a vertex
## colour: red sand, green grass, blue rock, alpha how deep the seabed lies (0 to 1 at
## [constant DARKEST_DEPTH]).
func _makeup(height: float, slope: float) -> Color:
	if slope > 0.75 and height > -0.5:
		return Color(0.0, 0.0, 1.0, 0.0)
	if height < -0.8:
		return Color(1.0, 0.0, 0.0, clampf(-height / DARKEST_DEPTH, 0.0, 1.0))
	if height < 1.6:
		return Color(1.0, 0.0, 0.0, 0.0)
	if slope > 0.5 or height > 9.0:
		return Color(0.0, 0.0, 1.0, 0.0)
	return Color(0.0, 1.0, 0.0, 0.0)


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
	# What each grid point is made of, from its height and the slope round it, so the textures
	# blend across a cell rather than changing in steps from one facet to the next.
	var makeup := PackedColorArray()
	makeup.resize(n * n)
	for j in n:
		for i in n:
			var dx := (heights[j * n + mini(i + 1, cells)] - heights[j * n + maxi(i - 1, 0)]) / (2.0 * step)
			var dz := (heights[mini(j + 1, cells) * n + i] - heights[maxi(j - 1, 0) * n + i]) / (2.0 * step)
			var up := Vector3(-dx, 1.0, -dz).normalized()
			makeup[j * n + i] = _makeup(heights[j * n + i], 1.0 - up.y)

	# Two surfaces: [0] receives shadows, [1] (deep seabed) doesn't.
	var vertices: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var normals: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array()]
	var colors: Array[PackedColorArray] = [PackedColorArray(), PackedColorArray()]
	for j in cells:
		for i in cells:
			var x0 := -size * 0.5 + i * step
			var z0 := -size * 0.5 + j * step
			var k00 := j * n + i
			var k10 := k00 + 1
			var k01 := k00 + n
			var k11 := k01 + 1
			var p00 := Vector3(x0, heights[k00], z0)
			var p10 := Vector3(x0 + step, heights[k10], z0)
			var p01 := Vector3(x0, heights[k01], z0 + step)
			var p11 := Vector3(x0 + step, heights[k11], z0 + step)
			# Alternate the diagonal so the low-poly facets don't all line up.
			var triangles: Array[PackedVector3Array]
			var corners: Array[PackedInt32Array]
			if (i + j) % 2 == 0:
				triangles = [PackedVector3Array([p00, p10, p11]), PackedVector3Array([p00, p11, p01])]
				corners = [PackedInt32Array([k00, k10, k11]), PackedInt32Array([k00, k11, k01])]
			else:
				triangles = [PackedVector3Array([p00, p10, p01]), PackedVector3Array([p10, p11, p01])]
				corners = [PackedInt32Array([k00, k10, k01]), PackedInt32Array([k10, k11, k01])]
			for t in 2:
				var tri := triangles[t]
				var normal := (tri[2] - tri[0]).cross(tri[1] - tri[0]).normalized()
				var top := maxf(tri[0].y, maxf(tri[1].y, tri[2].y))
				var surface := 1 if top < shadow_cutoff_height else 0
				vertices[surface].append_array(tri)
				normals[surface].append_array(PackedVector3Array([normal, normal, normal]))
				for k in corners[t]:
					colors[surface].append(makeup[k])

	var deep := material.duplicate() as ShaderMaterial
	deep.shader = DEEP_SHADER
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
		built.surface_set_material(built.get_surface_count() - 1, deep if surface == 1 else material)
	mesh = built
	_plant_palms()


## Scatters palms over the islands: one spot per [member palm_spacing] square, jittered,
## kept where the ground suits a palm. Each model's palms are drawn together as one
## [MultiMeshInstance3D], on the visual layer the shore map leaves out, so a crown hanging
## over the water isn't taken for a shore.
func _plant_palms() -> void:
	for child in get_children(true):
		if child.has_meta(&"palms"):
			child.free()
	if palm_spacing <= 0.0 or palm_models.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var placed: Array[Array] = []
	for kind in palm_models.size():
		placed.append([])
	var steps := int(size / palm_spacing)
	for j in steps:
		for i in steps:
			# Every spot draws the same numbers, kept or not, so moving one island doesn't move
			# the palms on the others.
			var x := -size * 0.5 + (i + rng.randf()) * palm_spacing
			var z := -size * 0.5 + (j + rng.randf()) * palm_spacing
			var kind := rng.randi() % palm_models.size()
			var turn := rng.randf() * TAU
			var grow := rng.randf_range(0.8, 1.15)
			var h := _height(x, z)
			if h < PALM_LOWEST or h > PALM_HIGHEST:
				continue
			var up := Vector3(_height(x - 1.0, z) - _height(x + 1.0, z), 2.0, _height(x, z - 1.0) - _height(x, z + 1.0))
			if 1.0 - up.normalized().y > PALM_STEEPEST:
				continue
			placed[kind].append(Transform3D(Basis(Vector3.UP, turn).scaled(Vector3.ONE * grow), Vector3(x, h - PALM_SINK, z)))
	for kind in palm_models.size():
		if placed[kind].is_empty():
			continue
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _palm_mesh(palm_models[kind])
		multimesh.instance_count = placed[kind].size()
		for n in placed[kind].size():
			multimesh.set_instance_transform(n, placed[kind][n])
		var grove := MultiMeshInstance3D.new()
		grove.name = "Palms%d" % kind
		grove.multimesh = multimesh
		grove.layers = ShoreMap.DYNAMIC_LAYER
		grove.set_meta(&"palms", true)
		add_child(grove, false, Node.INTERNAL_MODE_FRONT)


## The one mesh of a palm model.
static func _palm_mesh(scene: PackedScene) -> Mesh:
	var palm := scene.instantiate()
	var found := SceneryModel.meshes(palm)
	var shape: Mesh = found[0].mesh if not found.is_empty() else null
	palm.free()
	return shape


func _add_collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
