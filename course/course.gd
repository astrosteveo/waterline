@tool
class_name Course
extends Node3D
## A race course: a closed centre line, the corridor around it with invisible walls at its
## edges, the buoys in the order racers pass them, and the start line.
##
## The centre line is a smooth closed curve (centripetal Catmull-Rom) through
## [member control_points], sampled every [member sample_spacing] meters and turned so its
## first sample lies on the start line (the child Marker3D named StartLine). Racers'
## progress is measured along it ([method track]). The buoys are the Buoy children of the
## Buoys node, in order of travel; each becomes a [CourseGate] across the corridor.
##
## Everything is in world space: keep this node at the origin, unrotated. It is the root
## of a course scene, next to the water, sun, terrain and scenery.

## Emitted after the centre line, walls and gates are rebuilt.
signal layout_changed

## Name shown on the HUD and in menus.
@export var course_name: String = "Course"
## Laps in a race on this course.
@export_range(1, 9, 1) var laps: int = 3

@export_group("Centre line")
## Points the centre line passes through, in order of travel. Only x and z are used.
@export var control_points: PackedVector3Array = PackedVector3Array():
	set(value):
		control_points = value
		_queue_rebuild()
## Half width of the corridor at each control point, in meters: the walls stand this far
## either side of the centre line (closer on the inside of tight turns).
@export var half_widths: PackedFloat32Array = PackedFloat32Array():
	set(value):
		half_widths = value
		_queue_rebuild()
## Distance between centre-line samples.
@export_range(0.25, 4.0, 0.05, "suffix:m") var sample_spacing: float = 1.0:
	set(value):
		sample_spacing = value
		_queue_rebuild()

@export_group("Start")
## How far behind the start line the starting grid is.
@export_range(0.0, 60.0, 0.1, "suffix:m") var grid_distance: float = 12.0
## Sideways gap between starting slots.
@export_range(1.0, 20.0, 0.1, "suffix:m") var grid_spacing: float = 7.0

@export_group("Walls")
## Build the invisible walls when the game runs.
@export var build_walls: bool = true
@export var wall_bottom: float = -6.0
## Walls reach this high, above any jump.
@export var wall_top: float = 18.0
@export_range(0.1, 5.0, 0.1, "suffix:m") var wall_thickness: float = 1.0
## Length of each wall box.
@export_range(0.5, 20.0, 0.1, "suffix:m") var wall_segment: float = 3.0
## How springy the walls are. A little bounce keeps a craft from sticking to them.
@export_range(0.0, 1.0, 0.01) var wall_bounce: float = 0.1

@export_group("Wall floats")
## Line the walls with small floats where they cross open water, so racers can see where
## the course ends. Along beaches and rocks the land itself shows it.
@export var wall_floats: bool = true
@export_range(1.0, 20.0, 0.1, "suffix:m") var float_spacing: float = 5.0
## Floats go only where the seabed is deeper than this.
@export_range(0.0, 20.0, 0.1, "suffix:m") var float_min_depth: float = 2.0
## The floats alternate between these colours.
@export var float_colors: PackedColorArray = PackedColorArray([Color(1.0, 0.42, 0.08), Color(0.96, 0.96, 0.94)])

@export_group("Preview")
## Draw the centre line, walls and gates in the editor.
@export var preview_in_editor: bool = true:
	set(value):
		preview_in_editor = value
		_queue_rebuild()

## Length of the centre line, in meters: one lap.
var length: float = 0.0
## The buoy gates in order of travel.
var gates: Array[CourseGate] = []
## The start and finish line.
var finish_gate: CourseGate

var _points := PackedVector3Array()
var _tangents := PackedVector3Array()
var _widths := PackedFloat32Array()
var _curvatures := PackedFloat32Array()
var _left_limits := PackedFloat32Array()
var _right_limits := PackedFloat32Array()
var _left_wall := PackedVector3Array()
var _right_wall := PackedVector3Array()
var _step := 1.0
var _rebuild_queued := false
var _preview: MeshInstance3D
var _walls: StaticBody3D
var _floats: MultiMeshInstance3D
var _float_material: ShaderMaterial


func _ready() -> void:
	rebuild()
	if Engine.is_editor_hint():
		return
	if build_walls:
		_build_wall_bodies()
	if wall_floats:
		_build_wall_floats()


func _exit_tree() -> void:
	if _float_material != null and not Engine.is_editor_hint():
		Ocean.remove_follower(_float_material)


