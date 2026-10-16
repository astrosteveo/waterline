@tool
class_name JetSkiModel
extends Node3D
## A jet ski and its rider: a hull, and a blocky rider built from code whose body leans with
## the controls. The hull is built from code too (a flat-shaded low-poly hull, a seat and
## handlebars) unless [member hull_scene] gives a model to draw instead.
##
## [JetSki] calls [method set_pose] and [method set_rider] every frame, and sets [member seat]
## from the craft's Seat marker. A replacement model only needs to be a Node3D scene,
## optionally with the same methods; the physics never reads the model. Model space matches
## the craft: -Z forward, +Y up, origin on the keel at mid-length.
##
## The rider's parts hang under their own node, so after a crash the rider can leave the
## craft: [method set_rider] places the rider's pelvis anywhere in the world, in a tumbling,
## swimming or climbing pose.

## A scene to draw as the hull instead of the code-built one, in model space. Empty: the
## code-built hull. Named Marker3D nodes in it tell the rider where to hold on:
## [br]- [code]Handlebar[/code]: the steering pivot. It turns about its own Y axis with the
## steering, and so does everything under it, so put the handlebar's meshes there. The hands
## hold it [constant GRIP_SPREAD] either side along its X axis.
## [br]- [code]FootLeft[/code] and [code]FootRight[/code]: the footrests.
## [br]- [code]BottomLine[/code] and [code]TrimLine[/code] (optional): where the paint
## changes colour, by their height. See [member hull_color].
## [br]The rider sits at [member seat], which comes from the craft, not from the hull scene.
@export var hull_scene: PackedScene:
	set(value):
		hull_scene = value
		_queue_build()

@export_group("Colours")
## The hull's main colour. On a [member hull_scene], the light grey and white parts of each
## StandardMaterial3D's texture are painted: [member bottom_color] below the BottomLine
## marker, [member trim_color] from there up to the TrimLine marker, this colour above.
## Dark and strongly coloured parts keep their own colour.
@export var hull_color: Color = Color(0.98, 0.78, 0.10):
	set(value):
		hull_color = value
		_queue_build()
@export var trim_color: Color = Color(0.10, 0.35, 0.85):
	set(value):
		trim_color = value
		_queue_build()
@export var bottom_color: Color = Color(0.94, 0.95, 0.97):
	set(value):
		bottom_color = value
		_queue_build()
@export var deck_color: Color = Color(0.22, 0.24, 0.28):
	set(value):
		deck_color = value
		_queue_build()
@export var seat_color: Color = Color(0.08, 0.10, 0.16):
	set(value):
		seat_color = value
		_queue_build()
@export var suit_color: Color = Color(0.85, 0.12, 0.14):
	set(value):
		suit_color = value
		_queue_build()
@export var vest_color: Color = Color(1.0, 0.86, 0.1):
	set(value):
		vest_color = value
		_queue_build()
@export var helmet_color: Color = Color(0.95, 0.96, 1.0):
	set(value):
		helmet_color = value
		_queue_build()
@export var skin_color: Color = Color(0.86, 0.66, 0.5):
	set(value):
		skin_color = value
		_queue_build()

## How much of the model to hide, from 0 (all of it drawn) to 1: [ChaseCamera] fades a craft
## that comes between it and the craft it follows. Drawn as a dither (alpha hash) in the
## opaque pass, so a faded craft still sorts correctly against the water. A ghost doesn't fade.
@export_range(0.0, 1.0, 0.01) var fade: float = 0.0:
	set(value):
		value = clampf(value, 0.0, 1.0)
		if value == fade:
			return
		fade = value
		_apply_fade()

## Draw see-through and without shadows, for a time-trial ghost.
@export var ghost: bool = false:
	set(value):
		ghost = value
		_queue_build()

@export_group("Pose")
## How far the rider's body tips forward at full forward lean, and back at full back lean.
@export_range(0.0, 60.0, 0.1, "degrees") var lean_forward_angle: float = 28.0
@export_range(0.0, 60.0, 0.1, "degrees") var lean_back_angle: float = 22.0
## How far the body leans into a full-lock turn.
@export_range(0.0, 45.0, 0.1, "degrees") var turn_lean_angle: float = 16.0
## Handlebar rotation at full lock.
@export_range(0.0, 60.0, 0.1, "degrees") var bar_angle: float = 24.0
## How quickly the pose follows the controls, per second.
@export_range(0.1, 50.0, 0.1) var pose_response: float = 10.0

