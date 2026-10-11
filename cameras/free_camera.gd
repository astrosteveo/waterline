class_name FreeCamera
extends Camera3D
## A fly camera for looking around a scene.
##
## Hold the right mouse button (cam_look) and move the mouse to look, or use the right
## stick. Move with cam_forward, cam_back, cam_left and cam_right (W, S, A, D), rise and
## sink with cam_up and cam_down (E, Q), hold cam_fast (Shift) to go faster, and turn
## the mouse wheel (cam_speed_up, cam_speed_down) to change the base speed.

@export_range(0.5, 200.0, 0.1, "suffix:m/s") var move_speed: float = 15.0
@export_range(1.0, 20.0, 0.1) var fast_multiplier: float = 4.0
@export_range(0.0001, 0.02, 0.0001) var mouse_sensitivity: float = 0.0025
@export_range(0.1, 10.0, 0.1, "suffix:rad/s") var stick_look_speed: float = 2.0
## How quickly the camera reaches its target speed; higher is snappier.
@export_range(0.5, 50.0, 0.1) var acceleration: float = 10.0

var _yaw := 0.0
var _pitch := 0.0
var _velocity := Vector3.ZERO


func _ready() -> void:
	# Moved in _process, so not interpolated between physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event.is_action_pressed(&"cam_look"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_released(&"cam_look"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed(&"cam_speed_up"):
		move_speed = minf(move_speed * 1.25, 200.0)
	elif event.is_action_pressed(&"cam_speed_down"):
		move_speed = maxf(move_speed / 1.25, 0.5)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * mouse_sensitivity
		_pitch = clampf(_pitch - motion.relative.y * mouse_sensitivity, -1.55, 1.55)


func _process(delta: float) -> void:
	if not current:
		return
	var look := Input.get_vector(&"cam_look_left", &"cam_look_right", &"cam_look_up", &"cam_look_down")
	_yaw -= look.x * stick_look_speed * delta
	_pitch = clampf(_pitch - look.y * stick_look_speed * delta, -1.55, 1.55)
	rotation = Vector3(_pitch, _yaw, 0.0)

	var move := Input.get_vector(&"cam_left", &"cam_right", &"cam_forward", &"cam_back")
	var rise := Input.get_axis(&"cam_down", &"cam_up")
	var direction := global_basis * Vector3(move.x, 0.0, move.y) + Vector3.UP * rise
	var speed := move_speed * (fast_multiplier if Input.is_action_pressed(&"cam_fast") else 1.0)
	_velocity = _velocity.lerp(direction.limit_length(1.0) * speed, 1.0 - exp(-acceleration * delta))
	global_position += _velocity * delta


## Points the camera from [param from] toward [param target] and keeps that view.
func look_from(from: Vector3, target: Vector3) -> void:
	global_position = from
	look_at(target, Vector3.UP)
	_yaw = rotation.y
	_pitch = rotation.x
	_velocity = Vector3.ZERO