## Rebuilds the centre line, wall lines and gates from the current data.
func rebuild() -> void:
	_rebuild_queued = false
	_build_centre_line()
	_build_wall_lines()
	_build_gates()
	_update_preview()
	layout_changed.emit()


func _queue_rebuild() -> void:
	if not is_node_ready() or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if control_points.size() < 4:
		warnings.append("The centre line needs at least 4 control points.")
	if half_widths.size() != control_points.size():
		warnings.append("half_widths needs one value per control point.")
	if get_node_or_null(^"StartLine") == null:
		warnings.append("Add a Marker3D named StartLine on the centre line; until then the first control point is the start.")
	for i in range(1, gates.size()):
		if gates[i].offset <= gates[i - 1].offset:
			warnings.append("Buoy %s comes before the buoy listed ahead of it; order the Buoys children by travel." % gates[i].buoy.name)
	return warnings


# --- Queries -------------------------------------------------------------------------

## Number of centre-line samples.
func sample_count() -> int:
	return _points.size()


## Point on the centre line [param offset] meters past the start line (y = 0).
func point_at(offset: float) -> Vector3:
	var f := _fraction(offset)
	var i := int(f)
	var t := f - i
	return _points[i % _points.size()].lerp(_points[(i + 1) % _points.size()], t)


## Direction of travel at [param offset] (horizontal, unit length).
func tangent_at(offset: float) -> Vector3:
	var f := _fraction(offset)
	var i := int(f)
	var t := f - i
	return _tangents[i % _tangents.size()].slerp(_tangents[(i + 1) % _tangents.size()], t).normalized()


## Horizontal unit vector to the right of the direction of travel at [param offset].
func right_at(offset: float) -> Vector3:
	return tangent_at(offset).cross(Vector3.UP)


## Half width of the corridor at [param offset].
func width_at(offset: float) -> float:
	return _lerp_array(_widths, offset)


## Signed curvature at [param offset], 1/m: positive for a right turn.
func curvature_at(offset: float) -> float:
	return _lerp_array(_curvatures, offset)


## How far left (negative) and right (positive) of the centre line the corridor reaches at
## [param offset]: the walls, pulled in on the inside of tight turns.
func limits_at(offset: float) -> Vector2:
	return Vector2(-_lerp_array(_left_limits, offset), _lerp_array(_right_limits, offset))


## A transform on the course: [param lateral] meters right of the centre line at
## [param offset], facing the direction of travel, at the water's rest level.
func transform_at(offset: float, lateral: float = 0.0) -> Transform3D:
	var forward := tangent_at(offset)
	var position := point_at(offset) + forward.cross(Vector3.UP) * lateral
	return Transform3D(Basis.looking_at(forward, Vector3.UP), position)


## Starting slot [param slot] of [param count], side by side behind the start line, left
## to right.
func grid_transform(slot: int, count: int) -> Transform3D:
	var lateral := (slot - (count - 1) * 0.5) * grid_spacing
	return transform_at(length - grid_distance, lateral)


## Each buoy gate as [offset, required side, the buoy's distance right of the centre line],
## for tests and tools.
func gate_table() -> Array:
	var table := []
	for gate in gates:
		table.append([gate.offset, gate.required_side, (gate.position - point_at(gate.offset)).dot(right_at(gate.offset))])
	return table


## Updates [param progress] to [param world_position]. The nearest centre-line sample is
## searched near the last one, so a racer can't jump to another part of the course that
## happens to lie close by. The first update (index -1) searches the whole line.
func track(progress: CourseProgress, world_position: Vector3, window: int = 24) -> void:
	var p := Vector3(world_position.x, 0.0, world_position.z)
	var n := _points.size()
	if n == 0:
		return
	var best := -1
	var best_distance := INF
	if progress.index < 0:
		for i in n:
			var d := _points[i].distance_squared_to(p)
			if d < best_distance:
				best_distance = d
				best = i
	else:
		for k in range(-window, window + 1):
			var i := posmod(progress.index + k, n)
			var d := _points[i].distance_squared_to(p)
			if d < best_distance:
				best_distance = d
				best = i
	# Refine between the samples either side.
	var a := _points[best]
	var ahead := _points[(best + 1) % n] - a
	var t_ahead := clampf((p - a).dot(ahead) / ahead.length_squared(), 0.0, 1.0)
	var behind := _points[(best - 1 + n) % n]
	var back := a - behind
	var t_back := clampf((p - behind).dot(back) / back.length_squared(), 0.0, 1.0)
	var offset: float
	if (a + ahead * t_ahead).distance_squared_to(p) <= (behind + back * t_back).distance_squared_to(p):
		offset = (best + t_ahead) * _step
	else:
		offset = (best - 1 + t_back) * _step
	offset = fposmod(offset, length)
	if progress.index < 0:
		progress.distance = offset if offset < length * 0.5 else offset - length
	else:
		progress.distance += wrapf(offset - progress.offset, -length * 0.5, length * 0.5)
	progress.index = best
	progress.offset = offset
	progress.lateral = (p - point_at(offset)).dot(right_at(offset))


