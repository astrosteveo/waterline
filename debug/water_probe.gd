@tool
class_name WaterProbe
extends Node3D
## A test marker that the CPU wave function places on the water.
##
## It is a thin pole that changes from yellow to magenta exactly at the surface height
## the CPU computes, with a black ring every 5 cm above and below. If the drawn water
## crosses every pole at its colour change, the CPU surface matches the shader's.

## Total length of the pole in meters; half sits above the computed surface.
@export_range(0.1, 10.0, 0.01, "suffix:m") var pole_length: float = 1.2
## Thickness of the pole.
@export_range(0.005, 0.5, 0.001, "suffix:m") var pole_radius: float = 0.03
## Move with the waves while the game runs.
@export var follow_waves: bool = true


func _ready() -> void:
	_build()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint() or not follow_waves:
		return
	# Placed in _physics_process, so it is drawn at the end-of-step wave time.
	global_position.y = Ocean.height_at_time(global_position, Ocean.end_time)


func _build() -> void:
	for child in get_children(true):
		if child.has_meta(&"probe_part"):
			child.free()
	var half := pole_length * 0.5
	_add_cylinder(Vector3(0.0, half * 0.5, 0.0), pole_radius, half, Color(1.0, 0.85, 0.0))
	_add_cylinder(Vector3(0.0, -half * 0.5, 0.0), pole_radius, half, Color(0.95, 0.0, 0.8))
	var ring := 0.05
	while ring < half:
		_add_cylinder(Vector3(0.0, ring, 0.0), pole_radius * 1.25, 0.006, Color.BLACK)
		_add_cylinder(Vector3(0.0, -ring, 0.0), pole_radius * 1.25, 0.006, Color.BLACK)
		ring += 0.05
	var cap := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = pole_radius * 2.0
	sphere.height = pole_radius * 4.0
	cap.mesh = sphere
	cap.material_override = _flat_material(Color(1.0, 0.85, 0.0))
	cap.position = Vector3(0.0, half, 0.0)
	cap.set_meta(&"probe_part", true)
	add_child(cap, false, Node.INTERNAL_MODE_FRONT)


func _add_cylinder(at: Vector3, radius: float, length: float, color: Color) -> void:
	var part := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = length
	cylinder.radial_segments = 16
	cylinder.rings = 1
	part.mesh = cylinder
	part.material_override = _flat_material(color)
	part.position = at
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.set_meta(&"probe_part", true)
	add_child(part, false, Node.INTERNAL_MODE_FRONT)


func _flat_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	return material
