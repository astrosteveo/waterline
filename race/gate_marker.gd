class_name GateMarker
extends Node3D
## A floating arrow over the next buoy of the rider the camera follows (the player, unless
## watching a race), in the buoy's colour, pointing to the side to pass on.

@export var race: Race
## Height of the arrow above the buoy's water line.
@export_range(0.0, 10.0, 0.1, "suffix:m") var height: float = 3.5
## How far the arrow sits toward the passing side.
@export_range(0.0, 5.0, 0.1, "suffix:m") var side_offset: float = 1.0
## Arrow length.
@export_range(0.5, 6.0, 0.1, "suffix:m") var size: float = 2.2

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _time := 0.0


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _arrow_mesh(size)
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.layers = ShoreMap.DYNAMIC_LAYER
	add_child(_mesh)
	visible = false


func _process(delta: float) -> void:
	_time += delta
	var gate := _target_gate()
	visible = gate != null
	if gate == null:
		return
	var side := float(gate.required_side)
	var buoy := gate.buoy
	var x := gate.right * side
	var basis := Basis(x, Vector3.UP, x.cross(Vector3.UP))
	var bob := sin(_time * TAU * 1.2) * 0.18
	var base := buoy.get_global_transform_interpolated().origin
	global_transform = Transform3D(basis, base + Vector3.UP * (height + bob) + x * side_offset)
	var pulse := 0.85 + 0.15 * sin(_time * TAU * 2.0)
	_material.albedo_color = buoy.color().lightened(0.15) * pulse


func _target_gate() -> CourseGate:
	if race == null or race.watched == null or race.course == null:
		return null
	if not race.watched.is_racing() or race.course.gates.is_empty():
		return null
	var index := race.watched.next_gate
	if index >= race.course.gates.size():
		return null
	var gate := race.course.gates[index]
	return gate if gate.buoy != null else null


## An arrow pointing along +X in the XY plane, extruded 0.25 * size deep, centred on the origin.
static func _arrow_mesh(length: float) -> ArrayMesh:
	var s := length / 2.4
	var outline := PackedVector2Array([
		Vector2(-1.2, -0.25), Vector2(0.15, -0.25), Vector2(0.15, -0.7), Vector2(1.2, 0.0),
		Vector2(0.15, 0.7), Vector2(0.15, 0.25), Vector2(-1.2, 0.25),
	])
	for i in outline.size():
		outline[i] *= s
	var depth := 0.3 * s
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var triangles := Geometry2D.triangulate_polygon(outline)
	for face in [1.0, -1.0]:
		for k in range(0, triangles.size(), 3):
			var corners := [triangles[k], triangles[k + 1], triangles[k + 2]]
			if face < 0.0:
				corners.reverse()
			for c in corners:
				var p: Vector2 = outline[c]
				vertices.append(Vector3(p.x, p.y, face * depth * 0.5))
				normals.append(Vector3(0.0, 0.0, face))
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var n := Vector3(b.y - a.y, a.x - b.x, 0.0).normalized()
		var a0 := Vector3(a.x, a.y, depth * 0.5)
		var a1 := Vector3(a.x, a.y, -depth * 0.5)
		var b0 := Vector3(b.x, b.y, depth * 0.5)
		var b1 := Vector3(b.x, b.y, -depth * 0.5)
		vertices.append_array(PackedVector3Array([a0, b1, b0, a0, a1, b1]))
		for k in 6:
			normals.append(n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
