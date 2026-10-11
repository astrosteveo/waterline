class_name JetSki
extends RigidBody3D
## A jet ski: a rigid body that floats on the Ocean's waves.
##
## Each physics tick, every hull point (the Marker3D children of HullPoints) samples the
## water. Submerged points push the hull up along the wave normal, and resist being pushed
## further in, so the craft rides up, over and down the swells and can leave the water off
## a crest. On top of that come thrust from the jet, drag through the water, sideways grip,
## steering, banking, the rider's lean and air control. Every number is in [member tuning].
##
## The craft's local frame: -Z forward, +X right, +Y up, origin on the keel at mid-length.

## Emitted after [method respawn] has put the craft back.
signal respawned
## Emitted when the rider is thrown off: [param reason] is impact, nose_dive, landed_on_side,
## landed_sideways or capsized.
signal crashed(reason: StringName)
## Emitted when the rider is back on and in control after a crash.
signal remounted

## What the rider is doing. The order matches [enum JetSkiModel.RiderMode].
enum RiderState {
	## Seated and in control.
	ABOARD,
	## Thrown off, flying through the air.
	THROWN,
	## In the water, swimming back to the craft.
	SWIMMING,
	## Climbing back on.
	MOUNTING,
}

## Where the rider's pelvis sits when seated, in the craft's local space.
const SEAT := Vector3(0.0, 1.12, 0.38)
## Where the rider can climb on: either side of the seat, or behind the stern. The rider
## swims to the nearest.
const BOARDING_POINTS: Array[Vector3] = [Vector3(-1.0, 0.0, 0.4), Vector3(1.0, 0.0, 0.4), Vector3(0.0, 0.0, 1.7)]

## The ride's tuning numbers. Shared resources can be swapped per rider or per craft.
@export var tuning: JetSkiTuning
## Multiplies the thrust. The power meter will raise it.
@export_range(0.0, 3.0, 0.01) var power_multiplier: float = 1.0
## Hull points behind this local Z feed the jet intake: when they leave the water, so
## does the thrust.
@export var intake_min_z: float = 0.5
## Detect crashes and throw the rider off. When false the craft can't crash.
@export var crashes_enabled: bool = true

## What the rider asks for this tick. [PlayerInput] or a computer rider writes it.
var controls := RiderControls.new()
## Called instead of [method respawn] when the rider asks for a reset ([method request_reset]).
## A race sets it to put the craft back on the course.
var reset_handler: Callable

# Telemetry, refreshed every physics tick.
## Horizontal speed over the ground, m/s.
var speed: float = 0.0
## Speed through the water along the hull, m/s.
var forward_speed: float = 0.0
## Sideways speed through the water, m/s (positive to the right).
var side_speed: float = 0.0
## Angle between the hull and its direction of travel, radians (positive: moving right of the nose).
var slip_angle: float = 0.0
## Share of the hull points in the water, weighted by how wet each is (0 to 1).
var contact: float = 0.0
## True while every hull point is clear of the water.
var airborne: bool = false
## Seconds since the craft last left the water (0 while on it).
var air_time: float = 0.0
## Height of the lowest hull point above the water; negative when it is under.
var clearance: float = 0.0
## Sideways force the hull needs to hold its line, divided by what it can make.
var grip_usage: float = 0.0
## True while the hull needs clearly more sideways force (over 10% more) than it has.
var sliding: bool = false
## True while turning hard with a forward lean at speed.
var carving: bool = false
## Current jet thrust, 0 to 1. It follows the throttle with a short lag.
var thrust: float = 0.0
## Water height under the centre of mass.
var water_height: float = 0.0
## What the rider is doing.
var rider_state: RiderState = RiderState.ABOARD
## Crashes since the craft was spawned.
var crash_count: int = 0
## The last crash's reason, and the measurements of the last touchdown after a jump:
## pitch below the surface, roll and slip in degrees, and the air time.
var last_crash_reason: StringName = &""
var last_landing: Dictionary = {}
## The largest speed change from an impact seen in the last physics tick, m/s.
var last_impact_speed: float = 0.0

