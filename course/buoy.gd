@tool
class_name Buoy
extends RigidBody3D
## A course buoy that bobs on the waves. Its colour tells racers which side to pass it on:
## keep a red buoy on your right (pass to its left) and a yellow buoy on your left (pass to
## its right). [Course] collects the buoys under its Buoys node, in order, as gates.
##
## The node's origin sits at the water line; the float hangs below it. The buoy is moored:
## springs pull it to its anchor, to the water height and upright along the waves, so a
## craft that hits it knocks it aside and loses some speed, and it swings back. Gates use
## the anchor, not where the buoy has been pushed. The meshes are built from code and can be
## replaced by any child scene named "Model".

enum Kind {
	## Keep on the racer's right: pass to its left.
	RED,
	## Keep on the racer's left: pass to its right.
	YELLOW,
}

const RED_COLOR := Color(0.93, 0.13, 0.10)
const YELLOW_COLOR := Color(1.0, 0.80, 0.05)
const STRIPE_COLOR := Color(0.97, 0.97, 0.95)

@export var kind: Kind = Kind.RED:
	set(value):
		kind = value
		_queue_build()
## Height of the buoy above the water line, in meters.
@export_range(0.5, 6.0, 0.01, "suffix:m") var height: float = 2.3:
	set(value):
		height = value
		_queue_build()
## Radius of the float at the water line.
@export_range(0.2, 3.0, 0.01, "suffix:m") var radius: float = 0.75:
	set(value):
		radius = value
		_queue_build()
## How much the buoy tilts with the wave slope: 0 stays upright, 1 stands along the normal.
@export_range(0.0, 1.0, 0.01) var tilt_follow: float = 0.6
## How stiffly the mooring holds the buoy at its anchor, per second squared (and the
## damping, per second). A hit at racing speed pushes it about a meter.
@export_range(0.0, 200.0, 0.1) var mooring_stiffness: float = 30.0
@export_range(0.0, 50.0, 0.1) var mooring_damping: float = 7.0
## The same for its height on the water, and for standing upright.
@export_range(0.0, 500.0, 0.1) var float_stiffness: float = 60.0
@export_range(0.0, 50.0, 0.1) var float_damping: float = 10.0
@export_range(0.0, 500.0, 0.1) var upright_stiffness: float = 40.0
@export_range(0.0, 50.0, 0.1) var upright_damping: float = 8.0

var _main_material: StandardMaterial3D
var _flash_color := Color.WHITE
var _flash_time := 0.0
var _flash_duration := 0.0
var _rest := Vector3.ZERO
var _build_queued := false
var _sample := WaterSample.new()


func _ready() -> void:
	_build()
	if Engine.is_editor_hint():
		return
	collision_layer = PhysicsLayers.FLOATING
	collision_mask = PhysicsLayers.CRAFT
	mass = 80.0
	gravity_scale = 0.0
	can_sleep = false
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.0
	_rest = global_position
	Ocean.sample_at_time(_rest, Ocean.time, _sample)
	global_position = Vector3(_rest.x, _sample.height, _rest.z)
	reset_physics_interpolation()


## The side a racer must pass on: -1 to the buoy's left, +1 to its right.
func required_side() -> int:
	return -1 if kind == Kind.RED else 1


## The buoy's colour.
func color() -> Color:
	return RED_COLOR if kind == Kind.RED else YELLOW_COLOR


## Where the buoy rests: its position when the level loaded, at the water's rest level.
func rest_position() -> Vector3:
	return _rest if is_node_ready() and not Engine.is_editor_hint() else global_position


## Lights the buoy up in [param flash_color], fading over [param duration] seconds.
func flash(flash_color: Color, duration: float = 0.6) -> void:
	_flash_color = flash_color
	_flash_duration = maxf(duration, 0.01)
	_flash_time = _flash_duration


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if Engine.is_editor_hint():
		return
	var at := state.transform.origin
	Ocean.sample_at_time(Vector3(at.x, 0.0, at.z), Ocean.time, _sample)
	var velocity := state.linear_velocity
	var force := Vector3.ZERO
	force.x = (_rest.x - at.x) * mooring_stiffness - (velocity.x - _sample.velocity.x) * mooring_damping
	force.z = (_rest.z - at.z) * mooring_stiffness - (velocity.z - _sample.velocity.z) * mooring_damping
	force.y = (_sample.height - at.y) * float_stiffness - (velocity.y - _sample.velocity.y) * float_damping
	state.apply_central_force(force * mass)
	var up := Vector3.UP.lerp(_sample.normal, tilt_follow).normalized()
	var axis := state.transform.basis.y.cross(up)
	state.apply_torque((axis * upright_stiffness - state.angular_velocity * upright_damping) * mass * 0.5)


func _process(delta: float) -> void:
	if _flash_time <= 0.0 or _main_material == null:
		return
	_flash_time = maxf(_flash_time - delta, 0.0)
	var strength := _flash_time / _flash_duration
	_main_material.emission_enabled = strength > 0.0
	_main_material.emission = _flash_color
	_main_material.emission_energy_multiplier = 2.5 * strength


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child in get_children(true):
		if child.has_meta(&"buoy_part"):
			child.free()
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius * 0.95
	cylinder.height = height + 0.8
	shape.shape = cylinder
	shape.position = Vector3(0.0, (height - 0.8) * 0.5, 0.0)
	_add_part(shape)
	if get_node_or_null(^"Model") != null:
		return

	_main_material = _material(color())
	var stripe := _material(STRIPE_COLOR)
	var dark := _material(Color(0.12, 0.13, 0.16))
	# Float: a fat drum half under water.
	_add_mesh(_cylinder(radius, radius * 0.9, 0.8), Vector3(0.0, -0.15, 0.0), _main_material)
	_add_mesh(_cylinder(radius * 1.02, radius * 1.02, 0.14), Vector3(0.0, 0.12, 0.0), stripe)
	# A tapered mast with a white band and a ball on top, so it reads from far away.
	var mast_height := height - 0.45
	_add_mesh(_cylinder(radius * 0.18, radius * 0.7, mast_height), Vector3(0.0, 0.25 + mast_height * 0.5, 0.0), _main_material)
	_add_mesh(_cylinder(radius * 0.47, radius * 0.53, mast_height * 0.16),
			Vector3(0.0, 0.25 + mast_height * 0.45, 0.0), stripe)
	var ball := SphereMesh.new()
	ball.radius = radius * 0.26
	ball.height = radius * 0.52
	ball.radial_segments = 10
	ball.rings = 5
	_add_mesh(ball, Vector3(0.0, height, 0.0), stripe)
	_add_mesh(_cylinder(radius * 0.92, radius * 0.92, 0.06), Vector3(0.0, -0.56, 0.0), dark)


func _cylinder(top: float, bottom: float, h: float) -> CylinderMesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = h
	mesh.radial_segments = 10
	mesh.rings = 1
	return mesh


func _material(albedo: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = albedo
	material.roughness = 0.45
	return material


func _add_mesh(mesh: PrimitiveMesh, at: Vector3, material: Material) -> void:
	mesh.material = material
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = at
	node.layers = ShoreMap.DYNAMIC_LAYER
	_add_part(node)


func _add_part(node: Node3D) -> void:
	node.set_meta(&"buoy_part", true)
	add_child(node, false, Node.INTERNAL_MODE_FRONT)
