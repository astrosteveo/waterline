class_name CameraSwitcher
extends Node
## Swaps between the chase camera and the free camera on the toggle_camera action. While
## the free camera flies, the player's craft gets no input, since both use the same keys.

@export var chase_camera: Camera3D
@export var free_camera: FreeCamera
## The player's input node, switched off while the free camera is in use.
@export var player_input: PlayerInput


func _ready() -> void:
	if chase_camera != null:
		chase_camera.make_current()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_camera"):
		toggle()


## Switches to the other camera. The free camera starts where the chase camera is.
func toggle() -> void:
	if chase_camera == null or free_camera == null:
		return
	if chase_camera.current:
		free_camera.look_from(chase_camera.global_position,
				chase_camera.global_position - chase_camera.global_basis.z)
		free_camera.make_current()
		if player_input != null:
			player_input.enabled = false
	else:
		chase_camera.make_current()
		if player_input != null:
			player_input.enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
