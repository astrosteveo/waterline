class_name PlayerInput
extends Node
## Reads the Input Map each physics tick and writes the rider's controls into the parent
## [JetSki]. Keyboard steering is digital, so it is eased in over [member steer_rise_time]
## to make small corrections possible.

## Seconds a digital steer or lean takes to go from 0 to full.
@export_range(0.0, 1.0, 0.01, "suffix:s") var steer_rise_time: float = 0.12
## Seconds to return to centre after letting go.
@export_range(0.0, 1.0, 0.01, "suffix:s") var steer_fall_time: float = 0.08
@export_range(0.0, 1.0, 0.01, "suffix:s") var lean_rise_time: float = 0.15
## When false, the craft gets no input (for example while the free camera is in use).
@export var enabled: bool = true

var _craft: JetSki


func _ready() -> void:
	_craft = get_parent() as JetSki
	if _craft == null:
		push_error("PlayerInput must be a child of a JetSki.")


func _physics_process(delta: float) -> void:
	if _craft == null:
		return
	var controls := _craft.controls
	if not enabled:
		controls.clear()
		return
	controls.throttle = Input.get_action_strength(&"throttle")
	controls.steer = _ease(controls.steer, Input.get_axis(&"steer_left", &"steer_right"), delta,
			steer_rise_time, steer_fall_time)
	controls.lean = _ease(controls.lean, Input.get_axis(&"lean_back", &"lean_forward"), delta,
			lean_rise_time, steer_fall_time)
	if Input.is_action_just_pressed(&"stunt"):
		# The direction held as the button goes down picks the stunt; the raw axes, not the
		# eased steer and lean, so a key pressed together with it counts.
		controls.request_stunt(Vector2(Input.get_axis(&"steer_left", &"steer_right"),
				Input.get_axis(&"lean_back", &"lean_forward")))
	if Input.is_action_just_pressed(&"reset_craft"):
		_craft.request_reset()


## Moves [param current] toward [param target], taking [param rise] seconds for a full
## swing away from centre and [param fall] seconds back toward it.
func _ease(current: float, target: float, delta: float, rise: float, fall: float) -> float:
	var returning := is_zero_approx(target) or (current != 0.0 and signf(target) != signf(current))
	var time := fall if returning else rise
	if time <= 0.0:
		return target
	return move_toward(current, target, delta / time)
