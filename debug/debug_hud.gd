class_name DebugHud
extends CanvasLayer
## A text readout of the craft's telemetry for tuning: speed, height above the water, grip,
## lean and the rest. toggle_debug (F3) shows and hides it.

@export var craft: JetSki
@export var chase_camera: ChaseCamera
## Show the readout when the scene starts.
@export var start_visible: bool = true

var _label: Label
var _hint: Label


func _ready() -> void:
	layer = 10
	_label = Label.new()
	_label.position = Vector2(24.0, 20.0)
	_label.add_theme_font_size_override(&"font_size", 22)
	_label.add_theme_color_override(&"font_color", Color(1.0, 1.0, 1.0))
	_label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_label.add_theme_constant_override(&"shadow_offset_x", 2)
	_label.add_theme_constant_override(&"shadow_offset_y", 2)
	add_child(_label)
	_hint = Label.new()
	_hint.add_theme_font_size_override(&"font_size", 18)
	_hint.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.85))
	_hint.add_theme_constant_override(&"shadow_offset_x", 2)
	_hint.add_theme_constant_override(&"shadow_offset_y", 2)
	_hint.text = "Space throttle   A/D steer   W/S lean   R reset   C camera   F3 readout"
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.offset_left = 24.0
	_hint.offset_top = -44.0
	add_child(_hint)
	visible = start_visible


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_debug"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible or craft == null:
		return
	var t := craft.telemetry()
	var lines: PackedStringArray = []
	lines.append("speed      %5.1f km/h  (%4.1f m/s through water)" % [t["speed_kmh"], t["forward_speed"]])
	lines.append("slip       %5.1f deg   side %4.1f m/s" % [t["slip_degrees"], t["side_speed"]])
	lines.append("grip use   %5.2f %s%s" % [t["grip_usage"], "SLIDING " if t["sliding"] else "", "CARVING" if t["carving"] else ""])
	lines.append("contact    %5.2f   clearance %5.2f m" % [t["contact"], t["clearance"]])
	lines.append("air        %s %4.2f s" % ["AIRBORNE" if t["airborne"] else "on water", t["air_time"]])
	lines.append("pitch      %5.1f deg   roll %5.1f deg" % [t["pitch_degrees"], t["roll_degrees"]])
	lines.append("throttle   %4.2f  thrust %4.2f  steer %5.2f  lean %5.2f" % [craft.controls.throttle, t["thrust"], craft.controls.steer, craft.controls.lean])
	if chase_camera != null:
		lines.append("camera gap %5.2f m above water (lowest)" % chase_camera.min_water_gap)
	_label.text = "\n".join(lines)
