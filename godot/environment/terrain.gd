@tool
class_name Terrain
extends MeshInstance3D
## Seabed and islands built from code: a flat-shaded height field with a matching collision
## shape, drawn in kiln's sand, grass and rock textures by height and slope. Near the water's
## edge the grid is finer and smooth-shaded (see [member shallow_lowest]).
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

@export_group("Shallows")
## Cells whose ground reaches between [member shallow_lowest] and [member shallow_highest]
## (in the terrain's own space, which the courses put at the water's rest level) are split into
## [member shallow_subdivisions] by [member shallow_subdivisions] smaller cells and shaded
## smooth, so the seabed seen through shallow water and the shoreline don't show the coarse
## grid's straight facets. The land above and the deep seabed stay flat-shaded on the coarse
## grid; where the two meet, the fine cells' edge follows the coarse cell's.
@export var shallow_lowest: float = -8.0:
	set(value):
		shallow_lowest = value
		_queue_build()
@export var shallow_highest: float = 1.6:
	set(value):
		shallow_highest = value
		_queue_build()
@export_range(1, 8, 1) var shallow_subdivisions: int = 4:
	set(value):
		shallow_subdivisions = value
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
# The grid while building: grid points per side, the fine lattice's subdivisions and spacing,
# each grid point's height and makeup, which cells are split, and the fine lattice's heights,
# worked out as they're needed (keyed by _lattice_key()).
var _points := 0
var _sub := 1
var _fine_step := 0.0
var _heights := PackedFloat32Array()
var _makeup := PackedColorArray()
var _split := PackedByteArray()
var _lattice: Dictionary[int, float] = {}
# The mesh's two surfaces while building: the shallows and land, which receive shadows, and
# the deep seabed, which doesn't.
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()
var _deep_vertices := PackedVector3Array()
var _deep_normals := PackedVector3Array()
var _deep_colors := PackedColorArray()


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
		# Beyond its most ragged coast an island can't reach here: skip its noise. (The noise
		# stays within 1 either way, so twice the coast noise is a safe margin.)
		var reach := radius * (1.0 + 2.0 * coast_noise)
		if dx * dx + dz * dz >= reach * reach:
			continue
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
func _makeup_at(height: float, slope: float) -> Color:
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

	_points = cells + 1
	_sub = maxi(shallow_subdivisions, 1)
	_fine_step = size / (cells * _sub)
	_lattice.clear()
	var n := _points
	var step := size / cells
	_heights.resize(n * n)
	for j in n:
		for i in n:
			_heights[j * n + i] = _lattice_height(i * _sub, j * _sub)
	# What each grid point is made of, from its height and the slope round it, so the textures
	# blend across a cell rather than changing in steps from one facet to the next.
	_makeup.resize(n * n)
	for j in n:
		for i in n:
			var dx := (_heights[j * n + mini(i + 1, cells)] - _heights[j * n + maxi(i - 1, 0)]) / (2.0 * step)
			var dz := (_heights[mini(j + 1, cells) * n + i] - _heights[maxi(j - 1, 0) * n + i]) / (2.0 * step)
			var up := Vector3(-dx, 1.0, -dz).normalized()
			_makeup[j * n + i] = _makeup_at(_heights[j * n + i], 1.0 - up.y)
	# The cells near the water's edge are split (see shallow_lowest).
	_split.resize(cells * cells)
	for j in cells:
		for i in cells:
			var corners := [_heights[j * n + i], _heights[j * n + i + 1], _heights[(j + 1) * n + i],
					_heights[(j + 1) * n + i + 1]]
			_split[j * cells + i] = 1 if corners.max() >= shallow_lowest and corners.min() <= shallow_highest else 0

	var coords := PackedFloat32Array()
	coords.resize(n)
	for i in n:
		coords[i] = _lattice_coord(i * _sub)
	for j in cells:
		for i in cells:
			var cell := j * cells + i
			if _split[cell] == 1:
				_add_split_cell(i, j)
				continue
			if (i > 0 and _split[cell - 1] == 1) or (i < cells - 1 and _split[cell + 1] == 1) \
					or (j > 0 and _split[cell - cells] == 1) or (j < cells - 1 and _split[cell + cells] == 1):
				_add_cell(i, j)
				continue
			# Most cells have no split cell beside them: two flat-shaded triangles, the diagonal
			# alternating so the low-poly facets don't all line up. Written out here rather than
			# through _add_cell(), whose calls made the build twice as slow.
			var k00 := j * n + i
			var p00 := Vector3(coords[i], _heights[k00], coords[j])
			var p10 := Vector3(coords[i + 1], _heights[k00 + 1], coords[j])
			var p01 := Vector3(coords[i], _heights[k00 + n], coords[j + 1])
			var p11 := Vector3(coords[i + 1], _heights[k00 + n + 1], coords[j + 1])
			if (i + j) % 2 == 0:
				_add_flat(p00, p10, p11, _makeup[k00], _makeup[k00 + 1], _makeup[k00 + n + 1])
				_add_flat(p00, p11, p01, _makeup[k00], _makeup[k00 + n + 1], _makeup[k00 + n])
			else:
				_add_flat(p00, p10, p01, _makeup[k00], _makeup[k00 + 1], _makeup[k00 + n])
				_add_flat(p10, p11, p01, _makeup[k00 + 1], _makeup[k00 + n + 1], _makeup[k00 + n])
	_lattice.clear()

	var deep := material.duplicate() as ShaderMaterial
	deep.shader = DEEP_SHADER
	var built := ArrayMesh.new()
	var surfaces := [[_vertices, _normals, _colors, material], [_deep_vertices, _deep_normals, _deep_colors, deep]]
	for surface: Array in surfaces:
		if (surface[0] as PackedVector3Array).is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface[0]
		arrays[Mesh.ARRAY_NORMAL] = surface[1]
		arrays[Mesh.ARRAY_COLOR] = surface[2]
		built.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		built.surface_set_material(built.get_surface_count() - 1, surface[3])
	_vertices = PackedVector3Array()
	_normals = PackedVector3Array()
	_colors = PackedColorArray()
	_deep_vertices = PackedVector3Array()
	_deep_normals = PackedVector3Array()
	_deep_colors = PackedColorArray()
	mesh = built
	_plant_palms()


