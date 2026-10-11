class_name Floater
extends RigidBody3D
## A rigid body that floats on the Ocean: crates, barrels, buoys.
##
## The water is sampled at [member sample_points] (local space). Each submerged point
## pushes up along the wave normal in proportion to its depth, and drags the body toward
## the water's own velocity, so floating things bob and drift with the waves. Leave the
## points empty to use the eight corners of the first BoxShape3D child.

@export var sample_points: PackedVector3Array = PackedVector3Array()
## Upward force per meter of depth at each point, in newtons. Zero picks the stiffness
## that floats the body with [member rest_draft] of its points' height under water.
@export_range(0.0, 50000.0, 1.0, "suffix:N/m") var buoyancy_per_point: float = 0.0
## Share of the sampled height that sits under water at rest, used when
## [member buoyancy_per_point] is zero.
@export_range(0.05, 1.0, 0.01) var rest_draft: float = 0.5
## Depth past which a point adds no more buoyancy.
@export_range(0.01, 10.0, 0.01, "suffix:m") var max_depth: float = 1.0
## Drag toward the water's velocity, per second, at full submersion.
@export_range(0.0, 20.0, 0.01) var water_drag: float = 1.5
## Damping of rotation in the water, per second.
@export_range(0.0, 20.0, 0.01) var water_angular_drag: float = 1.2

var _samples: Array[WaterSample] = []


func _ready() -> void:
	can_sleep = false
	if sample_points.is_empty():
		_use_box_corners()
	for i in sample_points.size():
		_samples.append(WaterSample.new())
	if buoyancy_per_point <= 0.0 and not sample_points.is_empty():
		var low := INF
		var high := -INF
		for p in sample_points:
			low = minf(low, p.y)
			high = maxf(high, p.y)
		# At rest the water stands at this local height; only points below it carry the load.
		var waterline := low + maxf((high - low) * rest_draft, 0.02)
		var submerged := 0.0
		for p in sample_points:
			submerged += maxf(waterline - p.y, 0.0)
		buoyancy_per_point = mass * 9.8 / submerged
		max_depth = maxf(max_depth, high - low)


func _use_box_corners() -> void:
	for child in get_children():
		var shape_node := child as CollisionShape3D
		if shape_node == null or not (shape_node.shape is BoxShape3D):
			continue
		var half := (shape_node.shape as BoxShape3D).size * 0.5
		for corner in 8:
			var local := Vector3(half.x if corner & 1 else -half.x, half.y if corner & 2 else -half.y,
					half.z if corner & 4 else -half.z)
			sample_points.append(shape_node.transform * local)
		return


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var xform := state.transform
	var com := xform.origin + state.center_of_mass
	var count := sample_points.size()
	if count == 0:
		return
	var share := 1.0 / count
	var wet_share := 0.0
	for i in count:
		var p := xform * sample_points[i]
		var sample := Ocean.sample(p, _samples[i])
		var depth := sample.height - p.y
		if depth <= 0.0:
			continue
		var wet := minf(depth / max_depth, 1.0)
		var r := p - com
		var relative := state.linear_velocity + state.angular_velocity.cross(r) - sample.velocity
		var force := sample.normal * buoyancy_per_point * minf(depth, max_depth)
		force -= relative * water_drag * mass * share * minf(wet * 4.0, 1.0)
		state.apply_force(force, p - xform.origin)
		wet_share += share * minf(wet * 4.0, 1.0)
	if wet_share > 0.0:
		state.apply_torque(-state.angular_velocity * water_angular_drag * wet_share * mass)
