class_name Spray
extends Node3D
## Water thrown up by a jet ski, as GPU particles left behind in the world:
## [br]- a rooster tail from the jet nozzle while the jet bites the water;
## [br]- spray off both sides of the bow at speed;
## [br]- a sheet of spray off the outside of a carve or a slide;
## [br]- a splash at each touchdown, bigger the harder the landing.
## It reads the parent [JetSki]'s telemetry; the physics never reads it. The spray drifts
## with the wind ([member Ocean.wind]).

## The craft. Defaults to the parent.
@export var craft: JetSki
## Speed at which the bow spray and the rooster tail are at full strength.
@export_range(1.0, 40.0, 0.1, "suffix:m/s") var full_speed: float = 16.0
## How hard the wind ([member Ocean.wind]) pushes the spray: its acceleration per m/s of
## wind. Spray thrown at the craft's speed drifts downwind within its short life.
@export_range(0.0, 3.0, 0.01, "suffix:1/s") var wind_push: float = 0.8

var _tail: GPUParticles3D
var _bow_left: GPUParticles3D
var _bow_right: GPUParticles3D
var _carve_left: GPUParticles3D
var _carve_right: GPUParticles3D
var _splash: GPUParticles3D
var _draw_mesh: QuadMesh
var _material: ShaderMaterial
var _wind := Vector3.ZERO


