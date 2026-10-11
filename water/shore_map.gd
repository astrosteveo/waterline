class_name ShoreMap
extends Node3D
## Captures the height of the static scenery (terrain, rocks, ramps: everything drawn on the
## visual layers in [member scenery_layers]) from straight above, once, when the level
## loads. The water shader reads it as the global uniform [code]shore_height_map[/code] to
## tell shores from moving things: what it sees under the water only gets shoreline foam if
## it lies on or under the scenery, so a jet ski's hull, a crate or a buoy never does.
##
## Put moving things on visual layer 2 and the water on layer 3 (see [constant DYNAMIC_LAYER]
## and [constant WATER_LAYER]); layer 1 is scenery.

## Visual layer bits used across the game.
const SCENERY_LAYER := 1
const DYNAMIC_LAYER := 2
const WATER_LAYER := 4
## The capture pass's own layer (layer 20), which no game camera draws.
const CAPTURE_LAYER := 1 << 19

## Width and depth of the area covered, in meters, centred on this node.
@export_range(10.0, 8192.0, 1.0, "suffix:m") var extent: float = 800.0
## Texels along each side.
@export_range(64, 4096, 1) var resolution: int = 1024
## Visual layers that count as static scenery.
@export_flags_3d_render var scenery_layers: int = SCENERY_LAYER
## Height of the capture camera above this node; scenery must be lower than this.
@export var capture_height: float = 300.0

var _viewport: SubViewport


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.name = "Capture"
	_viewport.size = Vector2i(resolution, resolution)
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_debanding = false
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = extent
	camera.near = 1.0
	camera.far = capture_height + 100.0
	camera.cull_mask = scenery_layers | CAPTURE_LAYER
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	camera.environment = environment
	_viewport.add_child(camera)
	var eye := global_position + Vector3.UP * capture_height
	camera.look_at_from_position(eye, global_position, Vector3.FORWARD)
	camera.current = true

	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	quad.mesh = mesh
	quad.layers = CAPTURE_LAYER
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	quad.extra_cull_margin = 16384.0
	var material := ShaderMaterial.new()
	material.shader = preload("res://water/shore_height_capture.gdshader")
	material.set_shader_parameter(&"capture_camera_position", eye)
	quad.material_override = material
	_viewport.add_child(quad)
	quad.global_position = eye + Vector3.DOWN * 10.0

	RenderingServer.global_shader_parameter_set(&"shore_height_map", _viewport.get_texture())
	RenderingServer.global_shader_parameter_set(&"shore_map_rect", Vector4(
			global_position.x - extent * 0.5, global_position.z - extent * 0.5, extent, extent))


func _exit_tree() -> void:
	# The next level starts without a map until its own ShoreMap is ready.
	RenderingServer.global_shader_parameter_set(&"shore_map_rect", Vector4.ZERO)


## The captured scenery height at a world position, decoded on the CPU, for tests.
## Returns -64 where there is no scenery and NAN outside the map.
func height_at(world_position: Vector3) -> float:
	var image := _viewport.get_texture().get_image()
	var uv := Vector2(world_position.x - (global_position.x - extent * 0.5),
			world_position.z - (global_position.z - extent * 0.5)) / extent
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return NAN
	var color := image.get_pixel(int(uv.x * image.get_width()), int(uv.y * image.get_height()))
	return (roundf(color.r * 63.0) + color.g) / 64.0 * 128.0 - 64.0