var _hull_points := PackedVector3Array()
var _is_intake := PackedByteArray()
var _samples: Array[WaterSample] = []
var _spawn_transform := Transform3D.IDENTITY
var _respawn_target := Transform3D.IDENTITY
var _pending_respawn := false
var _respawn_speed := 0.0
var _capsized_time := 0.0
var _model: Node3D
var _held := false
var _hold_transform := Transform3D.IDENTITY
var _crash_reason: StringName = &""
var _rider_time := 0.0
var _rider_position := Vector3.ZERO
var _rider_previous := Vector3.ZERO
var _rider_velocity := Vector3.ZERO
var _rider_heading := Vector3.FORWARD
var _rider_spin := 0.0
var _right_craft := false
var _previous_velocity := Vector3.ZERO
var _crash_velocity := Vector3.ZERO


func _ready() -> void:
	if tuning == null:
		tuning = JetSkiTuning.new()
	can_sleep = false
	continuous_cd = true
	# Contacts tell a craft riding a ramp from one in the air, and detect crashes.
	contact_monitor = true
	max_contacts_reported = 8
	custom_integrator = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	_apply_body_tuning()
	_collect_hull_points()
	_model = get_node_or_null(^"Model") as Node3D
	_spawn_transform = global_transform
	# Start on the water rather than wherever the scene put the keel: now, for the first
	# frame drawn, and again on the first physics tick, which also matches the water's motion.
	global_position.y = Ocean.height_at(global_position) - 0.08
	reset_physics_interpolation()
	respawn()


func _process(_delta: float) -> void:
	if _model == null:
		return
	if _model.has_method(&"set_pose"):
		var aboard := rider_state == RiderState.ABOARD
		_model.call(&"set_pose", controls.steer if aboard else 0.0, controls.lean if aboard else 0.0,
				thrust, airborne)
	if _model.has_method(&"set_rider"):
		_model.call(&"set_rider", rider_state, _rider_pelvis(), _mount_blend())


func _physics_process(delta: float) -> void:
	if _crash_reason != &"" and rider_state == RiderState.ABOARD:
		throw_rider(_crash_reason)
	_crash_reason = &""
	if rider_state == RiderState.ABOARD:
		return
	_rider_time += delta
	_rider_previous = _rider_position
	var t := tuning
	match rider_state:
		RiderState.THROWN:
			_rider_velocity += Vector3.DOWN * 9.8 * delta
			_rider_velocity -= _rider_velocity * minf(0.4 * delta, 1.0)
			_rider_position += _rider_velocity * delta
			_stop_rider_at_obstacles()
			_rider_spin += delta * 7.0
			var water := Ocean.height_at_time(_rider_position, Ocean.end_time)
			if _rider_position.y <= water and _rider_velocity.y < 0.0:
				_rider_position.y = water
				rider_state = RiderState.SWIMMING
				_rider_time = 0.0
		RiderState.SWIMMING:
			var target := boarding_point()
			var to_target := target - _rider_position
			to_target.y = 0.0
			var distance := to_target.length()
			if distance <= t.mount_reach or _rider_time >= t.max_swim_time:
				_start_mount()
			elif distance > 0.01:
				_rider_heading = to_target / distance
				# A moment to come up for air, then swim.
				var swim := t.swim_speed * smoothstep(t.surface_time, t.surface_time + 0.4, _rider_time)
				_rider_position += _rider_heading * minf(swim * delta, distance)
			_rider_position.y = Ocean.height_at_time(_rider_position, Ocean.end_time)
		RiderState.MOUNTING:
			if _rider_time >= t.mount_time:
				rider_state = RiderState.ABOARD
				_rider_time = 0.0
				remounted.emit()


