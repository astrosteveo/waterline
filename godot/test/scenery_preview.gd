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
