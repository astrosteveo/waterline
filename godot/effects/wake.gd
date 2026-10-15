class_name Wake
extends MeshInstance3D
## The foam a jet ski leaves on the water: a churned trail straight behind the stern and two
## arms spreading out in a V, fading over a few seconds.
##
## Every physics tick the craft is on the water at speed, a point is added at its stern every
## [member spacing] meters, stored as the rest position of the surface under it, so the
## shader ([code]wake.gdshader[/code]) can move it with the waves. The mesh is rebuilt each
## frame from the points' ages.

## The craft to follow.
@export var craft: JetSki
## Meters between trail points.
@export_range(0.1, 5.0, 0.05, "suffix:m") var spacing: float = 0.7
## Seconds the arms last, and the churned trail behind the stern.
@export_range(0.5, 10.0, 0.1, "suffix:s") var arm_life: float = 4.0
@export_range(0.5, 10.0, 0.1, "suffix:s") var trail_life: float = 2.2
## How fast the arms spread sideways, as a share of the craft's speed when they were made.
@export_range(0.0, 1.0, 0.01) var spread: float = 0.32
## No wake below this speed.
@export_range(0.0, 10.0, 0.1, "suffix:m/s") var min_speed: float = 2.0
## Where the wake starts, in the craft's local space (the stern).
@export var stern: Vector3 = Vector3(0.0, 0.0, 1.35)

const MAX_POINTS := 160

var _rest := PackedVector2Array()
var _right := PackedVector2Array()
var _born := PackedFloat32Array()
var _strength := PackedFloat32Array()
var _speed := PackedFloat32Array()
var _breaks := PackedByteArray()
var _clock := 0.0
var _last := Vector3.INF
var _mesh := ArrayMesh.new()
var _material: ShaderMaterial


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layers = ShoreMap.DYNAMIC_LAYER
	mesh = _mesh
	_material = ShaderMaterial.new()
	_material.shader = preload("res://effects/wake.gdshader")
	# After the water, which is in the transparent pass too.
	_material.render_priority = 1
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.seamless = true
	texture.width = 256
	texture.height = 256
	_material.set_shader_parameter(&"foam_noise", texture)
	material_override = _material
	Ocean.add_follower(_material)
	# A huge box, so the wake is never culled when its points are off the mesh's own bounds.
	custom_aabb = AABB(Vector3(-5000, -50, -5000), Vector3(10000, 100, 10000))


func _exit_tree() -> void:
	if _material != null:
		Ocean.remove_follower(_material)


func _physics_process(delta: float) -> void:
	_clock += delta
	if craft == null:
		return
	var at := craft.global_transform * stern
	var moving := craft.contact > 0.25 and craft.speed > min_speed and not craft.airborne
	if not moving:
		_last = Vector3.INF
		return
	if _last != Vector3.INF and at.distance_to(_last) < spacing:
		return
	var heading := -craft.global_basis.z
	var right := Vector2(-heading.z, heading.x).normalized()
	var rest := Ocean.wave_set.find_rest_position(at.x, at.z, Ocean.end_time)
	_add(rest, right, clampf(craft.speed / 16.0, 0.2, 1.0) * (1.4 if craft.carving else 1.0), craft.speed,
			_last == Vector3.INF)
	_last = at


func _add(rest: Vector2, right: Vector2, strength: float, speed: float, starts_new: bool) -> void:
	if _rest.size() >= MAX_POINTS:
		_rest.remove_at(0)
		_right.remove_at(0)
		_born.remove_at(0)
		_strength.remove_at(0)
		_speed.remove_at(0)
		_breaks.remove_at(0)
	_rest.append(rest)
	_right.append(right)
	_born.append(_clock)
	_strength.append(strength)
	_speed.append(speed)
	_breaks.append(1 if starts_new else 0)


func _process(_delta: float) -> void:
	# Drop points older than the arms last.
	while not _born.is_empty() and _clock - _born[0] > arm_life:
		_rest.remove_at(0)
		_right.remove_at(0)
		_born.remove_at(0)
		_strength.remove_at(0)
		_speed.remove_at(0)
		_breaks.remove_at(0)
	_mesh.clear_surfaces()
	if _rest.size() < 2:
		return
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	# The churned trail: wide behind the stern, widening and fading quickly.
	_ribbon(vertices, colors, uvs, indices, 0.0, 1.0, 0.9, trail_life, 1.0)
	# The two arms of the V.
	_ribbon(vertices, colors, uvs, indices, -1.0, 0.8, 0.55, arm_life, 0.7)
	_ribbon(vertices, colors, uvs, indices, 1.0, 0.8, 0.55, arm_life, 0.7)
	if indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


## Adds one ribbon. [param side] -1 or 1 for an arm (which spreads sideways with age), 0 for
## the trail down the middle. [param width] at birth, growing by [param growth] per second.
func _ribbon(vertices: PackedVector3Array, colors: PackedColorArray, uvs: PackedVector2Array,
		indices: PackedInt32Array, side: float, width: float, growth: float, life: float, alpha: float) -> void:
	var previous := -1
	for i in _rest.size():
		var age := _clock - _born[i]
		if age > life:
			previous = -1
			continue
		if _breaks[i] == 1:
			previous = -1
		var fade := pow(1.0 - age / life, 1.5) * _strength[i] * alpha
		var centre := _rest[i] + _right[i] * side * (0.5 + _speed[i] * spread * age)
		var half := (width + growth * age) * 0.5
		var base := vertices.size()
		var a := centre - _right[i] * half
		var b := centre + _right[i] * half
		vertices.append(Vector3(a.x, 0.0, a.y))
		vertices.append(Vector3(b.x, 0.0, b.y))
		colors.append(Color(1, 1, 1, fade))
		colors.append(Color(1, 1, 1, fade))
		uvs.append(Vector2(0.0, i * 0.1))
		uvs.append(Vector2(1.0, i * 0.1))
		if previous >= 0:
			indices.append_array(PackedInt32Array([previous, previous + 1, base, previous + 1, base + 1, base]))
		previous = base
