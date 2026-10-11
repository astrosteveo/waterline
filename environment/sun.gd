@tool
class_name Sun
extends DirectionalLight3D
## The sun. Publishes its direction as the global shader uniform [code]sun_direction[/code],
## which the water uses for light shining through wave crests.


func _ready() -> void:
	_publish()


func _process(_delta: float) -> void:
	_publish()


func _publish() -> void:
	# A DirectionalLight3D shines along its -Z axis, so the sun lies along +Z.
	RenderingServer.global_shader_parameter_set(&"sun_direction", global_transform.basis.z.normalized())