## Adds an unsplit cell next to a split one: two flat-shaded triangles, as [method _build]
## draws any other unsplit cell. The split cell's points along their shared edge lie on this
## cell's edge, and the triangle there is fanned from its middle through them, in its own plane,
## so the two meet without cracks.
func _add_cell(i: int, j: int) -> void:
	var n := _points
	var k00 := j * n + i
	var corners: PackedInt32Array = [k00, k00 + 1, k00 + n + 1, k00, k00 + n + 1, k00 + n] if (i + j) % 2 == 0 \
			else [k00, k00 + 1, k00 + n, k00 + 1, k00 + n + 1, k00 + n]
	for t in 2:
		var keys: PackedInt32Array = [corners[t * 3], corners[t * 3 + 1], corners[t * 3 + 2]]
		var a := _grid_point(keys[0])
		var b := _grid_point(keys[1])
		var c := _grid_point(keys[2])
		var normal := (c - a).cross(b - a).normalized()
		var surface := 1 if maxf(a.y, maxf(b.y, c.y)) < shadow_cutoff_height else 0
		# The triangle's outline, with the split cell's points along an edge they share.
		var ring := PackedVector3Array()
		var ring_makeup := PackedColorArray()
		for k in 3:
			var from := keys[k]
			var to := keys[(k + 1) % 3]
			ring.append(_grid_point(from))
			ring_makeup.append(_makeup[from])
			var lo := mini(from, to)
			var hi := maxi(from, to)
			if (hi - lo != 1 and hi - lo != n) or not _mixed_edge(lo, hi):
				continue
			for m in range(1, _sub):
				# The same sums as _add_split_cell() does, so the points match exactly.
				var along := m if from == lo else _sub - m
				var g := _grid_lattice(lo) + (Vector2i(along, 0) if hi - lo == 1 else Vector2i(0, along))
				ring.append(Vector3(_lattice_coord(g.x), lerpf(_heights[lo], _heights[hi], float(along) / _sub),
						_lattice_coord(g.y)))
				ring_makeup.append(_makeup[lo].lerp(_makeup[hi], float(along) / _sub))
		if ring.size() == 3:
			_add_triangle(surface, a, b, c, normal, normal, normal, _makeup[keys[0]], _makeup[keys[1]], _makeup[keys[2]])
			continue
		var middle := (a + b + c) / 3.0
		var middle_makeup := (_makeup[keys[0]] + _makeup[keys[1]] + _makeup[keys[2]]) / 3.0
		for k in ring.size():
			var next := (k + 1) % ring.size()
			_add_triangle(surface, middle, ring[k], ring[next], normal, normal, normal, middle_makeup, ring_makeup[k],
					ring_makeup[next])


## Grid point [param k] (its index in the grid's arrays), where it is drawn.
@warning_ignore("integer_division")
func _grid_point(k: int) -> Vector3:
	return Vector3(_lattice_coord((k % _points) * _sub), _heights[k], _lattice_coord((k / _points) * _sub))


## Grid point [param k] as a point of the fine lattice.
@warning_ignore("integer_division")
func _grid_lattice(k: int) -> Vector2i:
	return Vector2i((k % _points) * _sub, (k / _points) * _sub)