## The nearest place for the swimming rider to climb on, in world space.
func boarding_point() -> Vector3:
	var best := global_transform * BOARDING_POINTS[0]
	for local in BOARDING_POINTS:
		var point := global_transform * local
		if point.distance_squared_to(_rider_position) < best.distance_squared_to(_rider_position):
			best = point
	return best


## Where a camera should look: the craft, or between the craft and its rider while the rider
## is off it, so a thrown or swimming rider stays in view.
func camera_focus() -> Vector3:
	var craft := get_global_transform_interpolated().origin
	if rider_state == RiderState.ABOARD or rider_state == RiderState.MOUNTING:
		return craft
	return craft.lerp(_rider_pelvis().origin, 0.5)


## True while the rider is on the craft and in control.
func is_rider_aboard() -> bool:
	return rider_state == RiderState.ABOARD


## Throws the rider off: the engine cuts out, the rider flies on with the craft's momentum,
## lands in the water, swims back and climbs on. [param reason] is reported by [signal crashed].
func throw_rider(reason: StringName = &"impact") -> void:
	if rider_state != RiderState.ABOARD:
		return
	rider_state = RiderState.THROWN
	_rider_time = 0.0
	_rider_position = global_transform * SEAT
	_rider_previous = _rider_position
	var heading := -global_basis.z
	heading.y = 0.0
	_rider_heading = heading.normalized() if heading.length_squared() > 1e-4 else Vector3.FORWARD
	# The rider keeps going at the speed the craft had before the crash.
	var velocity := _crash_velocity if _crash_velocity != Vector3.ZERO else linear_velocity
	var side := signf(global_basis.x.y) if absf(global_basis.x.y) > 0.05 else -1.0
	var right := global_basis.x
	right.y = 0.0
	_rider_velocity = velocity * tuning.throw_speed_share + Vector3.UP * tuning.throw_up_speed \
			- right.normalized() * side * tuning.throw_side_speed
	_crash_velocity = Vector3.ZERO
	_rider_spin = 0.0
	crash_count += 1
	last_crash_reason = reason
	crashed.emit(reason)


## A thrown rider who flies into a rock or a wall drops off it rather than passing through.
func _stop_rider_at_obstacles() -> void:
	var query := PhysicsRayQueryParameters3D.create(_rider_previous, _rider_position,
			PhysicsLayers.SCENERY | PhysicsLayers.WALLS)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	var normal: Vector3 = hit["normal"]
	_rider_position = (hit["position"] as Vector3) + normal * 0.4
	var bounce := normal * maxf(-_rider_velocity.dot(normal), 0.0) * 0.3
	_rider_velocity = Vector3(0.0, minf(_rider_velocity.y, 0.0), 0.0) + bounce


func _start_mount() -> void:
	rider_state = RiderState.MOUNTING
	_rider_time = 0.0
	# A capsized or badly tilted craft is turned upright as the rider climbs on.
	if global_basis.y.dot(Vector3.UP) < 0.6:
		_right_craft = true


## The rider's pelvis in world space while off the craft, between physics ticks.
func _rider_pelvis() -> Transform3D:
	if rider_state == RiderState.ABOARD:
		return Transform3D.IDENTITY
	var fraction := Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	var at := _rider_previous.lerp(_rider_position, fraction)
	var facing := Basis.looking_at(_rider_heading, Vector3.UP)
	if rider_state == RiderState.THROWN:
		return Transform3D(Basis(facing.x, -_rider_spin) * facing, at)
	# Lying in the water, head toward the craft, shoulders above the surface.
	return Transform3D(facing * Basis(Vector3.RIGHT, -1.05), at + Vector3.UP * 0.15)


func _mount_blend() -> float:
	if rider_state != RiderState.MOUNTING:
		return 0.0
	var fraction := Engine.get_physics_interpolation_fraction() if get_tree().physics_interpolation else 1.0
	return clampf((_rider_time + (fraction - 1.0) * get_physics_process_delta_time()) / tuning.mount_time, 0.0, 1.0)