## What the rider is doing, for [method set_rider].
enum RiderMode {
	## Seated, riding.
	ABOARD,
	## Thrown off, tumbling through the air.
	THROWN,
	## In the water, swimming back to the craft.
	SWIMMING,
	## Climbing back on.
	MOUNTING,
}

## [member seat] until [JetSki] sets it: the Seat marker of jetski.tscn.
const DEFAULT_SEAT := Vector3(0.0, 1.12, 0.38)
## The code-built hull's handlebar pivot and footrests (left, right), in model space.
const HANDLEBAR_PIVOT := Vector3(0.0, 1.03, -0.42)
const FOOTRESTS: Array[Vector3] = [Vector3(-0.30, 0.56, 0.30), Vector3(0.30, 0.56, 0.30)]
## How far either side of the handlebar pivot the hands hold the bar, in meters.
const GRIP_SPREAD := 0.33
## The ghost look: alpha, glow colour and glow strength.
const GHOST_ALPHA := 0.38
const GHOST_GLOW := Color(0.55, 0.8, 1.0)
const GHOST_GLOW_ENERGY := 0.35
const HULL_PAINT := preload("res://jetski/model/hull_paint.gdshader")
const HULL_PAINT_GHOST := preload("res://jetski/model/hull_paint_ghost.gdshader")

# Hull cross-sections from bow to stern: z, half width, keel height, chine height, deck height.
const STATIONS: Array[Vector4] = [
	Vector4(-1.50, 0.03, 0.40, 0.44),
	Vector4(-1.28, 0.26, 0.17, 0.30),
	Vector4(-0.92, 0.45, 0.05, 0.19),
	Vector4(-0.40, 0.55, 0.0, 0.15),
	Vector4(0.40, 0.56, 0.0, 0.14),
	Vector4(1.10, 0.54, 0.02, 0.14),
	Vector4(1.42, 0.50, 0.04, 0.15),
]
const DECK_HEIGHTS: Array[float] = [0.50, 0.60, 0.62, 0.58, 0.55, 0.52, 0.48]

## Where the rider's pelvis sits when seated, in model space. [JetSki] sets it from the
## craft's Seat marker, so the drawn rider sits where a crash throws the rider from, and the
## climb back on ends there.
var seat: Vector3 = DEFAULT_SEAT

var _steer := 0.0
var _lean := 0.0
var _airborne := 0.0
var _target_steer := 0.0
var _target_lean := 0.0
var _target_airborne := 0.0
var _build_queued := false

var _parts: Dictionary[StringName, MeshInstance3D] = {}
# The node that turns with the steering, its transform at rest (in its parent's space), and
# that transform in model space. The hands follow the last one.
var _handlebar: Node3D
var _bar_rest := Transform3D(Basis.IDENTITY, HANDLEBAR_PIVOT)
var _bar_in_model := Transform3D(Basis.IDENTITY, HANDLEBAR_PIVOT)
var _feet: Array[Vector3] = FOOTRESTS.duplicate()
# The painted materials of the hull scene's meshes. Holding them here lets a rebuild free the
# meshes before their materials: freed the other way round, the renderer reports errors for
# the meshes' missing materials.
var _hull_materials: Array[Material] = []
# Every material [member fade] changes.
var _fading: Array[Material] = []
var _rider_root: Node3D
var _rider_mode: RiderMode = RiderMode.ABOARD
var _rider_pelvis := Transform3D.IDENTITY
var _mount_blend := 0.0
var _clock := 0.0
var _stunt: StringName = &""
var _stunt_progress := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		# The craft's script doesn't run in the editor, so take the seat from its Seat marker
		# here, to show the rider where the game will.
		var marker := get_node_or_null(^"../Seat") as Node3D
		if marker != null:
			seat = transform.affine_inverse() * marker.position
	_build()


func _process(delta: float) -> void:
	_clock += delta
	var blend := 1.0 - exp(-pose_response * delta)
	_steer = lerpf(_steer, _target_steer, blend)
	_lean = lerpf(_lean, _target_lean, blend)
	_airborne = lerpf(_airborne, _target_airborne, blend)
	_apply_pose()


## Sets the pose to blend toward: steer and lean from -1 to 1, throttle 0 to 1.
func set_pose(steer: float, lean: float, _throttle: float, airborne: bool) -> void:
	_target_steer = clampf(steer, -1.0, 1.0)
	_target_lean = clampf(lean, -1.0, 1.0)
	_target_airborne = 1.0 if airborne else 0.0


## Shows a stunt: [param stunt] is a key of [constant JetSki.STUNTS] or empty, and
## [param progress] runs from 0 to 1. A handstand is the rider's own pose; for a roll, flip
## or spin the craft turns the whole model and the rider tucks in.
func set_stunt(stunt: StringName, progress: float) -> void:
	_stunt = stunt
	_stunt_progress = clampf(progress, 0.0, 1.0)


