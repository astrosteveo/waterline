@tool
class_name OceanSurface
extends MeshInstance3D
## Draws the ocean and makes its waves the ones physics uses.
##
## The mesh is a square grid that follows the active camera. Its middle keeps a uniform
## vertex spacing and moves in whole steps of that spacing, so vertices stay on a fixed
## world lattice and the waves don't swim; past it the vertex rings spread out toward the
## horizon (see ocean_grid_offset() in gerstner.gdshaderinc). On ready, the node hands its
## [member wave_set] to the Ocean autoload, which the jet skis and buoys query.

## The waves to draw and simulate.
@export var wave_set: WaveSet:
	set(value):
		if wave_set != null and wave_set.changed.is_connected(_on_wave_set_changed):
			wave_set.changed.disconnect(_on_wave_set_changed)
		wave_set = value
		if wave_set != null and not wave_set.changed.is_connected(_on_wave_set_changed):
			wave_set.changed.connect(_on_wave_set_changed)
		_on_wave_set_changed()
		if is_inside_tree() and not Engine.is_editor_hint():
			Ocean.wave_set = wave_set

## The water's look. It must use res://water/ocean.gdshader.
@export var water_material: ShaderMaterial:
	set(value):
		water_material = value
		material_override = value
		_push_static_uniforms()

@export_group("Grid")
## Grid cells along each side of the mesh. The vertex count is about this squared.
@export_range(64, 2048, 2) var grid_cells: int = 1024:
	set(value):
		grid_cells = value
		_rebuild_mesh()
## Vertex spacing in meters in the uniform middle of the grid.
@export_range(0.05, 4.0, 0.01, "suffix:m") var inner_spacing: float = 0.3:
	set(value):
		inner_spacing = value
		_rebuild_mesh()
## Share of the grid's half-width that keeps the uniform spacing.
@export_range(0.05, 0.9, 0.01) var inner_fraction: float = 0.25:
	set(value):
		inner_fraction = value
		_rebuild_mesh()
## Distance in meters to the outer edge of the grid.
@export_range(100.0, 50000.0, 1.0, "suffix:m") var outer_radius: float = 6000.0:
	set(value):
		outer_radius = value
		_rebuild_mesh()
## Keep the grid centred under the active camera while the game runs.
@export var follow_camera: bool = true

## The wave time the last frame was drawn at.
var last_render_time: float = 0.0

var _editor_time := 0.0


func _ready() -> void:
	# The grid moves in _process, under the camera, so it isn't interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = water_material
	_rebuild_mesh()
	_on_wave_set_changed()
	if not Engine.is_editor_hint() and wave_set != null:
		Ocean.wave_set = wave_set


func _process(delta: float) -> void:
	var t := 0.0
	if Engine.is_editor_hint():
		_editor_time += delta
		t = _editor_time
	else:
		t = Ocean.render_time()
		if follow_camera:
			_follow(get_viewport().get_camera_3d())
		global_position.y = Ocean.level
	if water_material != null and wave_set != null:
		water_material.set_shader_parameter(&"wave_phase", wave_set.get_shader_wave_phases(t))
		water_material.set_shader_parameter(&"ripple_time", t)
	last_render_time = t


## Moves the grid under [param camera] in whole steps of the inner spacing.
func _follow(camera: Camera3D) -> void:
	if camera == null:
		return
	var at := camera.global_position
	global_position = Vector3(snappedf(at.x, inner_spacing), global_position.y, snappedf(at.z, inner_spacing))


func _rebuild_mesh() -> void:
	# Setters run while the scene loads; _ready builds the mesh once after that.
	if not is_node_ready():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	plane.subdivide_width = grid_cells - 1
	plane.subdivide_depth = grid_cells - 1
	mesh = plane
	# The shader moves vertices far outside the 2 x 2 plane: cull by the real extent.
	var reach := outer_radius + 10.0
	var rise := 20.0
	if wave_set != null:
		rise = wave_set.max_height() + 5.0
	custom_aabb = AABB(Vector3(-reach, -rise, -reach), Vector3(reach * 2.0, rise * 2.0, reach * 2.0))
	_push_static_uniforms()


func _push_static_uniforms() -> void:
	if water_material == null:
		return
	water_material.set_shader_parameter(&"grid_cells", float(grid_cells))
	water_material.set_shader_parameter(&"inner_fraction", inner_fraction)
	water_material.set_shader_parameter(&"inner_spacing", inner_spacing)
	water_material.set_shader_parameter(&"outer_radius", outer_radius)


func _on_wave_set_changed() -> void:
	if water_material == null:
		return
	if wave_set == null:
		water_material.set_shader_parameter(&"wave_count", 0)
		return
	var data := wave_set.get_shader_wave_data()
	water_material.set_shader_parameter(&"wave_count", data["count"])
	water_material.set_shader_parameter(&"wave_dir_k", data["wave_dir_k"])
	water_material.set_shader_parameter(&"wave_shape", data["wave_shape"])
	water_material.set_shader_parameter(&"max_wave_height", maxf(wave_set.max_height(), 0.01))
	water_material.set_shader_parameter(&"wave_phase", wave_set.get_shader_wave_phases(Ocean.render_time() if not Engine.is_editor_hint() else _editor_time))
	if wave_set.max_fold() >= 0.95:
		push_warning("WaveSet folds over itself (max fold %.2f); keep it below 0.9." % wave_set.max_fold())