## Copies mass, centre of mass and inertia from [member tuning] to the body.
func _apply_body_tuning() -> void:
	mass = tuning.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = tuning.center_of_mass
	inertia = tuning.inertia


func _collect_hull_points() -> void:
	_hull_points.clear()
	_is_intake.clear()
	_samples.clear()
	var holder := get_node_or_null(^"HullPoints")
	if holder == null:
		push_error("JetSki needs a HullPoints node with Marker3D children.")
		return
	for child in holder.get_children():
		var marker := child as Node3D
		if marker == null:
			continue
		var local := global_transform.affine_inverse() * marker.global_position
		_hull_points.append(local)
		_is_intake.append(1 if local.z >= intake_min_z else 0)
		_samples.append(WaterSample.new())


## Puts the craft back upright on the water at [param where] (its spawn point by default),
## moving forward at [param speed] m/s through the water.
func respawn(where: Transform3D = _spawn_transform, speed: float = 0.0) -> void:
	_respawn_target = where
	_respawn_speed = speed
	_pending_respawn = true


## Puts the craft back upright where it is now, facing the way it was going.
func respawn_here() -> void:
	var heading := -global_basis.z
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		heading = Vector3.FORWARD
	respawn(Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), global_position))


## Asks for the craft to be put back: [member reset_handler] if set, else [method respawn].
## Ignored while the rider is off the craft, so a reset can't cut a crash short.
func request_reset() -> void:
	if rider_state != RiderState.ABOARD:
		return
	if reset_handler.is_valid():
		reset_handler.call()
	else:
		respawn()


## Keeps the craft floating at [param where] with the engine idle, for example on the
## starting grid. The waves still move it up and down.
func hold(where: Transform3D) -> void:
	_held = true
	_hold_transform = where


## Ends [method hold]: the rider has control again.
func release() -> void:
	_held = false


## True while [method hold] keeps the craft in place.
func is_held() -> bool:
	return _held


