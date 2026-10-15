extends Node
## Checks [method CourseConditions.apply_to] on real course scenes: each field it sets (the
## sun and per-lap waves among them), the
## fields it leaves to the scene, water overrides added to the scene's own, and a change to a
## course already in the tree. Run it with gdh (test/scenarios/course_conditions.scenario.json):
## step until [member done], then check that [member failures] is empty.

const GULL_COVE := "res://levels/gull_cove.tscn"
const LANTERN_HARBOR := "res://levels/lantern_harbor.tscn"
const COVE_CALM := "res://water/presets/cove_calm.tres"
const COVE_SWELL := "res://water/presets/cove_swell.tres"
const DAY := "res://environment/day_environment.tres"
const NIGHT := "res://environment/night_environment.tres"
const WATER := "res://water/ocean_material.tres"

## True once every check has run.
var done: bool = false
## Each check that failed, as a line of text.
var failures: PackedStringArray = PackedStringArray()
## The names of the checks that ran.
var checks: PackedStringArray = PackedStringArray()

var _course: Course


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var shared_deep: Variant = (load(WATER) as ShaderMaterial).get_shader_parameter(&"deep_color")

	# Every field set, before the course enters the tree.
	var all := CourseConditions.new()
	all.wave_set = load(COVE_SWELL) as WaveSet
	all.environment = load(NIGHT) as Environment
	all.water_overrides = {"deep_color": Color(0.5, 0.1, 0.1)}
	all.lap_levels = PackedFloat32Array([-0.4, -0.8])
	var swell := load(COVE_SWELL) as WaveSet
	all.lap_waves = [null, swell] as Array[WaveSet]
	all.sun_light_color = Color(0.6, 0.7, 1.0)
	all.sun_light_energy = 0.5
	all.sun_direction = Vector3(1, 1, 0)
	_load(GULL_COVE, all)
	await get_tree().physics_frame
	var surface := _surface()
	_check("waves", [surface.wave_set.resource_path, Ocean.wave_set.resource_path], [COVE_SWELL, COVE_SWELL])
	_check("sky", _world().environment.resource_path, NIGHT)
	_check("water", surface.water_material.get_shader_parameter(&"deep_color"), Color(0.5, 0.1, 0.1))
	_check("water file untouched", (load(WATER) as ShaderMaterial).get_shader_parameter(&"deep_color"), shared_deep)
	_check("tide", [Array(_course.lap_levels), Ocean.level], [[-0.4, -0.8], -0.4])
	_check("lap waves", [_course.lap_waves.size(), _course.waves_for_lap(0), _course.waves_for_lap(2) == swell],
			[2, null, true])
	_check("sun light", [_sun().light_color, _sun().light_energy, _sun().visible], [Color(0.6, 0.7, 1.0), 0.5, true])
	var toward := Vector3(1, 1, 0).normalized()
	# The sun lies along the light's +Z, which Sun publishes to the water and sky.
	_check("sun direction", _sun().global_basis.z.normalized().is_equal_approx(toward), true)
	var fresh := (load(GULL_COVE) as PackedScene).instantiate() as Course
	_check("course scene file untouched", [fresh.lap_levels.size(), fresh.lap_waves.size(),
			(fresh.get_node(^"Sun") as DirectionalLight3D).light_energy], [0, 0, 1.25])
	fresh.free()

	# No field set: the scene's own conditions.
	_load(GULL_COVE, CourseConditions.new())
	await get_tree().physics_frame
	surface = _surface()
	_check("empty keeps the waves", [surface.wave_set.resource_path, Ocean.wave_set.resource_path], [COVE_CALM, COVE_CALM])
	_check("empty keeps the sky", _world().environment.resource_path, DAY)
	_check("empty keeps the water", [surface.water_material.resource_path, surface.shader_overrides], [WATER, {}])
	_check("empty keeps the tide", [_course.lap_levels.size(), Ocean.level], [0, 0.0])
	_check("empty keeps the sun", [_sun().light_color, _sun().light_energy, _sun().visible,
			_sun().basis.is_equal_approx(_scene_sun_basis(GULL_COVE))], [Color(1, 0.96, 0.88), 1.25, true, true])
	_check("empty is empty", CourseConditions.new().is_empty(), true)

	# A sun turned off; only its energy changes.
	var dark := CourseConditions.new()
	dark.sun_light_energy = 0.0
	_check("a sun override isn't empty", dark.is_empty(), false)
	_load(LANTERN_HARBOR, dark)
	await get_tree().physics_frame
	_check("sun off", [_sun().light_energy, _sun().visible, _sun().light_color], [0.0, false, Color(0.6, 0.7, 1)])

	# Water overrides add to the scene's own.
	var crest := CourseConditions.new()
	crest.water_overrides = {"crest_strength": 0.4}
	_load(LANTERN_HARBOR, crest)
	await get_tree().physics_frame
	surface = _surface()
	_check("override replaces the scene's value", surface.water_material.get_shader_parameter(&"crest_strength"), 0.4)
	_check("the scene's other overrides stay", surface.water_material.get_shader_parameter(&"deep_color"), Color(0.04, 0.13, 0.28, 1))

	# Applied to a course already in the tree.
	var later := CourseConditions.new()
	later.wave_set = load(COVE_SWELL) as WaveSet
	later.environment = load(NIGHT) as Environment
	later.water_overrides = {"deep_color": Color(0.1, 0.5, 0.1)}
	later.sun_light_energy = 0.3
	later.sun_direction = Vector3(0, 1, 0)
	_load(GULL_COVE, null)
	await get_tree().physics_frame
	later.apply_to(_course)
	surface = _surface()
	_check("in the tree: waves", [surface.wave_set.resource_path, Ocean.wave_set.resource_path], [COVE_SWELL, COVE_SWELL])
	_check("in the tree: sky", _world().environment.resource_path, NIGHT)
	_check("in the tree: water", [surface.material_override == surface.water_material,
			surface.water_material.get_shader_parameter(&"deep_color")], [true, Color(0.1, 0.5, 0.1)])
	_check("in the tree: sun", [_sun().light_energy, _sun().global_basis.z.normalized().is_equal_approx(Vector3.UP)],
			[0.3, true])
	_check("in the tree: water file untouched", (load(WATER) as ShaderMaterial).get_shader_parameter(&"deep_color"), shared_deep)

	_course.queue_free()
	_course = null
	done = true
	print("course conditions: %s" % ("passed" if failures.is_empty() else "FAILED\n  " + "\n  ".join(failures)))


