class_name GhostRider
extends Node3D
## Plays back a time-trial ghost: a see-through copy of the craft and rider that rides the
## recorded run in step with the race clock.

var race: Race
var _frames := PackedFloat32Array()
var _count := 0
var _model: Node3D


## Sets up the ghost from a recording ([method Records.load_ghost]). Returns false if it
## holds no frames.
func setup(ghost: Dictionary, model_scene: PackedScene, rider: RiderProfile) -> bool:
	_frames = ghost.get("frames", PackedFloat32Array())
	_count = _frames.size() / GhostRecorder.STRIDE
	if _count == 0:
		return false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_model = model_scene.instantiate() as Node3D
	if "ghost" in _model:
		_model.set(&"ghost", true)
	if rider != null:
		rider.apply_colors(_model)
	add_child(_model)
	_show(0.0)
	return true


func _process(_delta: float) -> void:
	if race == null or _count == 0:
		return
	if race.phase == Race.Phase.COUNTDOWN:
		_show(0.0)
		return
	var fraction := Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	# Frame k was recorded at the end of race tick k + 1.
	var at := race.race_time / get_physics_process_delta_time() - 1.0 + fraction
	visible = at < _count - 1
	if visible:
		_show(at)


func _show(at: float) -> void:
	var i := clampi(int(at), 0, _count - 1)
	var j := mini(i + 1, _count - 1)
	var t := clampf(at - i, 0.0, 1.0)
	var a := _read(i)
	var b := _read(j)
	var origin := Vector3(a[0], a[1], a[2]).lerp(Vector3(b[0], b[1], b[2]), t)
	var qa := Quaternion(a[3], a[4], a[5], a[6])
	var qb := Quaternion(b[3], b[4], b[5], b[6])
	_model.global_transform = Transform3D(Basis(qa.slerp(qb, t)), origin)
	if _model.has_method(&"set_pose"):
		_model.call(&"set_pose", lerpf(a[7], b[7], t), lerpf(a[8], b[8], t), 1.0, a[9] > 0.5)
	if _model.has_method(&"set_stunt"):
		var stunt_index := int(a[10])
		var names := JetSki.STUNTS.keys()
		var stunt: StringName = names[stunt_index] if stunt_index >= 0 and stunt_index < names.size() else &""
		_model.call(&"set_stunt", stunt, a[11])


func _read(i: int) -> PackedFloat32Array:
	return _frames.slice(i * GhostRecorder.STRIDE, (i + 1) * GhostRecorder.STRIDE)