## Like [method track], but searches the whole centre line, for a racer that was moved
## (a rescue). The travelled distance stays continuous.
func relocate(progress: CourseProgress, world_position: Vector3) -> void:
	if progress.index < 0:
		track(progress, world_position)
		return
	var old_distance := progress.distance
	var old_offset := progress.offset
	progress.index = -1
	track(progress, world_position)
	progress.distance = old_distance + wrapf(progress.offset - old_offset, -length * 0.5, length * 0.5)


func _fraction(offset: float) -> float:
	return fposmod(offset, length) / _step


func _lerp_array(values: PackedFloat32Array, offset: float) -> float:
	if values.is_empty():
		return 0.0
	var f := _fraction(offset)
	var i := int(f)
	return lerpf(values[i % values.size()], values[(i + 1) % values.size()], f - i)


# --- Building ------------------------------------------------------------------------

func _build_centre_line() -> void:
	_points.clear()
	_tangents.clear()
	_widths.clear()
	_curvatures.clear()
	length = 0.0
	var count := control_points.size()
	if count < 4:
		return
	# A fine polyline through the control points (centripetal Catmull-Rom)...
	var fine := PackedVector3Array()
	var fine_widths := PackedFloat32Array()
	for i in count:
		var p0 := _flat(control_points[(i - 1 + count) % count])
		var p1 := _flat(control_points[i])
		var p2 := _flat(control_points[(i + 1) % count])
		var p3 := _flat(control_points[(i + 2) % count])
		var w1 := _width(i)
		var w2 := _width((i + 1) % count)
		var t1 := sqrt(p0.distance_to(p1))
		var t2 := t1 + sqrt(p1.distance_to(p2))
		var t3 := t2 + sqrt(p2.distance_to(p3))
		var pieces := maxi(int(p1.distance_to(p2) / 0.25), 4)
		for k in pieces:
			var t := lerpf(t1, t2, float(k) / pieces)
			var a1 := p0 * ((t1 - t) / t1) + p1 * (t / t1)
			var a2 := p1 * ((t2 - t) / (t2 - t1)) + p2 * ((t - t1) / (t2 - t1))
			var a3 := p2 * ((t3 - t) / (t3 - t2)) + p3 * ((t - t2) / (t3 - t2))
			var b1 := a1 * ((t2 - t) / t2) + a2 * (t / t2)
			var b2 := a2 * ((t3 - t) / (t3 - t1)) + a3 * ((t - t1) / (t3 - t1))
			fine.append(b1 * ((t2 - t) / (t2 - t1)) + b2 * ((t - t1) / (t2 - t1)))
			fine_widths.append(lerpf(w1, w2, float(k) / pieces))
	# ...resampled at even spacing.
	var cumulative := PackedFloat32Array([0.0])
	for i in fine.size():
		cumulative.append(cumulative[i] + fine[i].distance_to(fine[(i + 1) % fine.size()]))
	length = cumulative[fine.size()]
	var n := maxi(int(length / sample_spacing), 8)
	_step = length / n
	var j := 0
	var resampled := PackedVector3Array()
	var resampled_widths := PackedFloat32Array()
	for i in n:
		var s := i * _step
		while cumulative[j + 1] < s:
			j += 1
		var u := (s - cumulative[j]) / maxf(cumulative[j + 1] - cumulative[j], 1e-6)
		resampled.append(fine[j].lerp(fine[(j + 1) % fine.size()], u))
		resampled_widths.append(lerpf(fine_widths[j], fine_widths[(j + 1) % fine.size()], u))
	# Turn the arrays so sample 0 is the start line.
	var start := 0
	var marker := get_node_or_null(^"StartLine") as Node3D
	if marker != null:
		var target := _flat(marker.position)
		var best := INF
		for i in n:
			var d := resampled[i].distance_squared_to(target)
			if d < best:
				best = d
				start = i
	for i in n:
		_points.append(resampled[(i + start) % n])
		_widths.append(resampled_widths[(i + start) % n])
	for i in n:
		var tangent := (_points[(i + 1) % n] - _points[(i - 1 + n) % n]).normalized()
		_tangents.append(tangent)
	for i in n:
		var a := _tangents[(i - 1 + n) % n]
		var b := _tangents[(i + 1) % n]
		var turn := atan2(a.cross(b).y, a.dot(b))
		# Turning right is clockwise seen from above: a negative turn about +Y.
		_curvatures.append(-turn / (2.0 * _step))


