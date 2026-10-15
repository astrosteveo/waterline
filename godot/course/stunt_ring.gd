@tool
class_name StuntRing
extends Node3D
## A ring to ride through in stunt mode. A floating ring rides the waves with its lower edge
## in the water; an air ring hangs still, past a ramp's lip. Its local -Z is the way through.
## Built from code; a child scene named "Model" can replace the torus.

## Emitted when a racer passes through.
signal passed

## Radius of the opening.
@export_range(0.5, 8.0, 0.01, "suffix:m") var radius: float = 2.4:
	set(value):
		radius = value
		_queue_build()
## Floating rings follow the water; air rings stay where they are put.
@export var floating: bool = true
## How far the centre of a floating ring sits above the water.
@export_range(0.0, 5.0, 0.01, "suffix:m") var float_height: float = 1.6
@export var color: Color = Color(1.0, 0.75, 0.1):
	set(value):
		color = value
		_queue_build()

## True once a racer has passed through; the ring then fades out.
var taken: bool = false

var _material: StandardMaterial3D
var _anchor := Vector3.ZERO
var _fade := 1.0
var _spin := 0.0
var _build_queued := false


func _ready() -> void:
	_build()
	_anchor = global_position
	if not Engine.is_editor_hint() and floating:
		_follow_water()
		reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if floating:
		_follow_water()


func _process(delta: float) -> void:
	if Engine.is_editor_hint() or _material == null:
		return
	if taken:
		_fade = maxf(_fade - delta * 2.5, 0.0)
		_spin += delta * 12.0
		scale = Vector3.ONE * (1.0 + (1.0 - _fade) * 0.6)
		_material.albedo_color.a = _fade
		visible = _fade > 0.0
	else:
		_material.emission_energy_multiplier = 1.2 + 0.5 * sin(Time.get_ticks_msec() * 0.006)


## True if the movement from [param from] to [param to] went through the ring, forward.
func crosses(from: Vector3, to: Vector3) -> bool:
	var normal := -global_basis.z
	var a := (from - global_position).dot(normal)
	var b := (to - global_position).dot(normal)
	if not (a < 0.0 and b >= 0.0):
		return false
	var hit := from.lerp(to, a / (a - b))
	return hit.distance_to(global_position) <= radius + 0.3


## True if the movement went past the ring's plane, forward, outside the opening (within
## a few meters of it).
func misses(from: Vector3, to: Vector3) -> bool:
	var normal := -global_basis.z
	var a := (from - global_position).dot(normal)
	var b := (to - global_position).dot(normal)
	if not (a < 0.0 and b >= 0.0):
		return false
	var hit := from.lerp(to, a / (a - b))
	var distance := hit.distance_to(global_position)
	return distance > radius + 0.3 and distance < radius + 12.0


## Marks the ring as passed: it flashes and fades out.
func take() -> void:
	if taken:
		return
	taken = true
	if _material != null:
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.emission = Color.WHITE
		_material.emission_energy_multiplier = 4.0
	passed.emit()


func _follow_water() -> void:
	var water := Ocean.height_at_time(_anchor, Ocean.end_time)
	global_position = Vector3(_anchor.x, water + float_height, _anchor.z)


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child in get_children(true):
		if child.has_meta(&"ring_part"):
			child.free()
	if get_node_or_null(^"Model") != null:
		return
	_material = StandardMaterial3D.new()
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 1.2
	_material.roughness = 0.4
	var torus := TorusMesh.new()
	torus.inner_radius = radius
	torus.outer_radius = radius + 0.32
	torus.rings = 32
	torus.ring_segments = 8
	torus.material = _material
	var mesh := MeshInstance3D.new()
	mesh.mesh = torus
	# The torus lies flat (its axis is +Y); stand it up so the way through is -Z.
	mesh.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	mesh.layers = ShoreMap.DYNAMIC_LAYER
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.set_meta(&"ring_part", true)
	add_child(mesh, false, Node.INTERNAL_MODE_FRONT)
