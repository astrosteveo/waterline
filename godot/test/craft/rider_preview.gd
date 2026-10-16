extends Node3D
## Shows the four riders on their own craft in their own colours (the front row, facing the
## camera) and Marina on the Tradewind in each pose (the back row): steering hard right and leaning forward, thrown,
## swimming, half way through climbing back on, and in a handstand. For screenshots and the
## riders_kiln scenario. Each model comes from its craft scene as a [GhostRider] takes it, so
## its rider sits at the craft's Seat marker.

## The poses of the back row, left to right.
const POSES: Array[StringName] = [&"turn", &"thrown", &"swimming", &"mounting", &"handstand"]


func _ready() -> void:
	for i in Game.riders.size():
		var rider := Game.riders[i]
		var model := _add_model(rider.default_craft.scene, "Rider%d" % i, Vector3(-6.0 + 4.0 * i, 0.0, 0.0))
		rider.dress(model)
	var marina := Game.rider_named("Marina")
	for i in POSES.size():
		var model := _add_model(marina.default_craft.scene, String(POSES[i]).capitalize(),
				Vector3(-8.0 + 4.0 * i, 0.0, 6.0))
		marina.dress(model)
		model.set(&"pose_response", 50.0)
		var seat: Vector3 = model.global_transform * (model.get(&"seat") as Vector3)
		match POSES[i]:
			&"turn":
				model.call(&"set_pose", 1.0, 1.0, 1.0, false)
			&"thrown":
				var tumble := Basis(Vector3.FORWARD, 0.9) * Basis(Vector3.RIGHT, -0.6)
				model.call(&"set_rider", JetSkiModel.RiderMode.THROWN, Transform3D(tumble, seat + Vector3(1.2, 0.6, 0.0)))
			&"swimming":
				# Face down in the water, swimming toward the craft's side.
				var lying := Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -PI * 0.5)
				model.call(&"set_rider", JetSkiModel.RiderMode.SWIMMING, Transform3D(lying, Vector3(seat.x + 1.6, 0.1, seat.z)))
			&"mounting":
				var from := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(seat.x, 0.1, seat.z + 2.0))
				model.call(&"set_rider", JetSkiModel.RiderMode.MOUNTING, from, 0.5)
			&"handstand":
				model.call(&"set_stunt", &"handstand", 0.5)


func _add_model(craft_scene: PackedScene, model_name: String, at: Vector3) -> Node3D:
	var model := GhostRider.model_of(craft_scene)
	model.name = model_name
	model.position = at
	add_child(model)
	return model