func _width(i: int) -> float:
	return half_widths[i] if i < half_widths.size() else 20.0


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _build_wall_lines() -> void:
	var n := _points.size()
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	_left_limits.resize(n)
	_right_limits.resize(n)
	for i in n:
		var r := _tangents[i].cross(Vector3.UP)
		left.append(_points[i] - r * _widths[i])
		right.append(_points[i] + r * _widths[i])
		# On the inside of a turn the wall can't be further than the turn's radius.
		var radius := 1.0 / maxf(absf(_curvatures[i]), 1e-4)
		var inner := minf(_widths[i], radius * 0.9)
		_left_limits[i] = inner if _curvatures[i] < 0.0 else _widths[i]
		_right_limits[i] = inner if _curvatures[i] > 0.0 else _widths[i]
	_left_wall = _remove_loops(left)
	_right_wall = _remove_loops(right)


## Removes the small loops an offset line makes on the inside of a turn tighter than the
## offset: where the line crosses itself, the part between the crossings is cut out.
static func _remove_loops(line: PackedVector3Array, window: int = 160) -> PackedVector3Array:
	var n := line.size()
	var out := PackedVector3Array()
	var i := 0
	while i < n:
		out.append(line[i])
		var a := line[i]
		var b := line[(i + 1) % n]
		var next := i + 1
		for k in range(2, window):
			var j := i + k
			if j + 1 >= n:
				break
			var c := line[j]
			var d := line[j + 1]
			if maxf(c.x, d.x) < minf(a.x, b.x) or minf(c.x, d.x) > maxf(a.x, b.x) \
					or maxf(c.z, d.z) < minf(a.z, b.z) or minf(c.z, d.z) > maxf(a.z, b.z):
				continue
			var hit: Variant = Geometry2D.segment_intersects_segment(
					Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z), Vector2(d.x, d.z))
			if hit != null:
				var x: Vector2 = hit
				out.append(Vector3(x.x, 0.0, x.y))
				next = j + 1
				break
		i = next
	return out


func _build_gates() -> void:
	gates.clear()
	finish_gate = null
	if _points.is_empty():
		return
	finish_gate = CourseGate.new()
	finish_gate.position = _points[0]
	finish_gate.offset = 0.0
	finish_gate.forward = _tangents[0]
	finish_gate.right = _tangents[0].cross(Vector3.UP)
	finish_gate.reach_left = _widths[0] + 6.0
	finish_gate.reach_right = _widths[0] + 6.0
	var holder := get_node_or_null(^"Buoys")
	if holder == null:
		return
	var probe := CourseProgress.new()
	for child in holder.get_children():
		var buoy := child as Buoy
		if buoy == null:
			continue
		var at := _flat(buoy.rest_position())
		probe.index = -1
		track(probe, at)
		var gate := CourseGate.new()
		gate.position = at
		gate.offset = probe.offset
		gate.forward = tangent_at(probe.offset)
		gate.right = gate.forward.cross(Vector3.UP)
		var half := width_at(probe.offset)
		gate.reach_left = half + probe.lateral + 6.0
		gate.reach_right = half - probe.lateral + 6.0
		gate.required_side = buoy.required_side()
		gate.buoy = buoy
		gate.index = gates.size()
		gates.append(gate)


func _build_wall_bodies() -> void:
	if _walls != null:
		_walls.queue_free()
	_walls = StaticBody3D.new()
	_walls.name = "Walls"
	_walls.collision_layer = PhysicsLayers.WALLS
	_walls.collision_mask = 0
	var material := PhysicsMaterial.new()
	material.friction = 0.0
	material.bounce = wall_bounce
	_walls.physics_material_override = material
	_walls.add_to_group(&"course_walls")
	add_child(_walls, false, Node.INTERNAL_MODE_BACK)
	_add_wall_boxes(_left_wall, -1.0)
	_add_wall_boxes(_right_wall, 1.0)


