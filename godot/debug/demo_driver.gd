class_name DemoDriver
extends Node
## Rides the craft through a fixed sequence of controls, for recordings and for watching
## the physics without a controller. It runs when the game is started with the user
## argument [code]--demo[/code] (for example [code]godot --path . -- --demo[/code]), or
## when [member enabled] is set.

@export var craft: JetSki
@export var enabled: bool = false
## Each step: Vector4(seconds, throttle, steer, lean). The sequence repeats.
@export var sequence: Array[Vector4] = [
	Vector4(4.0, 1.0, 0.0, 0.0),
	Vector4(1.6, 1.0, -1.0, 0.0),
	Vector4(3.0, 1.0, 0.0, -0.4),
	Vector4(1.2, 1.0, 1.0, 1.0),
	Vector4(3.0, 1.0, 0.0, 0.0),
	Vector4(2.0, 1.0, 0.6, -0.6),
	Vector4(1.5, 0.0, 0.0, 0.0),
	Vector4(3.0, 1.0, -0.3, 0.3),
]

var _time := 0.0


func _ready() -> void:
	# Run after PlayerInput, so these controls win.
	process_physics_priority = 10
	if "--demo" in OS.get_cmdline_user_args():
		enabled = true


func _physics_process(delta: float) -> void:
	if not enabled or craft == null or sequence.is_empty():
		return
	var total := 0.0
	for item in sequence:
		total += item.x
	var t := fmod(_time, total)
	for item in sequence:
		if t < item.x:
			craft.controls.throttle = item.y
			craft.controls.steer = item.z
			craft.controls.lean = item.w
			break
		t -= item.x
	_time += delta
