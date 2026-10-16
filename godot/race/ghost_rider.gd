class_name GhostRider
extends Node3D
## Plays back a time-trial ghost: a see-through copy of the craft and rider that rides the
## recorded run in step with the race clock. It draws the Model node of the craft that set the
## run, without the rest of the craft (no physics, wake, spray or engine sound).

var race: Race
var _frames := PackedFloat32Array()
var _count := 0
var _model: Node3D


## Sets up the ghost from a recording ([method Records.load_ghost]), drawn with the model of
## [param craft_scene] (a craft scene: its root is a [JetSki] with a Model node), with
## [param rider] on it in the rider's colours. Returns false if the recording holds no frames or the craft scene
## has no Model node.
func setup(ghost: Dictionary, craft_scene: PackedScene, rider: RiderProfile) -> bool:
	_frames = ghost.get("frames", PackedFloat32Array())
	_count = _frames.size() / GhostRecorder.STRIDE
	if _count == 0:
		return false
	_model = model_of(craft_scene)
	if _model == null:
		return false
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if "ghost" in _model:
		_model.set(&"ghost", true)
	if rider != null:
		rider.dress(_model)
	add_child(_model)
	_show(0.0)
	return true


## The Model node of a new instance of [param craft_scene], taken out of it, or null when the
## scene has no Model node. The rest of the instance is freed before it enters the tree. A
## model with a `seat` property gets the craft's Seat marker in model space, as a [JetSki]
## gives its own model, so the rider sits where it sat in the run.
static func model_of(craft_scene: PackedScene) -> Node3D:
	var craft := craft_scene.instantiate()
	var model := craft.get_node_or_null(^"Model") as Node3D
	if model != null:
		var marker := craft.get_node_or_null(^"Seat") as Node3D
		if marker != null and &"seat" in model:
			model.set(&"seat", model.transform.affine_inverse() * marker.position)
		craft.remove_child(model)
		model.owner = null
	craft.free()
	return model


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