## Lines [param line] with boxes whose inner face lies on the line. [param side] is -1 for
## the left wall and 1 for the right wall.
func _add_wall_boxes(line: PackedVector3Array, side: float) -> void:
	var n := line.size()
	if n < 2:
		return
	var height := wall_top - wall_bottom
	var from := line[0]
	var travelled := 0.0
	for i in n:
		var a := line[i]
		var b := line[(i + 1) % n]
		travelled += a.distance_to(b)
		if travelled < wall_segment and i < n - 1:
			continue
		travelled = 0.0
		var to := b
		var along := to - from
		var span := along.length()
		if span < 0.05:
			continue
		var dir := along / span
		var outward := dir.cross(Vector3.UP) * side
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(wall_thickness, height, span + wall_thickness)
		shape.shape = box
		var centre := (from + to) * 0.5 + outward * (wall_thickness * 0.5)
		centre.y = (wall_top + wall_bottom) * 0.5
		shape.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), centre)
		_walls.add_child(shape)
		from = to


## Lines the walls with floats that ride the waves (see course/wall_float.gdshader).
func _build_wall_floats() -> void:
	var terrain: Terrain = null
	for child in get_children():
		if child is Terrain:
			terrain = child
	var spots := PackedVector2Array()
	for line in [_left_wall, _right_wall]:
		var points: PackedVector3Array = line
		var carried := 0.0
		for i in points.size():
			var a := points[i]
			var b := points[(i + 1) % points.size()]
			var span := a.distance_to(b)
			var along := float_spacing - carried
			while along <= span:
				var p := a.lerp(b, along / span)
				if terrain == null or terrain.height_at(p.x, p.z) < -float_min_depth:
					spots.append(Vector2(p.x, p.z))
				along += float_spacing
			carried = span - (along - float_spacing)
	if spots.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var mesh := SphereMesh.new()
	mesh.radius = 0.3
	mesh.height = 0.44
	mesh.radial_segments = 8
	mesh.rings = 4
	multimesh.mesh = mesh
	multimesh.instance_count = spots.size()
	for i in spots.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(spots[i].x, 0.0, spots[i].y)))
		multimesh.set_instance_color(i, float_colors[i % float_colors.size()] if not float_colors.is_empty() else Color.WHITE)
		multimesh.set_instance_custom_data(i, Color(spots[i].x, spots[i].y, 0.0, 0.0))
	_float_material = ShaderMaterial.new()
	_float_material.shader = preload("res://course/wall_float.gdshader")
	_floats = MultiMeshInstance3D.new()
	_floats.name = "WallFloats"
	_floats.multimesh = multimesh
	_floats.material_override = _float_material
	_floats.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_floats.layers = ShoreMap.DYNAMIC_LAYER
	# The waves move the floats up to a few meters from where the instances rest.
	var bounds := multimesh.get_aabb()
	_floats.custom_aabb = bounds.grow(4.0)
	add_child(_floats, false, Node.INTERNAL_MODE_BACK)
	Ocean.add_follower(_float_material)


func _update_preview() -> void:
	if not Engine.is_editor_hint() or not preview_in_editor:
		if _preview != null:
			_preview.queue_free()
			_preview = null
		return
	if _preview == null:
		_preview = MeshInstance3D.new()
		_preview.name = "Preview"
		_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_preview, false, Node.INTERNAL_MODE_BACK)
	_preview.mesh = build_layout_mesh()


## Lines showing the centre line (white), walls (orange), finish line and buoy gates, for
## the editor and for debugging.
func build_layout_mesh() -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	if _points.is_empty():
		return mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	var lift := Vector3.UP * 0.6
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	_add_loop(mesh, _points, Color(1.0, 1.0, 1.0, 1.0), lift)
	_add_loop(mesh, _left_wall, Color(1.0, 0.55, 0.1), lift)
	_add_loop(mesh, _right_wall, Color(1.0, 0.55, 0.1), lift)
	var all_gates: Array[CourseGate] = [finish_gate]
	all_gates.append_array(gates)
	for gate in all_gates:
		var color := Color.WHITE if gate.buoy == null else gate.buoy.color()
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(gate.position - gate.right * gate.reach_left + lift)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(gate.position + gate.right * gate.reach_right + lift)
	mesh.surface_end()
	return mesh


static func _add_loop(mesh: ImmediateMesh, line: PackedVector3Array, color: Color, lift: Vector3) -> void:
	for i in line.size():
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(line[i] + lift)
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(line[(i + 1) % line.size()] + lift)
