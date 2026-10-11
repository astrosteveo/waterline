class_name GhostRecorder
extends Node
## Records a craft's run for a time-trial ghost: every physics tick from the start, the
## model's transform (so stunts show) and its pose. [method data] returns it for
## [method Records.save_ghost]; [GhostRider] plays it back.

## Floats per frame: position (3), rotation quaternion (4), steer, lean, airborne,
## stunt index (-1 for none), stunt progress.
const STRIDE := 12

var craft: JetSki
var frames := PackedFloat32Array()
var recording := false


func _ready() -> void:
	# After the race (50) has moved the clock for this tick.
	process_physics_priority = 60


func start() -> void:
	frames.clear()
	recording = true


func stop() -> void:
	recording = false


func _physics_process(_delta: float) -> void:
	if not recording or craft == null:
		return
	var model := craft.get_node_or_null(^"Model") as Node3D
	var xform := model.global_transform if model != null else craft.global_transform
	var q := xform.basis.get_rotation_quaternion()
	var controls := craft.controls
	var stunt_index := JetSki.STUNTS.keys().find(craft.stunt)
	frames.append_array(PackedFloat32Array([xform.origin.x, xform.origin.y, xform.origin.z,
			q.x, q.y, q.z, q.w, controls.steer, controls.lean, 1.0 if craft.airborne else 0.0,
			float(stunt_index), craft.stunt_progress]))


func frame_count() -> int:
	return frames.size() / STRIDE


## The recording, for [method Records.save_ghost].
func data(rider: String, course: String, race_time: float) -> Dictionary:
	return {"rider": rider, "course": course, "time": race_time, "frames": frames}
