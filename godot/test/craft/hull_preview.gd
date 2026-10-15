extends Node3D
## Shows the code-built hull in the default colours, the Skipjack's kiln hull
## (assets/models/craft/skipjack.glb) in Dax's hull colours, and that hull as a time-trial
## ghost, for screenshots and the craft_hull_ghost scenario. Each model with a hull
## scene sits its rider at the Seat marker of [member craft], as [JetSki] would.

@export var craft: PackedScene = preload("res://craft/skipjack.tscn")


func _ready() -> void:
	var sample := craft.instantiate()
	var at: Vector3 = (sample.get_node(^"Seat") as Node3D).position
	sample.free()
	for child in get_children():
		var model := child as JetSkiModel
		if model != null and model.hull_scene != null:
			model.seat = at