## The telemetry as a dictionary, for the debug overlay and for tests.
func telemetry() -> Dictionary:
	return {
		"speed_kmh": speed * 3.6,
		"forward_speed": forward_speed,
		"side_speed": side_speed,
		"slip_degrees": rad_to_deg(slip_angle),
		"contact": contact,
		"airborne": airborne,
		"air_time": air_time,
		"clearance": clearance,
		"grip_usage": grip_usage,
		"sliding": sliding,
		"carving": carving,
		"thrust": thrust,
		"pitch_degrees": rad_to_deg(asin(clampf(-global_basis.z.y, -1.0, 1.0))),
		"roll_degrees": rad_to_deg(asin(clampf(global_basis.x.y, -1.0, 1.0))),
		"height": global_position.y,
		"water_height": water_height,
		"rider": RiderState.keys()[rider_state],
	}


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _pending_respawn:
		_do_respawn(state)
		return
	if _right_craft:
		_right_craft = false
		_turn_upright(state)
	var t := tuning
	var dt := state.step
	var xform := state.transform
	var b := xform.basis
	var origin := xform.origin
	var com := origin + state.center_of_mass
	var lin := state.linear_velocity
	var ang := state.angular_velocity
	var g := state.total_gravity.length()

	# --- The water at each hull point: buoyancy and the water's push-back. ---
	var count := _hull_points.size()
	var per_point_mass := t.mass / maxf(count, 1)
	var wet_sum := 0.0
	var depth_share_sum := 0.0
	var normal_sum := Vector3.ZERO
	var water_velocity_sum := Vector3.ZERO
	var intake_depth_sum := 0.0
	var intake_count := 0
	var lowest := INF
	for i in count:
		var p := xform * _hull_points[i]
		var sample := Ocean.sample(p, _samples[i])
		var depth := sample.height - p.y
		lowest = minf(lowest, -depth)
		if _is_intake[i] == 1:
			intake_depth_sum += depth
			intake_count += 1
		if depth <= 0.0:
			continue
		var wet := minf(depth / t.wet_depth, 1.0)
		var n := sample.normal
		var r := p - com
		var normal_speed := (lin + ang.cross(r) - sample.velocity).dot(n)
		var push := Vector3.UP.lerp(n, t.normal_follow).normalized()
		var force := push * (t.buoyancy_stiffness * minf(depth, t.max_point_depth))
		var damping := 0.0
		if normal_speed < 0.0:
			damping = (-normal_speed * t.water_damping + normal_speed * normal_speed * t.slam_damping) * wet
		else:
			damping = -normal_speed * t.water_damping * t.release_share * wet
		# Never let the damping do more than stop the point's motion along the normal.
		var damping_limit := per_point_mass * absf(normal_speed) / dt
		force += n * clampf(damping, -damping_limit, damping_limit)
		state.apply_force(force, p - origin)
		wet_sum += wet
		depth_share_sum += minf(depth / t.max_point_depth, 1.0)
		normal_sum += n * wet
		water_velocity_sum += sample.velocity * wet

	contact = wet_sum / maxf(count, 1)
	clearance = lowest
	water_height = Ocean.height_at(com)
	var in_water := wet_sum > 0.0
	var submersion := depth_share_sum / maxf(count, 1)
	var surface_up := normal_sum.normalized() if in_water else Vector3.UP
	var water_velocity := water_velocity_sum / wet_sum if in_water else Vector3.ZERO
	# Water forces fade in as more of the hull touches the water.
	var grip_contact := smoothstep(0.0, 0.3, contact)

	# --- The frame on the water: forward and right along the surface. ---
	var nose := -b.z
	var forward := nose - surface_up * nose.dot(surface_up)
	forward = forward.normalized() if forward.length_squared() > 1e-6 else nose
	var right := forward.cross(surface_up)
	var through_water := lin - water_velocity
	forward_speed = through_water.dot(forward)
	side_speed = through_water.dot(right)
	speed = Vector2(lin.x, lin.z).length()
	slip_angle = atan2(side_speed, absf(forward_speed)) if absf(forward_speed) > 1.0 else 0.0

	# --- The rider: lean and carving change grip, turning and drag. ---
	var in_control := not _held and rider_state == RiderState.ABOARD
	var steer := clampf(controls.steer, -1.0, 1.0) if in_control else 0.0
	var lean := clampf(controls.lean, -1.0, 1.0) if in_control else 0.0
	var lean_forward := maxf(lean, 0.0)
	var lean_back := maxf(-lean, 0.0)
	var grip_multiplier := lerpf(1.0, t.lean_forward_grip, lean_forward) * lerpf(1.0, t.lean_back_grip, lean_back)
	var turn_multiplier := lerpf(1.0, t.lean_forward_turn, lean_forward) * lerpf(1.0, t.lean_back_turn, lean_back)
	var drag_multiplier := lerpf(1.0, t.lean_forward_drag, lean_forward) * lerpf(1.0, t.lean_back_drag, lean_back)
	carving = in_water and absf(steer) >= t.carve_steer and lean >= t.carve_lean \
			and forward_speed >= t.carve_min_speed
	if carving:
		grip_multiplier *= t.carve_grip
		turn_multiplier *= t.carve_turn
		drag_multiplier *= t.carve_drag
	var speed_ratio := clampf(absf(forward_speed) / t.reference_top_speed, 0.0, 1.5)

	# --- Thrust: the jet pushes along the surface while the intake is under water. ---
	var throttle := 0.0 if not in_control else clampf(controls.throttle, 0.0, 1.0)
	thrust = move_toward(thrust, throttle, t.throttle_response * dt)
	var intake_depth := intake_depth_sum / maxf(intake_count, 1)
	var intake_wet := clampf(intake_depth / t.intake_depth, 0.0, 1.0)
	var thrust_force := t.max_thrust * thrust * intake_wet * power_multiplier
	state.apply_central_force(forward * thrust_force)
	state.apply_torque(b.x * thrust_force * t.thrust_pitch_lever)

	if in_water:
		# Planing lift and drag through the water.
		var planing := maxf(forward_speed, 0.0)
		state.apply_central_force(surface_up * t.planing_lift * planing * planing * grip_contact)
		var deep := lerpf(1.0, t.deep_drag_multiplier, submersion)
		var drag := (t.linear_drag * forward_speed + t.quadratic_drag * forward_speed * absf(forward_speed)) \
				* drag_multiplier * deep * grip_contact
		state.apply_central_force(-forward * drag)

		# Grip: the hull cancels sideways motion up to a limit, then slides.
		var grip_limit := t.grip_g * g * t.mass * grip_multiplier * grip_contact
		var needed := -side_speed * t.mass * t.grip_rate
		grip_usage = absf(needed) / grip_limit if grip_contact > 0.2 else 0.0
		sliding = grip_usage > 1.1
		state.apply_central_force(right * clampf(needed, -grip_limit, grip_limit))

		# Steering: drive the yaw rate toward what the stick asks for.
		var turn_rate := lerpf(t.turn_rate_low, t.turn_rate_high,
				smoothstep(t.turn_rate_peak_speed, t.reference_top_speed, absf(forward_speed)))
		var authority := lerpf(t.coast_steer, 1.0, thrust)
		var target_yaw := -steer * turn_rate * turn_multiplier * authority
		if absf(forward_speed) > 3.0:
			# Past the slip limit, stop turning the nose further from the direction of travel.
			var limit := deg_to_rad(t.slip_limit)
			target_yaw -= signf(slip_angle) * maxf(absf(slip_angle) - limit, 0.0) * t.slip_recovery
		var yaw_rate := ang.dot(surface_up)
		var yaw_acceleration := clampf((target_yaw - yaw_rate) * t.yaw_response,
				-t.max_yaw_acceleration, t.max_yaw_acceleration)
		state.apply_torque(surface_up * yaw_acceleration * t.inertia.y * grip_contact)

		# Banking into the turn, and roll damping.
		var bank_target := -steer * deg_to_rad(t.bank_angle) * smoothstep(3.0, 12.0, forward_speed)
		var roll := asin(clampf(b.x.dot(surface_up), -1.0, 1.0))
		var roll_rate := ang.dot(nose)
		var roll_torque := -(bank_target - roll) * t.bank_stiffness - roll_rate * t.roll_damping
		state.apply_torque(nose * roll_torque * grip_contact)

		# Pitch: the rider's lean and the bow rising at speed, each fading out as the nose
		# nears its limit relative to the water, a stiff push back past the limits, and damping.
		var pitch_rate := ang.dot(b.x)
		var surface_pitch := asin(clampf(nose.dot(surface_up), -1.0, 1.0))
		var max_up := deg_to_rad(t.lean_back_max_pitch)
		var max_down := deg_to_rad(t.lean_forward_max_pitch)
		var room_up := 1.0 - smoothstep(0.0, max_up, surface_pitch)
		var room_down := 1.0 - smoothstep(0.0, max_down, -surface_pitch)
		var pitch_torque := -lean_forward * t.lean_torque * room_down + lean_back * t.lean_torque * room_up
		pitch_torque += t.trim_torque * speed_ratio * speed_ratio * room_up
		if surface_pitch > max_up:
			pitch_torque -= (surface_pitch - max_up) * t.pitch_limit_stiffness
		elif surface_pitch < -max_down:
			pitch_torque += (-max_down - surface_pitch) * t.pitch_limit_stiffness
		pitch_torque -= pitch_rate * t.pitch_damping
		state.apply_torque(b.x * pitch_torque * grip_contact)
	else:
		grip_usage = 0.0
		sliding = false

	# --- Air control: lean pitches the craft, steering turns it. Fades out on the water. ---
	var air_share := 1.0 - grip_contact
	if air_share > 0.0:
		# Pitch: the lean sets a pitch rate, fading in over the first moments of air time
		# and stopping at the pitch limit. Yaw turns about the vertical.
		var air_pitch := asin(clampf(nose.y, -1.0, 1.0))
		var ramp := clampf(air_time / t.air_control_delay, 0.0, 1.0) if t.air_control_delay > 0.0 else 1.0
		var pitch_request := -lean * t.air_pitch_rate * ramp
		var air_limit := deg_to_rad(t.air_pitch_limit)
		if (pitch_request > 0.0 and air_pitch > air_limit) or (pitch_request < 0.0 and air_pitch < -air_limit):
			pitch_request = 0.0
		var pitch_error := pitch_request - ang.dot(b.x)
		var yaw_error := -steer * t.air_yaw_rate - ang.dot(Vector3.UP)
		var air_torque := b.x * pitch_error * t.inertia.x + Vector3.UP * yaw_error * t.inertia.y
		state.apply_torque(air_torque * t.air_response * air_share)
		# Roll: level out toward a small bank into the air turn.
		var air_roll := asin(clampf(b.x.y, -1.0, 1.0))
		var roll_target := -steer * deg_to_rad(t.air_bank_angle)
		var roll_acceleration := (air_roll - roll_target) * t.air_roll_stiffness - ang.dot(nose) * t.air_roll_damping
		state.apply_torque(nose * roll_acceleration * t.inertia.z * air_share)
		state.apply_torque(-ang * t.air_angular_damping * t.inertia.z * air_share)
	state.apply_central_force(-lin * lin.length() * t.air_drag)

	if _held:
		_apply_hold(state)
	if rider_state != RiderState.ABOARD:
		# No rider: the engine is cut, the craft slows and drifts toward the swimmer.
		var drift := through_water
		drift.y = 0.0
		state.apply_central_force(-drift * t.mass * t.riderless_brake)
		if rider_state == RiderState.SWIMMING:
			var gap := _rider_position - origin
			gap.y = 0.0
			state.apply_central_force(gap.limit_length(3.0) * t.mass * t.drift_to_rider)

	# --- Airtime, landings, impacts and capsizing. ---
	var was_airborne := airborne
	var air_before := air_time
	airborne = clearance > 0.02 and state.get_contact_count() == 0
	air_time = air_time + dt if airborne else 0.0
	var can_crash := crashes_enabled and in_control
	if was_airborne and not airborne:
		_judge_landing(b, surface_up, forward, lin, air_before, can_crash)
	_check_impacts(state, b, can_crash)
	if in_water and b.y.dot(Vector3.UP) < -0.1:
		_capsized_time += dt
		if can_crash and _capsized_time >= t.capsize_time:
			_crash_reason = &"capsized"
	else:
		_capsized_time = 0.0
	if _crash_reason != &"" and _crash_velocity == Vector3.ZERO:
		_crash_velocity = lin
	_previous_velocity = lin