## Adds a split cell: [member shallow_subdivisions] by [member shallow_subdivisions] small
## cells on the fine lattice, smooth-shaded. Along an edge it shares with an unsplit cell its
## points lie on that cell's straight edge, as [method _add_cell] puts them.
func _add_split_cell(i: int, j: int) -> void:
	var side := _sub + 1
	# The terrain's heights at the cell's lattice points and a ring of points round them, for the
	# slopes at its edges.
	var wide := _sub + 3
	var heights := PackedFloat64Array()
	heights.resize(wide * wide)
	for v in wide:
		for u in wide:
			heights[v * wide + u] = _lattice_height(i * _sub + u - 1, j * _sub + v - 1)
	var g00 := Vector2i(i * _sub, j * _sub)
	# The cell's corners: (i, j), (i + 1, j), (i, j + 1), (i + 1, j + 1); and which of its edges
	# it shares with an unsplit cell.
	var k00 := j * _points + i
	var corners: PackedInt32Array = [k00, k00 + 1, k00 + _points, k00 + _points + 1]
	var bottom := _mixed_edge(corners[0], corners[1])
	var top := _mixed_edge(corners[2], corners[3])
	var left := _mixed_edge(corners[0], corners[2])
	var right := _mixed_edge(corners[1], corners[3])
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for v in side:
		for u in side:
			var at := (v + 1) * wide + u + 1
			var h := heights[at]
			var on_x := u == 0 or u == _sub
			var on_z := v == 0 or v == _sub
			if on_z and not on_x and (top if v == _sub else bottom):
				var from := corners[2 if v == _sub else 0]
				h = lerpf(_heights[from], _heights[from + 1], float(u) / _sub)
			elif on_x and not on_z and (right if u == _sub else left):
				var from := corners[1 if u == _sub else 0]
				h = lerpf(_heights[from], _heights[from + _points], float(v) / _sub)
			points.append(Vector3(_lattice_coord(g00.x + u), h, _lattice_coord(g00.y + v)))
			normals.append(Vector3(heights[at - 1] - heights[at + 1], 2.0 * _fine_step,
					heights[at - wide] - heights[at + wide]).normalized())
			# The makeup blends across the cell from its corners, as across an unsplit cell
			# (worked out from each small cell's own height and slope, sand gave way to grass in
			# 1 m steps).
			var s := float(u) / _sub
			colors.append(_makeup[corners[0]].lerp(_makeup[corners[1]], s).lerp(
					_makeup[corners[2]].lerp(_makeup[corners[3]], s), float(v) / _sub))
	for v in _sub:
		for u in _sub:
			var q00 := v * side + u
			var q10 := q00 + 1
			var q01 := q00 + side
			var q11 := q01 + 1
			var triangles: PackedInt32Array = [q00, q10, q11, q00, q11, q01] if (g00.x + u + g00.y + v) % 2 == 0 \
					else [q00, q10, q01, q10, q11, q01]
			for t in 2:
				var qa := triangles[t * 3]
				var qb := triangles[t * 3 + 1]
				var qc := triangles[t * 3 + 2]
				var a := points[qa]
				var b := points[qb]
				var c := points[qc]
				var surface := 1 if maxf(a.y, maxf(b.y, c.y)) < shadow_cutoff_height else 0
				_add_triangle(surface, a, b, c, normals[qa], normals[qb], normals[qc], colors[qa], colors[qb], colors[qc])


## Adds a flat-shaded triangle.
func _add_flat(a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var normal := (c - a).cross(b - a).normalized()
	_add_triangle(1 if maxf(a.y, maxf(b.y, c.y)) < shadow_cutoff_height else 0, a, b, c, normal, normal, normal,
			ca, cb, cc)


func _add_triangle(surface: int, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3,
		ca: Color, cb: Color, cc: Color) -> void:
	if surface == 0:
		_vertices.append(a)
		_vertices.append(b)
		_vertices.append(c)
		_normals.append(na)
		_normals.append(nb)
		_normals.append(nc)
		_colors.append(ca)
		_colors.append(cb)
		_colors.append(cc)
	else:
		_deep_vertices.append(a)
		_deep_vertices.append(b)
		_deep_vertices.append(c)
		_deep_normals.append(na)
		_deep_normals.append(nb)
		_deep_normals.append(nc)
		_deep_colors.append(ca)
		_deep_colors.append(cb)
		_deep_colors.append(cc)


## True if the cell edge between grid points [param lo] and [param hi] (indices into the
## grid's arrays, [param hi] the next point along +x or +z) lies between a split and an
## unsplit cell.
@warning_ignore("integer_division")
func _mixed_edge(lo: int, hi: int) -> bool:
	var i := lo % _points
	var j := lo / _points
	var other := Vector2i(i, j - 1) if hi == lo + 1 else Vector2i(i - 1, j)
	if other.x < 0 or other.y < 0 or i >= cells or j >= cells:
		return false
	return _split[other.y * cells + other.x] != _split[j * cells + i]


## The terrain's height at fine lattice point ([param gi], [param gj]), which may lie outside
## the terrain (for slopes at its border); worked out once per build.
func _lattice_height(gi: int, gj: int) -> float:
	var key := _lattice_key(gi, gj)
	var h: float = _lattice.get(key, NAN)
	if is_nan(h):
		h = _height(_lattice_coord(gi), _lattice_coord(gj))
		_lattice[key] = h
	return h


func _lattice_key(gi: int, gj: int) -> int:
	return (gj + 1) * (cells * _sub + 3) + gi + 1


## The x (or z) of fine lattice line [param g]: grid line i is lattice line i times the
## subdivisions.
func _lattice_coord(g: int) -> float:
	return -size * 0.5 + g * _fine_step


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
