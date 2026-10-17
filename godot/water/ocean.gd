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

## Emitted when [member wave_set] is replaced or its waves change. [OceanSurface] follows
## a replaced set, so a script can change the waves through [member wave_set] or
## [method change_waves] alone.
signal wave_set_changed

## The waves in use. Never null: a flat sea until a scene sets one.
var wave_set: WaveSet = WaveSet.new():
	set(value):
		if wave_set.changed.is_connected(_on_waves_changed):
			wave_set.changed.disconnect(_on_waves_changed)
		wave_set = value if value != null else WaveSet.new()
		wave_set.changed.connect(_on_waves_changed)
		_on_waves_changed()

## Rest height of the water in world space. A course can raise or lower it between laps.
var level: float = 0.0

## The wind over the water, as a horizontal velocity in m/s. Spray and rain drift with it;
## a race's weather ([RaceWeather]) sets it, and each new scene starts calm.
var wind: Vector3 = Vector3.ZERO

## Wave time of the physics state at the start of the current physics step, in seconds.
var time: float = 0.0

## Wave time at the end of the current physics step.
var end_time: float = 0.0

var _followers: Array[ShaderMaterial] = []


func _ready() -> void:
	# Run before every other node's _physics_process.
	process_physics_priority = -1000


func _physics_process(delta: float) -> void:
	time = end_time
	end_time += delta
	# Every query from now on is at or after the end, so dropping the faded waves changes
	# nothing anyone sees.
	if wave_set.is_changing() and time >= wave_set.change_end():
		wave_set.finish_change()


func _process(_delta: float) -> void:
	var t := render_time()
	# For shaders that move with the game's time and the wind (palms swaying): unlike TIME,
	# game_time stops while the game is paused or held.
	RenderingServer.global_shader_parameter_set(&"game_time", t)
	RenderingServer.global_shader_parameter_set(&"wind", wind)
	if _followers.is_empty():
		return
	var phases := wave_set.get_shader_wave_phases(t)
	var changing := wave_set.is_changing()
	var shapes := wave_set.get_shader_wave_shapes(t) if changing else PackedVector4Array()
	for material in _followers:
		material.set_shader_parameter(&"wave_phase", phases)
		material.set_shader_parameter(&"water_level", level)
		if changing:
			material.set_shader_parameter(&"wave_shape", shapes)


## Changes the waves into [param target]'s over [param duration] seconds of wave time,
## starting now: only the amplitudes change (see [method WaveSet.changing_to]). The water
## works on a copy, so [param target] and the current set stay as they are, and the
## change depends only on [member time], so a race replayed from the same start sees the
## same water. Calling it again during a change starts the new one from where the waves
## are.
func change_waves(target: WaveSet, duration: float) -> void:
	# From the end of this step: anything that already read the water this step read the
	# old waves at a time the new set gives the same heights for.
	wave_set = wave_set.changing_to(target, end_time, duration)


## Keeps [param material]'s wave uniforms (wave_count, wave_dir_k, wave_shape, wave_phase
## and water_level) in step with the water every frame, so a shader that includes
## res://water/gerstner.gdshaderinc can move things with the drawn waves.
func add_follower(material: ShaderMaterial) -> void:
	if material in _followers:
		return
	_followers.append(material)
	_push_wave_data(material)


## Stops updating [param material].
func remove_follower(material: ShaderMaterial) -> void:
	_followers.erase(material)


func _on_waves_changed() -> void:
	for material in _followers:
		_push_wave_data(material)
	wave_set_changed.emit()


func _push_wave_data(material: ShaderMaterial) -> void:
	var data := wave_set.get_shader_wave_data()
	material.set_shader_parameter(&"wave_count", data["count"])
	material.set_shader_parameter(&"wave_dir_k", data["wave_dir_k"])
	material.set_shader_parameter(&"wave_shape", wave_set.get_shader_wave_shapes(render_time()))
	material.set_shader_parameter(&"wave_phase", wave_set.get_shader_wave_phases(render_time()))
	material.set_shader_parameter(&"water_level", level)


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