## Judges a touchdown after a jump: nose first, on its side or sideways throws the rider off.
func _judge_landing(b: Basis, surface_up: Vector3, forward: Vector3, velocity: Vector3, air: float,
		can_crash: bool) -> void:
	var t := tuning
	var pitch := rad_to_deg(asin(clampf(-b.z.dot(surface_up), -1.0, 1.0)))
	var roll := rad_to_deg(asin(clampf(b.x.dot(surface_up), -1.0, 1.0)))
	var flat := velocity - surface_up * velocity.dot(surface_up)
	var slip := rad_to_deg(flat.angle_to(forward)) if flat.length() > 8.0 else 0.0
	last_landing = {"pitch": pitch, "roll": roll, "slip": slip, "air_time": air,
			"upside_down": b.y.dot(surface_up) < 0.0}
	if not can_crash or air < t.crash_landing_air_time:
		return
	if pitch < -t.crash_landing_pitch:
		_crash_reason = &"nose_dive"
	elif absf(roll) > t.crash_landing_roll or b.y.dot(surface_up) < 0.0:
		_crash_reason = &"landed_on_side"
	elif slip > t.crash_landing_slip:
		_crash_reason = &"landed_sideways"


## A hard side or front hit on scenery or another craft throws the rider off. Walls and
## floating things only push the craft away; the hull's underside meeting a slope (a ramp,
## a beach) is riding, not a hit.
func _check_impacts(state: PhysicsDirectBodyState3D, b: Basis, can_crash: bool) -> void:
	var t := tuning
	last_impact_speed = 0.0
	for i in state.get_contact_count():
		var other := state.get_contact_collider_object(i) as CollisionObject3D
		if other == null or other.collision_layer & (PhysicsLayers.WALLS | PhysicsLayers.FLOATING):
			continue
		if state.get_contact_local_normal(i).dot(b.y) > 0.7:
			continue
		var change := state.get_contact_impulse(i).length() / t.mass
		last_impact_speed = maxf(last_impact_speed, change)
		var limit := t.crash_craft_impact_speed if other is JetSki else t.crash_impact_speed
		if can_crash and change > limit:
			_crash_reason = &"impact"
			# Contacts already slowed the craft this tick: the rider flies at the speed before.
			_crash_velocity = _previous_velocity


