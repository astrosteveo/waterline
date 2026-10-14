class_name CourseConditions
extends Resource
## The water, sky and tide to race a course in, set on top of what its scene sets.
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


## True when no field is set, so [method apply_to] changes nothing.
func is_empty() -> bool:
	return wave_set == null and environment == null and water_overrides.is_empty() and lap_levels.is_empty()


## Sets the fields that aren't empty on [param course] and its OceanSurface and
## WorldEnvironment. Call it before the course enters the tree, so the water and the tide
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


## The first node under [param root], depth first, that [param test] accepts, or null.
static func _find(root: Node, test: Callable) -> Node:
	for child in root.get_children():
		if test.call(child):
			return child
		var found := _find(child, test)
		if found != null:
			return found
	return null