## Places the rider. ABOARD seats the rider on the craft. Otherwise [param pelvis] is the
## rider's pelvis in world space (its -Z the way the rider faces, +Y toward the head), and
## for MOUNTING [param blend] goes from 0 (in the water at [param pelvis]) to 1 (seated).
func set_rider(mode: RiderMode, pelvis: Transform3D = Transform3D.IDENTITY, blend: float = 0.0) -> void:
	_rider_mode = mode
	_rider_pelvis = pelvis
	_mount_blend = clampf(blend, 0.0, 1.0)
	_place_rider_root()


func _place_rider_root() -> void:
	if _rider_root == null:
		return
	if _rider_mode == RiderMode.ABOARD:
		_rider_root.top_level = false
		_rider_root.transform = Transform3D.IDENTITY
		return
	_rider_root.top_level = true
	var pelvis := _rider_pelvis
	if _rider_mode == RiderMode.MOUNTING:
		var seated := get_global_transform_interpolated() * Transform3D(Basis.IDENTITY, seat)
		var t := _mount_blend * _mount_blend * (3.0 - 2.0 * _mount_blend)
		pelvis = Transform3D(pelvis.basis.slerp(seated.basis, t).orthonormalized(),
				pelvis.origin.lerp(seated.origin, t) + Vector3.UP * sin(PI * t) * 0.35)
	# The rider node's space is model space while seated, so its pelvis rests at the seat.
	_rider_root.global_transform = pelvis * Transform3D(Basis.IDENTITY, -seat)


func _queue_build() -> void:
	if not is_node_ready() or _build_queued:
		return
	_build_queued = true
	_build.call_deferred()


func _build() -> void:
	_build_queued = false
	for child in get_children(true):
		if child.has_meta(&"model_part"):
			child.free()
	_hull_materials.clear()
	_fading.clear()
	_parts.clear()
	_handlebar = null
	_bar_rest = Transform3D(Basis.IDENTITY, HANDLEBAR_PIVOT)
	_bar_in_model = _bar_rest
	_feet = FOOTRESTS.duplicate()
	if hull_scene != null:
		_build_hull_scene()
	else:
		_build_code_hull()
	_build_rider()
	_place_rider_root()
	_apply_pose()


## The flat-shaded hull, seat, hood, footwells and handlebar, all from code.
func _build_code_hull() -> void:
	var hull := MeshInstance3D.new()
	hull.mesh = _build_hull_mesh()
	_add_part(&"hull", hull)

	_add_box(&"seat", Vector3(0.40, 0.20, 0.95), Vector3(0.0, 0.66, 0.42), seat_color)
	_add_box(&"hood", Vector3(0.62, 0.22, 0.55), Vector3(0.0, 0.70, -0.62), hull_color.darkened(0.08))
	_add_box(&"column", Vector3(0.14, 0.34, 0.14), Vector3(0.0, 0.88, -0.48), deck_color)
	_add_box(&"footwell_left", Vector3(0.20, 0.03, 0.9), Vector3(-0.34, 0.50, 0.3), deck_color.darkened(0.3))
	_add_box(&"footwell_right", Vector3(0.20, 0.03, 0.9), Vector3(0.34, 0.50, 0.3), deck_color.darkened(0.3))
	_add_box(&"nozzle", Vector3(0.22, 0.14, 0.12), Vector3(0.0, 0.14, 1.46), deck_color.darkened(0.4))

	_handlebar = Node3D.new()
	_handlebar.position = HANDLEBAR_PIVOT
	_handlebar.set_meta(&"model_part", true)
	add_child(_handlebar, false, Node.INTERNAL_MODE_FRONT)
	var bar := MeshInstance3D.new()
	bar.mesh = _box_mesh(Vector3(0.74, 0.05, 0.05), deck_color.darkened(0.5))
	bar.layers = ShoreMap.DYNAMIC_LAYER
	bar.set_meta(&"model_part", true)
	_handlebar.add_child(bar, false, Node.INTERNAL_MODE_FRONT)


