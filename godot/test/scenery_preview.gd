extends Node3D
## A course and its scenery seen from a free camera, for screenshots and the scenery_kiln
## scenario. `-- --course id` picks the course (Gull Cove when none is named) and
## [method show_course] swaps it; [method view] puts the camera at a point along the course
## and [method look] anywhere.

## The course shown.
var course: Course
## The free camera.
var camera: Camera3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = 60.0
	camera.far = 4000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)
	camera.make_current()
	var id := Game.arg_value("--course")
	show_course(id if id != "" else "gull_cove")


## Each texture's tile, as kiln built it and as the game draws it, in metres: [built, drawn]
## by the material that draws it. kiln records a texture recipe's tile in art/kiln.lock.json,
## beside the project; the Rock, Wood and WoodDark materials repeat their texture every
## 1 / uv1_scale metres, and the terrain shader its sand, grass and rock every *_tile metres.
func texture_tiles() -> Dictionary:
	var lock_path := ProjectSettings.globalize_path("res://").path_join("../art/kiln.lock.json")
	var lock: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(lock_path))
	var tiles := {}
	for material: String in ["rock", "wood", "wood_dark"]:
		var texture := "wood" if material == "wood_dark" else material
		var scale := (load("res://environment/materials/%s.tres" % material) as BaseMaterial3D).uv1_scale
		tiles[material] = [lock["textures/" + texture]["tile"], 1.0 / scale.x]
	var terrain := load("res://environment/materials/terrain.tres") as ShaderMaterial
	for texture: String in ["sand", "grass", "rock"]:
		var parameter := texture + "_tile"
		var drawn: Variant = terrain.get_shader_parameter(parameter)
		if drawn == null:
			drawn = RenderingServer.shader_get_parameter_default(terrain.shader.get_rid(), parameter)
		tiles["terrain_" + texture] = [lock["textures/" + texture]["tile"], drawn]
	return tiles


## The materials in [method texture_tiles] that draw a texture at another size than kiln built
## it, as text: empty when they all agree.
func mismatched_tiles() -> Array[String]:
	var found: Array[String] = []
	var tiles := texture_tiles()
	for material: String in tiles:
		var pair: Array = tiles[material]
		if not is_equal_approx(float(pair[0]), float(pair[1])):
			found.append("%s: built %s m, drawn %s m" % [material, pair[0], pair[1]])
	return found


## Shows the course [param id] in place of the one shown, with the camera behind its start line.
func show_course(id: String) -> void:
	if course != null:
		remove_child(course)
		course.free()
	course = (load(Game.course_named(id).scene) as PackedScene).instantiate() as Course
	add_child(course)
	view(0.0)


## Puts the camera [param back] metres before course offset [param offset], [param lateral]
## metres right of the centre line and [param height] metres up, looking along the course.
func view(offset: float, height: float = 4.0, back: float = 14.0, lateral: float = 0.0) -> void:
	var from := course.transform_at(offset - back, lateral).origin + Vector3.UP * height
	var at := course.transform_at(offset + 20.0, lateral).origin + Vector3.UP * 1.0
	look(from, at)


## Puts the camera at [param from], looking at [param at].
func look(from: Vector3, at: Vector3) -> void:
	camera.look_at_from_position(from, at, Vector3.UP)
