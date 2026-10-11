extends Node
## Autoload "Ocean": the water every system shares.
##
## It holds the active [WaveSet], the wave clock and the rest level of the water, and
## answers height and normal queries for physics. [OceanSurface] registers its wave set
## here and draws the same surface with the shader.
##
## The clock advances once per physics tick, before any other node's
## [method Node._physics_process], so physics and drawing see the same waves:
## [br]- Rigid bodies read [member time] in [method RigidBody3D._integrate_forces]: the time
##   of their state at the start of the step.
## [br]- Nodes placed by script in [method Node._physics_process] read [member end_time]: the
##   time their new position will be shown at.
## [br]- The shader draws at [method render_time], which follows physics interpolation.

## Emitted when [member wave_set] is replaced.
signal wave_set_changed

## The waves in use. Never null: a flat sea until a scene sets one.
var wave_set: WaveSet = WaveSet.new():
	set(value):
		wave_set = value if value != null else WaveSet.new()
		wave_set_changed.emit()

## Rest height of the water in world space. A course can raise or lower it between laps.
var level: float = 0.0

## Wave time of the physics state at the start of the current physics step, in seconds.
var time: float = 0.0

## Wave time at the end of the current physics step.
var end_time: float = 0.0


func _ready() -> void:
	# Run before every other node's _physics_process.
	process_physics_priority = -1000


func _physics_process(delta: float) -> void:
	time = end_time
	end_time += delta


## The wave time to draw the current frame at. With physics interpolation on, bodies are
## drawn between their last two physics states, so the water is too.
func render_time() -> float:
	if get_tree().physics_interpolation:
		return time + (end_time - time) * Engine.get_physics_interpolation_fraction()
	return end_time


## Sets the clock, for example when a race restarts. Both times take the value.
func reset_time(value: float = 0.0) -> void:
	time = value
	end_time = value


## World height of the water surface above [param world_position] at [member time].
func height_at(world_position: Vector3) -> float:
	return level + wave_set.height_at(world_position.x, world_position.z, time)


## World height of the water surface above [param world_position] at wave time [param t].
func height_at_time(world_position: Vector3, t: float) -> float:
	return level + wave_set.height_at(world_position.x, world_position.z, t)


## Height, normal, water velocity and fold above [param world_position] at [member time].
## Pass [param out] to reuse an object instead of allocating one.
func sample(world_position: Vector3, out: WaterSample = null) -> WaterSample:
	var result := wave_set.sample(world_position.x, world_position.z, time, out)
	result.height += level
	return result


## Like [method sample], at wave time [param t].
func sample_at_time(world_position: Vector3, t: float, out: WaterSample = null) -> WaterSample:
	var result := wave_set.sample(world_position.x, world_position.z, t, out)
	result.height += level
	return result


## How far [param world_position] is below the surface (negative when above it).
func depth_of(world_position: Vector3) -> float:
	return height_at(world_position) - world_position.y
