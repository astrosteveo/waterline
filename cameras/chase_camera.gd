class_name ChaseCamera
extends Camera3D
## Follows a craft from behind and above, smoothly, without dipping into the waves.
##
## The camera turns toward the craft's heading and follows its height with separate lags,
## so it doesn't bob with every wave. After smoothing, two hard limits apply: the camera
## stays [member water_clearance] above the water under it, and it rises if a swell would
## block the line of sight to the craft. A ray toward the craft keeps islands and rocks
## from coming between them.

## The craft to follow.
@export var target_path: NodePath
## Distance behind the craft, in meters.
@export_range(1.0, 30.0, 0.1, "suffix:m") var distance: float = 6.4
## Height above the craft's smoothed height.
@export_range(0.0, 20.0, 0.1, "suffix:m") var height: float = 2.4
## The camera looks at this point above the craft...
@export_range(-2.0, 5.0, 0.01, "suffix:m") var look_height: float = 0.9
## ...moved this far ahead along the heading.
@export_range(-5.0, 20.0, 0.1, "suffix:m") var look_ahead: float = 2.5
## How quickly the camera swings round behind a turning craft, per second.
@export_range(0.1, 30.0, 0.1) var yaw_follow: float = 3.5
## How much the direction of travel, rather than the nose, sets the heading at speed.
@export_range(0.0, 1.0, 0.01) var velocity_heading: float = 0.5
## How quickly the camera follows the craft's height, per second. Low values ride out bumps.
@export_range(0.1, 30.0, 0.1) var height_follow: float = 2.5
## The same while the craft is in the air: slower, so a jump shows as the craft rising in the frame.
@export_range(0.1, 30.0, 0.1) var height_follow_air: float = 0.8
## How quickly the camera reaches its desired position, per second.
@export_range(0.1, 60.0, 0.1) var position_follow: float = 12.0
## Smallest height of the camera above the water directly under it.
@export_range(0.1, 5.0, 0.01, "suffix:m") var water_clearance: float = 0.9
## Smallest height of the line of sight above the water between camera and craft.
@export_range(0.0, 3.0, 0.01, "suffix:m") var sightline_clearance: float = 0.3
## Field of view at rest, and the extra at the reference speed.
@export_range(20.0, 120.0, 0.1, "degrees") var base_fov: float = 70.0
@export_range(0.0, 40.0, 0.1, "degrees") var speed_fov: float = 9.0
@export_range(1.0, 60.0, 0.1, "suffix:m/s") var reference_speed: float = 17.5
## Physics layers that block the camera (islands, rocks).
@export_flags_3d_physics var collision_mask: int = 1
## Gap kept between the camera and anything that blocks it.
@export_range(0.0, 3.0, 0.01, "suffix:m") var collision_margin: float = 0.4

## Lowest height of the camera above the water seen so far, for tests. Reset by snap().
var min_water_gap: float = INF

var _target: Node3D
var _yaw := 0.0
var _reference_height := 0.0
var _smoothed := Vector3.ZERO
var _fov_speed := 0.0
var _snap_next := true


func _ready() -> void:
	# Moved in _process from the craft's interpolated transform.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cull_mask &= ~ShoreMap.CAPTURE_LAYER
	if not target_path.is_empty():
		set_target(get_node_or_null(target_path) as Node3D)


## Follows [param node] from now on, starting right behind it.
func set_target(node: Node3D) -> void:
	if _target is JetSki and (_target as JetSki).respawned.is_connected(snap):
		(_target as JetSki).respawned.disconnect(snap)
	_target = node
	if _target is JetSki:
		(_target as JetSki).respawned.connect(snap)
	snap()
	# Place the camera now, so the first frame drawn already looks at the target.
	if _target != null and _target.is_inside_tree():
		_process(0.0)


## Jumps straight to the follow position on the next frame, without smoothing.
func snap() -> void:
	_snap_next = true
	min_water_gap = INF


func _process(delta: float) -> void:
	if _target == null:
		return
	var xform := _target.get_global_transform_interpolated()
	var focus := xform.origin + Vector3.UP * 0.4

	var nose := -xform.basis.z
	nose.y = 0.0
	var heading := nose.normalized() if nose.length_squared() > 1e-4 else Vector3.FORWARD
	var velocity := Vector3.ZERO
	if _target is RigidBody3D:
		velocity = (_target as RigidBody3D).linear_velocity
	velocity.y = 0.0
	var speed := velocity.length()
	if speed > 1.0:
		var weight := velocity_heading * smoothstep(2.0, 10.0, speed)
		heading = heading.lerp(velocity / speed, weight).normalized()
	var target_yaw := atan2(-heading.x, -heading.z)

	if _snap_next:
		_yaw = target_yaw
		_reference_height = focus.y
	else:
		_yaw = lerp_angle(_yaw, target_yaw, 1.0 - exp(-yaw_follow * delta))
		var follow := height_follow
		if _target is JetSki and (_target as JetSki).airborne:
			follow = height_follow_air
		_reference_height = lerpf(_reference_height, focus.y, 1.0 - exp(-follow * delta))

	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var look_target := Vector3(focus.x, focus.y + look_height, focus.z) - back * look_ahead
	var desired := Vector3(focus.x, _reference_height + height, focus.z) + back * distance
	if _snap_next:
		_smoothed = desired
		_snap_next = false
	else:
		_smoothed = _smoothed.lerp(desired, 1.0 - exp(-position_follow * delta))

	var at := _avoid_obstacles(focus, _smoothed)
	at.y = maxf(at.y, _lowest_height(at, look_target))
	global_position = at
	look_at(look_target, Vector3.UP)

	_fov_speed = lerpf(_fov_speed, clampf(speed / reference_speed, 0.0, 1.2), 1.0 - exp(-3.0 * delta))
	fov = base_fov + speed_fov * _fov_speed
	min_water_gap = minf(min_water_gap, at.y - _water_height(at))


## The lowest the camera may be at [param at]: above the water under it, and high enough
## that the line of sight to [param look_target] clears the water in between.
func _lowest_height(at: Vector3, look_target: Vector3) -> float:
	var lowest := _water_height(at) + water_clearance
	for f in [0.25, 0.5, 0.75]:
		var fraction: float = f
		var point := at.lerp(look_target, fraction)
		var needed := _water_height(point) + sightline_clearance
		# Height the camera needs so the line from it to the look target passes `needed` here.
		lowest = maxf(lowest, (needed - look_target.y * fraction) / (1.0 - fraction))
	return lowest


func _water_height(at: Vector3) -> float:
	return Ocean.height_at_time(at, Ocean.render_time())


## Pulls the camera in front of anything solid between it and the craft.
func _avoid_obstacles(focus: Vector3, at: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(focus, at, collision_mask)
	if _target is CollisionObject3D:
		query.exclude = [(_target as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return at
	var hit_position: Vector3 = hit["position"]
	return hit_position + (focus - hit_position).normalized() * collision_margin