## Draws [member hull_scene] and reads its markers (see [member hull_scene]).
func _build_hull_scene() -> void:
	var hull := hull_scene.instantiate() as Node3D
	if hull == null:
		push_error("JetSkiModel: the hull scene %s needs a Node3D root." % hull_scene.resource_path)
		_build_code_hull()
		return
	hull.name = "Hull"
	hull.set_meta(&"model_part", true)
	add_child(hull, false, Node.INTERNAL_MODE_FRONT)
	_handlebar = hull.find_child("Handlebar", true, false) as Node3D
	if _handlebar != null:
		_bar_rest = _handlebar.transform
		_bar_in_model = _in_model_space(_handlebar)
		_bar_in_model.basis = _bar_in_model.basis.orthonormalized()
	else:
		push_warning("JetSkiModel: the hull scene %s has no Handlebar marker." % hull_scene.resource_path)
	for i in 2:
		var foot := hull.find_child("FootLeft" if i == 0 else "FootRight", true, false) as Node3D
		if foot != null:
			_feet[i] = _in_model_space(foot).origin
		else:
			push_warning("JetSkiModel: the hull scene %s has no %s marker." % [hull_scene.resource_path,
					"FootLeft" if i == 0 else "FootRight"])
	var bottom_line := _marker_height(hull, "BottomLine")
	var trim_line := _marker_height(hull, "TrimLine")
	_dress_hull(hull, bottom_line, trim_line)


## The height of the marker named [param marker_name] in model space, or far below the hull
## when there is none.
func _marker_height(hull: Node, marker_name: String) -> float:
	var marker := hull.find_child(marker_name, true, false) as Node3D
	return _in_model_space(marker).origin.y if marker != null else -1000.0


## [param node]'s transform relative to this model.
func _in_model_space(node: Node3D) -> Transform3D:
	var xform := node.transform
	var parent := node.get_parent()
	while parent != null and parent != self:
		if parent is Node3D:
			xform = (parent as Node3D).transform * xform
		parent = parent.get_parent()
	return xform


## Puts the hull scene's meshes on the moving-things layer, paints them in the rider's
## colours ([code]hull_paint.gdshader[/code]) and gives them the ghost look when
## [member ghost] is on.
func _dress_hull(node: Node, bottom_line: float, trim_line: float) -> void:
	for child in node.get_children():
		_dress_hull(child, bottom_line, trim_line)
	var geometry := node as GeometryInstance3D
	if geometry == null:
		return
	geometry.layers = ShoreMap.DYNAMIC_LAYER
	if ghost:
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh_instance := node as MeshInstance3D
	if mesh_instance == null or mesh_instance.mesh == null:
		return
	var xform := _in_model_space(mesh_instance)
	# The second row of the transform: a vertex's height in model space.
	var height_row := Vector4(xform.basis.x.y, xform.basis.y.y, xform.basis.z.y, xform.origin.y)
	if mesh_instance.material_override != null:
		mesh_instance.material_override = _hull_material(mesh_instance.material_override, height_row,
				bottom_line, trim_line)
		return
	for surface in mesh_instance.mesh.get_surface_count():
		var source := mesh_instance.get_active_material(surface)
		if source != null:
			mesh_instance.set_surface_override_material(surface,
					_hull_material(source, height_row, bottom_line, trim_line))


## A painted copy of a hull scene's material. A material that isn't a StandardMaterial3D
## isn't painted; on a ghost it becomes plain see-through white.
func _hull_material(source: Material, height_row: Vector4, bottom_line: float, trim_line: float) -> Material:
	var base := source as BaseMaterial3D
	if base == null:
		return _material(Color.WHITE) if ghost else source
	var paint := ShaderMaterial.new()
	paint.shader = HULL_PAINT_GHOST if ghost else HULL_PAINT
	# A ghost draws after the water, as the code-built ghost does (see _dress_material).
	paint.render_priority = 1 if ghost else base.render_priority
	var values := {
		&"albedo": base.albedo_color,
		&"albedo_texture": base.albedo_texture,
		&"uv1_scale": base.uv1_scale,
		&"uv1_offset": base.uv1_offset,
		&"roughness": base.roughness,
		&"metallic": base.metallic,
		&"specular": base.metallic_specular,
		&"use_normal_map": base.normal_enabled,
		&"normal_texture": base.normal_texture,
		&"normal_scale": base.normal_scale,
		&"use_ao": base.ao_enabled,
		&"ao_light_affect": base.ao_light_affect,
		&"hull_color": hull_color,
		&"trim_color": trim_color,
		&"bottom_color": bottom_color,
		&"height_from_vertex": height_row,
		&"bottom_line": bottom_line,
		&"trim_line": trim_line,
		&"ghost_alpha": GHOST_ALPHA,
		&"ghost_glow": GHOST_GLOW,
		&"ghost_glow_energy": GHOST_GLOW_ENERGY,
	}
	if base is ORMMaterial3D:
		# Occlusion in red, roughness in green, metallic in blue.
		values.merge({
			&"roughness_texture": base.orm_texture, &"roughness_channel": Vector4(0, 1, 0, 0),
			&"metallic_texture": base.orm_texture, &"metallic_channel": Vector4(0, 0, 1, 0),
			&"ao_texture": base.orm_texture, &"ao_channel": Vector4(1, 0, 0, 0),
		})
	else:
		values.merge({
			&"roughness_texture": base.roughness_texture,
			&"roughness_channel": _channel(base.roughness_texture_channel),
			&"metallic_texture": base.metallic_texture,
			&"metallic_channel": _channel(base.metallic_texture_channel),
			&"ao_texture": base.ao_texture,
			&"ao_channel": _channel(base.ao_texture_channel),
		})
	for key: StringName in values:
		paint.set_shader_parameter(key, values[key])
	_hull_materials.append(paint)
	if not ghost:
		paint.set_shader_parameter(&"fade", fade)
		_fading.append(paint)
	return paint


