extends Node3D
## Checks that the CPU wave function matches the water the GPU draws.
##
## An orthographic camera looks straight down on the ocean, which is drawn with
## ocean_height_debug.gdshader: each pixel's colour encodes the height of the drawn
## surface there. [method check] reads the frame back and compares sampled pixels with
## [method Ocean.height_at_time] at the same world position and wave time.
##
## Run it with gdh: start this scene, step some frames, then
## [code]gdh live eval "scene.check()"[/code].

## Pixels between samples, in each direction.
@export_range(1, 64) var sample_step: int = 8
## Must match height_range in the shader material.
@export var height_range: float = 4.0
## Where the camera looks, and from how high.
@export var look_at_point: Vector3 = Vector3(12.0, 0.0, -7.0)
@export var camera_height: float = 40.0

@onready var _camera: Camera3D = $Camera
@onready var _surface: OceanSurface = $OceanSurface


func _ready() -> void:
	var viewport := get_viewport()
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_debanding = false
	_camera.look_at_from_position(look_at_point + Vector3.UP * camera_height, look_at_point, Vector3.FORWARD)


## Compares the last drawn frame with the CPU heights. Returns the number of samples,
## the mean, RMS and largest absolute error in meters, and where the largest one was.
func check() -> Dictionary:
	var image := get_viewport().get_texture().get_image()
	var size := image.get_size()
	var meters_per_pixel := _camera.size / float(size.y)
	var centre := _camera.global_position
	var t := _surface.last_render_time
	var count := 0
	var total := 0.0
	var total_squared := 0.0
	var worst := 0.0
	var worst_at := Vector3.ZERO
	var drawn_min := INF
	var drawn_max := -INF
	for py in range(sample_step >> 1, size.y, sample_step):
		for px in range(sample_step >> 1, size.x, sample_step):
			var color := image.get_pixel(px, py)
			var u := (roundf(color.r * 63.0) + color.g) / 64.0
			var drawn := u * 2.0 * height_range - height_range
			var x := centre.x + (px + 0.5 - size.x * 0.5) * meters_per_pixel
			var z := centre.z + (py + 0.5 - size.y * 0.5) * meters_per_pixel
			var cpu := Ocean.height_at_time(Vector3(x, 0.0, z), t)
			var error := absf(drawn - cpu)
			count += 1
			total += error
			total_squared += error * error
			drawn_min = minf(drawn_min, drawn)
			drawn_max = maxf(drawn_max, drawn)
			if error > worst:
				worst = error
				worst_at = Vector3(x, cpu, z)
	return {
		"samples": count,
		"wave_time": t,
		"mean_error_m": total / maxf(count, 1),
		"rms_error_m": sqrt(total_squared / maxf(count, 1)),
		"max_error_m": worst,
		"max_error_at": worst_at,
		"drawn_height_range_m": Vector2(drawn_min, drawn_max),
		"image_size": size,
	}
