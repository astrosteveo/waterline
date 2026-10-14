class_name Rain
extends GPUParticles3D
## Rain around the active camera: GPU particles left in the world, falling at a steady
## speed and drifting with the wind, drawn as streaks that fade out above the water
## ([code]rain.gdshader[/code]). The emitter moves ahead of the camera by the camera's own
## speed, so a fast chase camera stays inside the rain.

## How hard it rains, from 0 (none) to 1 (every drop).
var strength: float = 0.0:
	set(value):
		strength = clampf(value, 0.0, 1.0)
		amount_ratio = strength
		var on := strength > 0.001
		if emitting != on:
			emitting = on
## The wind, in m/s. The drops fall at [member fall_speed] and move with it.
var wind: Vector3 = Vector3.ZERO:
	set(value):
		if value.is_equal_approx(wind):
			return
		wind = value
		_update_velocity()

## The drops' colour. They are unshaded, so give them the light of the sky: [RaceWeather]
## sets the fog's colour, a little brighter.
var colour: Color = Color(0.5, 0.52, 0.55):
	set(value):
		colour = value
		if _material != null:
			_material.set_shader_parameter(&"tint", colour)

## Drops at full strength.
@export var drops: int = 10000
## How fast a drop falls, in m/s.
@export var fall_speed: float = 9.0
## How far above the camera the drops start, in meters.
@export var height: float = 9.0
## Half the width of the area the drops start in, in meters.
@export var reach: float = 22.0

var _material: ShaderMaterial
var _process_material: ParticleProcessMaterial
var _camera_last := Vector3.INF
var _camera_velocity := Vector3.ZERO


func _ready() -> void:
	amount = drops
	amount_ratio = strength
	emitting = strength > 0.001
	local_coords = false
	fixed_fps = 0
	# Each drop falls past the camera to the water: the rain's height plus a few meters.
	lifetime = (height + 6.0) / fall_speed
	preprocess = lifetime
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = ShoreMap.DYNAMIC_LAYER
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	visibility_aabb = AABB(Vector3(-reach - 20.0, -height - 30.0, -reach - 20.0),
			Vector3(reach * 2.0 + 40.0, height + 60.0, reach * 2.0 + 40.0))
	_process_material = ParticleProcessMaterial.new()
	_process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_process_material.emission_box_extents = Vector3(reach, 0.5, reach)
	_process_material.gravity = Vector3.ZERO
	_process_material.spread = 2.0
	_process_material.scale_min = 0.8
	_process_material.scale_max = 1.2
	process_material = _process_material
	_material = ShaderMaterial.new()
	_material.shader = preload("res://effects/rain.gdshader")
	# Drawn over the water, which is in the transparent pass too.
	_material.render_priority = 2
	_material.set_shader_parameter(&"tint", colour)
	Ocean.add_follower(_material)
	var quad := QuadMesh.new()
	quad.material = _material
	draw_pass_1 = quad
	_update_velocity()


func _exit_tree() -> void:
	if _material != null:
		Ocean.remove_follower(_material)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var at := camera.global_position
	if _camera_last != Vector3.INF and delta > 0.0:
		var measured := (at - _camera_last) / delta
		# A camera cut would throw the rain far away for a moment.
		if measured.length() < 80.0:
			_camera_velocity = _camera_velocity.lerp(measured, clampf(delta * 3.0, 0.0, 1.0))
	_camera_last = at
	# A drop takes this long to fall to the camera's height, so start it where the camera
	# will be by then, upwind by as far as the wind carries it.
	var fall_time := height / fall_speed
	global_position = at + Vector3(_camera_velocity.x, 0.0, _camera_velocity.z) * fall_time \
			- wind * fall_time + Vector3.UP * height


func _update_velocity() -> void:
	if _process_material == null:
		return
	var velocity := wind + Vector3.DOWN * fall_speed
	_process_material.direction = velocity.normalized()
	_process_material.initial_velocity_min = velocity.length()
	_process_material.initial_velocity_max = velocity.length()
	_material.set_shader_parameter(&"fall_velocity", velocity)