## The weights that pick one channel of a texture, as StandardMaterial3D does.
static func _channel(channel: BaseMaterial3D.TextureChannel) -> Vector4:
	match channel:
		BaseMaterial3D.TEXTURE_CHANNEL_GREEN:
			return Vector4(0, 1, 0, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_BLUE:
			return Vector4(0, 0, 1, 0)
		BaseMaterial3D.TEXTURE_CHANNEL_ALPHA:
			return Vector4(0, 0, 0, 1)
		BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE:
			return Vector4(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0, 0)
	return Vector4(1, 0, 0, 0)


## The rider: boxes between joints under their own node, placed every frame by _apply_pose().
func _build_rider() -> void:
	_rider_root = Node3D.new()
	_rider_root.name = "Rider"
	_rider_root.set_meta(&"model_part", true)
	add_child(_rider_root, false, Node.INTERNAL_MODE_FRONT)
	for side in [&"left", &"right"]:
		_add_box(StringName("shin_" + side), Vector3(0.13, 1.0, 0.14), Vector3.ZERO, suit_color.darkened(0.2), _rider_root)
		_add_box(StringName("thigh_" + side), Vector3(0.16, 1.0, 0.17), Vector3.ZERO, suit_color, _rider_root)
		_add_box(StringName("upper_arm_" + side), Vector3(0.11, 1.0, 0.11), Vector3.ZERO, suit_color, _rider_root)
		_add_box(StringName("forearm_" + side), Vector3(0.09, 1.0, 0.09), Vector3.ZERO, suit_color.darkened(0.15), _rider_root)
		_add_box(StringName("boot_" + side), Vector3(0.13, 0.1, 0.28), Vector3.ZERO, deck_color.darkened(0.5), _rider_root)
		_add_box(StringName("glove_" + side), Vector3(0.09, 0.09, 0.11), Vector3.ZERO, deck_color.darkened(0.5), _rider_root)
	_add_box(&"torso", Vector3(0.36, 1.0, 0.22), Vector3.ZERO, suit_color, _rider_root)
	_add_box(&"vest", Vector3(0.42, 1.0, 0.27), Vector3.ZERO, vest_color, _rider_root)
	_add_sphere(&"head", 0.11, skin_color, _rider_root)
	_add_sphere(&"helmet", 0.135, helmet_color, _rider_root)
	_add_box(&"visor", Vector3(0.2, 0.07, 0.04), Vector3.ZERO, Color(0.05, 0.08, 0.12), _rider_root)


func _apply_pose() -> void:
	if _parts.is_empty():
		return
	if _handlebar != null:
		_handlebar.transform = _bar_rest * Transform3D(_bar_turn(), Vector3.ZERO)
	_place_rider_root()
	var riding := _riding_joints()
	if _stunt == &"handstand":
		# Up onto the bars, hold, and back down onto the seat.
		var up := smoothstep(0.0, 0.3, _stunt_progress) * (1.0 - smoothstep(0.7, 1.0, _stunt_progress))
		riding = _blend_joints(riding, _handstand_joints(), up)
	var joints := riding
	match _rider_mode:
		RiderMode.THROWN:
			joints = _thrown_joints()
		RiderMode.SWIMMING:
			joints = _swimming_joints()
		RiderMode.MOUNTING:
			var t := _mount_blend * _mount_blend * (3.0 - 2.0 * _mount_blend)
			joints = _blend_joints(_swimming_joints(), riding, t)
	_pose_from(joints)


## Joint positions in model space (the rider node's space) for riding: the spine tips with
## the lean and the turn, hands on the bars, feet in the footwells.
func _riding_joints() -> Dictionary:
	var pitch := deg_to_rad(lean_forward_angle) * maxf(_lean, 0.0) - deg_to_rad(lean_back_angle) * maxf(-_lean, 0.0)
	var roll := _steer * deg_to_rad(turn_lean_angle)
	# The spine tips about the pelvis: forward for a forward lean, sideways into the turn.
	var spine := Basis(Vector3.RIGHT, -pitch) * Basis(Vector3.FORWARD, roll)
	var crouch := 0.06 * maxf(_lean, 0.0) - 0.08 * _airborne
	var tuck := 0.0
	if _stunt != &"" and _stunt != &"handstand":
		tuck = sin(PI * _stunt_progress)
		crouch += 0.14 * tuck
	var pelvis := seat + Vector3(_steer * 0.05, -crouch, 0.06 * maxf(_lean, 0.0))
	var chest := pelvis + spine * Vector3(0.0, 0.46, -0.24)
	var joints := {
		"spine": spine,
		"pelvis": pelvis,
		"chest": chest,
		"neck": pelvis + spine * Vector3(0.0, 0.62, -0.30),
		"head": pelvis + spine * Vector3(0.0, 0.74, -0.33),
	}
	var bar := _bar_in_model * Transform3D(_bar_turn(), Vector3.ZERO)
	joints["hand_basis"] = bar.basis
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var tag := "_l" if i == 0 else "_r"
		var foot := _feet[i]
		var hip := pelvis + spine * Vector3(0.11 * side, 0.0, 0.0)
		var shoulder := chest + spine * Vector3(0.21 * side, 0.0, 0.0)
		var hand := bar * Vector3(GRIP_SPREAD * side, 0.0, 0.0)
		joints["hip" + tag] = hip
		joints["knee" + tag] = (hip + foot) * 0.5 + Vector3(0.06 * side, 0.08 * tuck, -0.24 - 0.05 * _airborne - 0.08 * tuck)
		joints["foot" + tag] = foot
		joints["shoulder" + tag] = shoulder
		joints["elbow" + tag] = (shoulder + hand) * 0.5 + Vector3(0.12 * side, -0.06, 0.06)
		joints["hand" + tag] = hand
	return joints


## A handstand on the handlebars: the body upside down above the bars, legs straight up.
## The spine is turned forward over the bars by 207°, which puts the chest straight under
## the pelvis; blending from the riding pose swings the body forward, not backward.
func _handstand_joints() -> Dictionary:
	var bar := _bar_in_model.origin
	var spine := Basis(Vector3.RIGHT, -2.66)
	var pelvis := bar + Vector3(0.0, 1.07, 0.02)
	var chest := pelvis + spine * Vector3(0.0, 0.46, -0.24)
	var joints := {
		"spine": spine,
		"pelvis": pelvis,
		"chest": chest,
		"neck": pelvis + spine * Vector3(0.0, 0.62, -0.30),
		"head": pelvis + spine * Vector3(0.0, 0.74, -0.33),
		"hand_basis": _bar_in_model.basis,
	}
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var tag := "_l" if i == 0 else "_r"
		var hip := pelvis + spine * Vector3(0.11 * side, 0.0, 0.0)
		var shoulder := chest + spine * Vector3(0.21 * side, 0.0, 0.0)
		var hand := _bar_in_model * Vector3(GRIP_SPREAD * side, 0.0, 0.0)
		var foot := bar + Vector3(0.16 * side, 1.92, 0.12)
		joints["hip" + tag] = hip
		joints["knee" + tag] = (hip + foot) * 0.5 + Vector3(0.02 * side, 0.0, -0.03)
		joints["foot" + tag] = foot
		joints["shoulder" + tag] = shoulder
		joints["elbow" + tag] = (shoulder + hand) * 0.5 + Vector3(0.05 * side, 0.0, 0.02)
		joints["hand" + tag] = hand
	return joints


## Thrown off: body straight, arms and legs flailing.
func _thrown_joints() -> Dictionary:
	var flail := _clock * 11.0
	return _straight_joints(
		func(side: float) -> Vector3: return Vector3(0.42 * side, 0.30 + 0.15 * sin(flail + side), 0.1 * cos(flail)),
		func(side: float) -> Vector3: return Vector3(0.24 * side, -0.80, 0.12 * sin(flail * 0.8 + side * 2.0)))


## Swimming a crawl: arms turning over in turn, legs kicking. The body's +Y points the way
## it swims; [JetSki] tilts it to lie in the water.
func _swimming_joints() -> Dictionary:
	var stroke := _clock * 4.2
	return _straight_joints(
		func(side: float) -> Vector3:
			var phase := stroke + (0.0 if side < 0.0 else PI)
			return Vector3(0.10 * side, 0.55 * cos(phase), -0.25 * maxf(sin(phase), 0.0) + 0.1 * minf(sin(phase), 0.0)),
		func(side: float) -> Vector3: return Vector3(0.07 * side, -0.86, 0.12 * sin(stroke * 2.0 + side * 1.5)))


## A straight body with its pelvis at the seat; [param hand_offset] and [param foot_offset]
## give each hand relative to its shoulder and each foot relative to its hip, for side -1 or 1.
func _straight_joints(hand_offset: Callable, foot_offset: Callable) -> Dictionary:
	var pelvis := seat
	var chest := pelvis + Vector3(0.0, 0.46, -0.04)
	var joints := {
		"spine": Basis.IDENTITY,
		"pelvis": pelvis,
		"chest": chest,
		"neck": pelvis + Vector3(0.0, 0.62, -0.04),
		"head": pelvis + Vector3(0.0, 0.76, -0.05),
		"hand_basis": Basis.IDENTITY,
	}
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var tag := "_l" if i == 0 else "_r"
		var hip := pelvis + Vector3(0.11 * side, 0.0, 0.0)
		var shoulder := chest + Vector3(0.21 * side, 0.0, 0.0)
		var hand: Vector3 = shoulder + hand_offset.call(side)
		var foot: Vector3 = hip + foot_offset.call(side)
		joints["hip" + tag] = hip
		joints["knee" + tag] = (hip + foot) * 0.5 + Vector3(0.03 * side, 0.0, -0.08)
		joints["foot" + tag] = foot
		joints["shoulder" + tag] = shoulder
		joints["elbow" + tag] = (shoulder + hand) * 0.5 + Vector3(0.08 * side, 0.0, 0.06)
		joints["hand" + tag] = hand
	return joints


## The handlebar's turn for the steering, about its own Y axis.
func _bar_turn() -> Basis:
	return Basis(Vector3.UP, -_steer * deg_to_rad(bar_angle))


func _blend_joints(from: Dictionary, to: Dictionary, t: float) -> Dictionary:
	var out := {}
	for key in to:
		var a: Variant = from[key]
		var b: Variant = to[key]
		if a is Basis:
			out[key] = (a as Basis).slerp(b as Basis, t).orthonormalized()
		else:
			out[key] = (a as Vector3).lerp(b as Vector3, t)
	return out


## Places every rider part from a set of joints.
func _pose_from(joints: Dictionary) -> void:
	var spine: Basis = joints["spine"]
	var pelvis: Vector3 = joints["pelvis"]
	var chest: Vector3 = joints["chest"]
	var head: Vector3 = joints["head"]
	_place_between(&"torso", pelvis, joints["neck"])
	_place_between(&"vest", pelvis + spine * Vector3(0.0, 0.16, -0.07), chest + spine * Vector3(0.0, 0.05, 0.0))
	_set_part(&"head", Transform3D(spine, head))
	_set_part(&"helmet", Transform3D(spine, head + spine * Vector3(0.0, 0.025, 0.01)))
	_set_part(&"visor", Transform3D(spine, head + spine * Vector3(0.0, 0.0, -0.13)))
	var hand_basis: Basis = joints["hand_basis"]
	for tag in ["_l", "_r"]:
		var side_name := "left" if tag == "_l" else "right"
		_place_between(StringName("thigh_" + side_name), joints["hip" + tag], joints["knee" + tag])
		_place_between(StringName("shin_" + side_name), joints["knee" + tag], joints["foot" + tag])
		_set_part(StringName("boot_" + side_name), Transform3D(spine if _rider_mode != RiderMode.ABOARD else Basis.IDENTITY,
				joints["foot" + tag] + Vector3(0.0, -0.02, -0.05)))
		_place_between(StringName("upper_arm_" + side_name), joints["shoulder" + tag], joints["elbow" + tag])
		_place_between(StringName("forearm_" + side_name), joints["elbow" + tag], joints["hand" + tag])
		_set_part(StringName("glove_" + side_name), Transform3D(hand_basis, joints["hand" + tag]))


## Stretches a unit-height box part between two points.
func _place_between(part: StringName, from: Vector3, to: Vector3) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 0.001:
		return
	var y := axis / length
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 1e-4:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	_set_part(part, Transform3D(Basis(x, y * length, z), (from + to) * 0.5))


func _set_part(part: StringName, xform: Transform3D) -> void:
	var node: MeshInstance3D = _parts.get(part)
	if node != null:
		node.transform = xform


func _add_part(part: StringName, node: MeshInstance3D, parent: Node = self) -> void:
	node.name = String(part)
	node.layers = ShoreMap.DYNAMIC_LAYER
	if ghost:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.set_meta(&"model_part", true)
	parent.add_child(node, false, Node.INTERNAL_MODE_FRONT)
	_parts[part] = node


func _add_box(part: StringName, size: Vector3, at: Vector3, color: Color, parent: Node = self) -> void:
	var node := MeshInstance3D.new()
	node.mesh = _box_mesh(size, color)
	node.position = at
	_add_part(part, node, parent)


func _add_sphere(part: StringName, radius: float, color: Color, parent: Node = self) -> void:
	var node := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 5
	sphere.material = _material(color)
	node.mesh = sphere
	_add_part(part, node, parent)


func _box_mesh(size: Vector3, color: Color) -> BoxMesh:
	var box := BoxMesh.new()
	box.size = size
	box.material = _material(color)
	return box


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.55
	_dress_material(material)
	return material


## A ghost's material is see-through and glows faintly, so it reads as not really there.
## Any other material is dithered by [member fade]: alpha hash, opaque while the model isn't
## faded.
func _dress_material(material: StandardMaterial3D) -> void:
	if not ghost:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
		material.albedo_color.a = 1.0 - fade
		_fading.append(material)
		return
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = GHOST_ALPHA
	material.emission_enabled = true
	material.emission = GHOST_GLOW
	material.emission_energy_multiplier = GHOST_GLOW_ENERGY
	# Drawn after the water: both are see-through, and the water's mesh follows the camera,
	# so by distance it would sort nearer and draw over the ghost.
	material.render_priority = 1


func _apply_fade() -> void:
	for material in _fading:
		if material is StandardMaterial3D:
			(material as StandardMaterial3D).albedo_color.a = 1.0 - fade
		elif material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter(&"fade", fade)


## Builds the hull from its cross-sections, flat shaded, coloured by band.
func _build_hull_mesh() -> ArrayMesh:
	var rings: Array[PackedVector3Array] = []
	for s in STATIONS.size():
		var st := STATIONS[s]
		var z := st.x
		var w := st.y
		var deck := DECK_HEIGHTS[s]
		rings.append(PackedVector3Array([
			Vector3(-w * 0.80, deck, z),          # deck edge, left
			Vector3(-w, deck - 0.07, z),          # gunwale, left
			Vector3(-w * 0.97, st.w, z),          # chine, left
			Vector3(0.0, st.z, z),                # keel
			Vector3(w * 0.97, st.w, z),           # chine, right
			Vector3(w, deck - 0.07, z),           # gunwale, right
			Vector3(w * 0.80, deck, z),           # deck edge, right
			Vector3(0.0, deck + 0.025, z),        # deck centre
		]))
	# Colour of each band between consecutive ring points.
	var band_colors: Array[Color] = [trim_color, hull_color, bottom_color, bottom_color,
			hull_color, trim_color, deck_color, deck_color]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for s in rings.size() - 1:
		var a := rings[s]
		var b := rings[s + 1]
		var centre := Vector3(0.0, 0.3, (a[0].z + b[0].z) * 0.5)
		for k in 8:
			var k2 := (k + 1) % 8
			_add_triangle(vertices, normals, colors, a[k], b[k], b[k2], centre, band_colors[k])
			_add_triangle(vertices, normals, colors, a[k], b[k2], a[k2], centre, band_colors[k])
	# Transom: close the stern with a fan.
	var stern := rings[rings.size() - 1]
	var stern_centre := Vector3(0.0, 0.3, stern[0].z)
	var outward := stern_centre - Vector3(0.0, 0.3, 0.0)
	for k in 8:
		_add_triangle(vertices, normals, colors, stern_centre, stern[k], stern[(k + 1) % 8],
				stern_centre - outward, deck_color.darkened(0.2))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.6
	_dress_material(material)
	mesh.surface_set_material(0, material)
	return mesh


## Adds a flat-shaded triangle facing away from [param inside].
func _add_triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, inside: Vector3, color: Color) -> void:
	var normal := (c - a).cross(b - a)
	if normal.length_squared() < 1e-10:
		return
	normal = normal.normalized()
	if normal.dot((a + b + c) / 3.0 - inside) < 0.0:
		var swap := b
		b = c
		c = swap
		normal = -normal
	vertices.append_array(PackedVector3Array([a, b, c]))
	normals.append_array(PackedVector3Array([normal, normal, normal]))
	colors.append_array(PackedColorArray([color, color, color]))