## Replaces the course under test with a new instance of [param path], with [param conditions]
## applied before it enters the tree.
func _load(path: String, conditions: CourseConditions) -> void:
	if _course != null:
		remove_child(_course)
		_course.free()
	_course = (load(path) as PackedScene).instantiate() as Course
	if conditions != null:
		conditions.apply_to(_course)
	add_child(_course)


func _surface() -> OceanSurface:
	return _course.get_node(^"OceanSurface") as OceanSurface


func _sun() -> DirectionalLight3D:
	return _course.get_node(^"Sun") as DirectionalLight3D


## The basis of the sun in a fresh instance of the scene at [param path].
func _scene_sun_basis(path: String) -> Basis:
	var fresh := (load(path) as PackedScene).instantiate() as Course
	var basis := (fresh.get_node(^"Sun") as DirectionalLight3D).basis
	fresh.free()
	return basis


func _world() -> WorldEnvironment:
	return _course.get_node(^"WorldEnvironment") as WorldEnvironment


func _check(name: String, actual: Variant, expected: Variant) -> void:
	checks.append(name)
	if not _same(actual, expected):
		failures.append("%s: got %s, expected %s" % [name, actual, expected])


static func _same(a: Variant, b: Variant) -> bool:
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in a.size():
			if not _same(a[i], b[i]):
				return false
		return true
	if (a is float or a is int) and (b is float or b is int):
		return is_equal_approx(float(a), float(b))
	if a is Color and b is Color:
		return a.is_equal_approx(b)
	return a == b
