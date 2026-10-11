class_name MenuBackdrop
extends Node3D
## A course behind a menu, seen from a camera circling high over it.

@export var course_scene: PackedScene = preload("res://levels/gull_cove.tscn")
## Radians per second.
@export var orbit_speed: float = 0.05
@export var distance: float = 140.0
@export var height: float = 48.0

var _camera: Camera3D
var _orbit := 0.0
var _centre := Vector3.ZERO


func _ready() -> void:
	var backdrop := course_scene.instantiate()
	add_child(backdrop)
	var course := backdrop as Course
	if course != null:
		var sum := Vector3.ZERO
		for i in 16:
			sum += course.point_at(course.length * i / 16.0)
		_centre = sum / 16.0
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.far = 6000.0
	add_child(_camera)
	_camera.make_current()
	_place_camera()


func _process(delta: float) -> void:
	_orbit += orbit_speed * delta
	_place_camera()


func _place_camera() -> void:
	var around := Vector3(sin(_orbit), 0.0, cos(_orbit))
	_camera.global_position = _centre + around * distance + Vector3.UP * height
	_camera.look_at(_centre + Vector3.UP * 2.0, Vector3.UP)