func _ready() -> void:
	if craft == null:
		craft = get_parent() as JetSki
	_draw_mesh = _make_draw_mesh()
	# Rooster tail: up and back from the nozzle.
	_tail = _emitter("RoosterTail", Vector3(0.0, 0.25, 1.45), Vector3(0.0, 0.75, 0.65), 5.0, 3.5, 5.0, 0.5, 90, 0.22, 1.8, 0.95)
	# Bow spray: out and up from either side of the bow.
	_bow_left = _emitter("BowLeft", Vector3(-0.5, 0.45, -0.85), Vector3(-0.8, 1.0, 0.2), 15.0, 2.0, 3.0, 0.35, 40, 0.3, 1.4, 0.95)
	_bow_right = _emitter("BowRight", Vector3(0.5, 0.45, -0.85), Vector3(0.8, 1.0, 0.2), 15.0, 2.0, 3.0, 0.35, 40, 0.3, 1.4, 0.95)
	# Carving: a sheet off the outside of the turn, from the hull's side.
	_carve_left = _emitter("CarveLeft", Vector3(-0.6, 0.4, 0.1), Vector3(-0.9, 1.0, 0.3), 15.0, 3.0, 5.5, 0.55, 90, 0.45, 2.0, 0.85)
	_carve_right = _emitter("CarveRight", Vector3(0.6, 0.4, 0.1), Vector3(0.9, 1.0, 0.3), 15.0, 3.0, 5.5, 0.55, 90, 0.45, 2.0, 0.85)
	# Landing splash: a burst all round the hull.
	_splash = _emitter("Splash", Vector3(0.0, 0.35, 0.0), Vector3(0.0, 1.0, 0.0), 55.0, 2.0, 4.5, 0.7, 90, 0.3, 1.8, 0.5)
	_splash.one_shot = true
	_splash.explosiveness = 0.9
	_splash.emitting = false
	(_splash.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(_splash.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(0.5, 0.05, 1.3)
	if craft != null:
		craft.landed.connect(_on_landed)
		craft.crashed.connect(func(_reason: StringName) -> void: _burst(1.0))


func _process(_delta: float) -> void:
	if craft == null:
		return
	if not Ocean.wind.is_equal_approx(_wind):
		_wind = Ocean.wind
		var gravity := Vector3(_wind.x * wind_push, -9.8, _wind.z * wind_push)
		for emitter in [_tail, _bow_left, _bow_right, _carve_left, _carve_right, _splash]:
			((emitter as GPUParticles3D).process_material as ParticleProcessMaterial).gravity = gravity
	var wet := craft.contact > 0.2 and not craft.airborne
	var pace := clampf(craft.speed / full_speed, 0.0, 1.2)
	_drive(_tail, wet and craft.thrust > 0.2 and craft.speed > 1.5, clampf(craft.thrust * (0.35 + 0.65 * pace), 0.0, 1.0))
	var bow := pace * pace if wet and craft.speed > 4.0 else 0.0
	_drive(_bow_left, bow > 0.05, bow)
	_drive(_bow_right, bow > 0.05, bow)
	# The spray comes off the outside of the turn: the side the craft slides toward.
	var turning := wet and (craft.carving or craft.sliding or absf(craft.slip_angle) > 0.2) and craft.speed > 6.0
	var strength := clampf(absf(craft.slip_angle) / 0.35, 0.4, 1.0) if turning else 0.0
	var outside_right := craft.side_speed > 0.0
	_drive(_carve_right, turning and outside_right, strength)
	_drive(_carve_left, turning and not outside_right, strength)


func _drive(emitter: GPUParticles3D, on: bool, ratio: float) -> void:
	emitter.amount_ratio = clampf(ratio, 0.0, 1.0)
	if emitter.emitting != on:
		emitter.emitting = on


func _on_landed(quality: StringName, _stunts: Array[StringName], _points: int) -> void:
	_burst(1.0 if quality != &"clean" else 0.6)


## Throws a splash: [param size] 0 to 1.
func _burst(size: float) -> void:
	var material := _splash.process_material as ParticleProcessMaterial
	material.initial_velocity_min = 2.0 + 2.0 * size
	material.initial_velocity_max = 4.0 + 5.0 * size
	_splash.amount_ratio = clampf(0.4 + 0.6 * size, 0.0, 1.0)
	_splash.restart()
	_splash.emitting = true


func _emitter(node_name: String, at: Vector3, direction: Vector3, spread: float, speed_min: float,
		speed_max: float, lifetime: float, amount: int, size: float, grow: float, inherit: float) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = node_name
	particles.position = at
	particles.amount = amount
	particles.lifetime = lifetime
	particles.local_coords = false
	# Every frame, not the default 30 fps: a fast emitter otherwise drops its particles in rows.
	particles.fixed_fps = 0
	particles.emitting = false
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	particles.layers = ShoreMap.DYNAMIC_LAYER
	particles.visibility_aabb = AABB(Vector3(-12, -6, -12), Vector3(24, 16, 24))
	var material := ParticleProcessMaterial.new()
	# A small box of spawn points along the hull breaks up the rows between frames.
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(0.08, 0.04, 0.25)
	material.direction = direction.normalized()
	material.spread = spread
	material.initial_velocity_min = speed_min
	material.initial_velocity_max = speed_max
	material.gravity = Vector3(0.0, -9.8, 0.0)
	material.inherit_velocity_ratio = inherit
	material.damping_min = 0.5
	material.damping_max = 1.5
	material.scale_min = size
	material.scale_max = size * 1.6
	var scale_curve := Curve.new()
	scale_curve.max_value = 4.0
	scale_curve.add_point(Vector2(0.0, 0.6))
	scale_curve.add_point(Vector2(1.0, grow))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = scale_curve
	material.scale_curve = scale_texture
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.7))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	ramp.add_point(0.6, Color(1, 1, 1, 0.5))
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = ramp
	material.color_ramp = ramp_texture
	particles.process_material = material
	particles.draw_pass_1 = _draw_mesh
	add_child(particles)
	return particles


## A soft round billboard, lit so the spray darkens at night, fading out at the water and
## near the camera ([code]spray.gdshader[/code]).
func _make_draw_mesh() -> QuadMesh:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.4, Color(1, 1, 1, 0.8))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_material = ShaderMaterial.new()
	_material.shader = preload("res://effects/spray.gdshader")
	_material.set_shader_parameter(&"puff", texture)
	# Drawn over the water, which is in the transparent pass too.
	_material.render_priority = 2
	Ocean.add_follower(_material)
	var quad := QuadMesh.new()
	quad.material = _material
	return quad


func _exit_tree() -> void:
	if _material != null:
		Ocean.remove_follower(_material)