## Turns the craft upright where it is, keeping its heading.
func _turn_upright(state: PhysicsDirectBodyState3D) -> void:
	var heading := -state.transform.basis.z
	heading.y = 0.0
	if heading.length_squared() < 0.01:
		heading = state.transform.basis.y
		heading.y = 0.0
	if heading.length_squared() < 0.01:
		heading = Vector3.FORWARD
	var origin := state.transform.origin
	var water := Ocean.sample(origin)
	origin.y = water.height - 0.08
	state.transform = Transform3D(Basis.looking_at(heading.normalized(), Vector3.UP), origin)
	state.linear_velocity = water.velocity
	state.angular_velocity = Vector3.ZERO
	_capsized_time = 0.0
	reset_physics_interpolation.call_deferred()


## Pulls the craft toward the hold point and heading with a spring and a damper.
func _apply_hold(state: PhysicsDirectBodyState3D) -> void:
	var gap := _hold_transform.origin - state.transform.origin
	gap.y = 0.0
	var velocity := state.linear_velocity
	velocity.y = 0.0
	state.apply_central_force((gap * 4.0 - velocity * 3.0) * tuning.mass)
	var nose := -state.transform.basis.z
	var want := -_hold_transform.basis.z
	var yaw_error := atan2(nose.cross(want).y, nose.dot(want))
	var yaw_rate := state.angular_velocity.y
	state.apply_torque(Vector3.UP * (yaw_error * 9.0 - yaw_rate * 5.0) * tuning.inertia.y)


func _do_respawn(state: PhysicsDirectBodyState3D) -> void:
	_pending_respawn = false
	var target := _respawn_target
	var water := Ocean.sample(target.origin)
	target.origin.y = water.height - 0.08
	state.transform = target
	# Move with the water, so the craft doesn't drop off a falling surface.
	state.linear_velocity = water.velocity - target.basis.z * _respawn_speed
	state.angular_velocity = Vector3.ZERO
	thrust = 0.0
	air_time = 0.0
	airborne = false
	rider_state = RiderState.ABOARD
	_crash_reason = &""
	_crash_velocity = Vector3.ZERO
	_capsized_time = 0.0
	_right_craft = false
	speed = Vector2(state.linear_velocity.x, state.linear_velocity.z).length()
	forward_speed = _respawn_speed
	side_speed = 0.0
	slip_angle = 0.0
	grip_usage = 0.0
	sliding = false
	carving = false
	contact = 1.0
	clearance = -0.08
	water_height = water.height
	reset_physics_interpolation.call_deferred()
	respawned.emit.call_deferred()
