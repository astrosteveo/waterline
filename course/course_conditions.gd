class_name CourseConditions
extends Resource
## The water, sky, sun and tide to race a course in, set on top of what its scene sets.
##
## Each field is optional: an empty one leaves the scene's own value. [CourseInfo] holds
## one to ship a layout in other conditions (Gull Cove in rough water) as a course of its
## own. [method apply_to] sets them on a course scene; [Race] calls it after it loads the
## course and before the racers spawn.

## The waves to draw and simulate instead of the scene's [member OceanSurface.wave_set].
@export var wave_set: WaveSet
## The sky, fog and ambient light instead of the scene's [WorldEnvironment]'s.
@export var environment: Environment
## Water shader parameters, as {name: value}, set on top of the scene's
## [member OceanSurface.shader_overrides]: a key here replaces the scene's value for that key,
## and the scene's other keys stay.
@export var water_overrides: Dictionary = {}
## The water's rest level on each lap instead of the scene's [member Course.lap_levels].
@export var lap_levels: PackedFloat32Array = PackedFloat32Array()
## The waves on each lap instead of the scene's [member Course.lap_waves]. An empty entry
## keeps the waves of the lap before, as it does there.
@export var lap_waves: Array[WaveSet] = []

@export_group("Sun")
## The sun's (or moon's) light colour instead of the scene's. Transparent keeps the scene's.
@export var sun_light_color: Color = Color(0, 0, 0, 0)
## The sun's light energy instead of the scene's: 0 turns the sun off. Negative keeps the
## scene's.
@export_range(-1.0, 4.0, 0.01, "or_greater") var sun_light_energy: float = -1.0
## Where the sun is in the sky, as a direction from the course toward it (+Y is straight
## up). Zero keeps the scene's.
@export var sun_direction: Vector3 = Vector3.ZERO


## True when no field is set, so [method apply_to] changes nothing.
func is_empty() -> bool:
	return (wave_set == null and environment == null and water_overrides.is_empty() and lap_levels.is_empty()
			and lap_waves.is_empty() and sun_light_color.a == 0.0 and sun_light_energy < 0.0
			and sun_direction == Vector3.ZERO)


## Sets the fields that aren't empty on [param course] and its OceanSurface,
## WorldEnvironment and sun (its first [DirectionalLight3D]). Call it before the course enters the tree, so the water and the tide
## start from these values. It also works on a course already in the tree: the waves,
## the sky and the water change at once, and the race moves the level toward the new
## tide's level.
func apply_to(course: Course) -> void:
	if wave_set != null or not water_overrides.is_empty():
		var surface := _find(course, func(node: Node) -> bool: return node is OceanSurface) as OceanSurface
		if surface == null:
			push_error("%s has no OceanSurface for the course's waves and water." % course.name)
		else:
			if wave_set != null:
				surface.wave_set = wave_set
			if not water_overrides.is_empty():
				surface.shader_overrides = surface.shader_overrides.merged(water_overrides, true)
	if environment != null:
		var world := _find(course, func(node: Node) -> bool: return node is WorldEnvironment) as WorldEnvironment
		if world == null:
			push_error("%s has no WorldEnvironment for the course's sky." % course.name)
		else:
			world.environment = environment
	if not lap_levels.is_empty():
		course.lap_levels = lap_levels
	if not lap_waves.is_empty():
		course.lap_waves = lap_waves
	if sun_light_color.a > 0.0 or sun_light_energy >= 0.0 or sun_direction != Vector3.ZERO:
		var sun := _find(course, func(node: Node) -> bool: return node is DirectionalLight3D) as DirectionalLight3D
		if sun == null:
			push_error("%s has no DirectionalLight3D for the course's sun." % course.name)
		else:
			_apply_sun(sun)


func _apply_sun(sun: DirectionalLight3D) -> void:
	if sun_light_color.a > 0.0:
		sun.light_color = Color(sun_light_color, 1.0)
	if sun_light_energy >= 0.0:
		sun.light_energy = sun_light_energy
		sun.visible = sun_light_energy > 0.0
	if sun_direction != Vector3.ZERO:
		# A DirectionalLight3D shines along its -Z axis, so the sun lies along +Z. The course
		# root sits at the origin unturned, so the sun's own basis is its basis in the world.
		var toward := sun_direction.normalized()
		var up := Vector3.FORWARD if absf(toward.y) > 0.999 else Vector3.UP
		sun.basis = Basis.looking_at(-toward, up)


## The first node under [param root], depth first, that [param test] accepts, or null.
static func _find(root: Node, test: Callable) -> Node:
	for child in root.get_children():
		if test.call(child):
			return child
		var found := _find(child, test)
		if found != null:
			return found
	return null
