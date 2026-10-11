class_name RaceHud
extends CanvasLayer
## The heads-up display during a race: lap, race time and lap times, speed, the countdown
## and short messages for buoys, laps and going the wrong way. It reads the player's
## [RacerState] from [member race] and listens to the race's signals.

@export var race: Race

const YELLOW := Color(1.0, 0.86, 0.12)
const RED := Color(1.0, 0.22, 0.16)
const WHITE := Color(1.0, 1.0, 1.0)
const CYAN := Color(0.45, 0.92, 1.0)

var _font: FontVariation
var _lap_value: Label
var _time_value: Label
var _lap_list: Label
var _speed_value: Label
var _message: Label
var _sub_message: Label
var _wrong_way: Label
var _message_tween: Tween
var _sub_tween: Tween


func _ready() -> void:
	layer = 5
	_font = FontVariation.new()
	_font.base_font = ThemeDB.fallback_font
	_font.variation_embolden = 0.9
	_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.18, 1.0), Vector2.ZERO)
	_build()
	if race != null:
		race.countdown_changed.connect(_on_countdown)
		race.started.connect(_on_started)
		race.gate_judged.connect(_on_gate_judged)
		race.lap_completed.connect(_on_lap_completed)
		race.finished.connect(_on_finished)


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	# Top left: lap.
	var lap_box := _column(root, Control.PRESET_TOP_LEFT, Vector2(48.0, 32.0))
	lap_box.add_child(_label("LAP", 30, YELLOW))
	_lap_value = _label("1/3", 72, WHITE)
	lap_box.add_child(_lap_value)

	# Top right: race time and lap times.
	var time_box := _column(root, Control.PRESET_TOP_RIGHT, Vector2(-48.0, 32.0))
	time_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	var time_title := _label("TIME", 30, YELLOW)
	time_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_box.add_child(time_title)
	_time_value = _label("0:00.00", 64, WHITE)
	_time_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_box.add_child(_time_value)
	_lap_list = _label("", 30, WHITE)
	_lap_list.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	time_box.add_child(_lap_list)

	# Bottom right: speed.
	var speed_box := _column(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-48.0, -36.0))
	speed_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_speed_value = _label("0", 84, WHITE)
	_speed_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_box.add_child(_speed_value)
	var unit := _label("km/h", 28, YELLOW)
	unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	speed_box.add_child(unit)

	# Centre: countdown and messages.
	# Messages sit in the upper third, clear of the rider in the middle of the screen.
	_message = _label("", 150, WHITE)
	_centre(root, _message, -255.0)
	_sub_message = _label("", 52, WHITE)
	_centre(root, _sub_message, -150.0)
	_wrong_way = _label("WRONG WAY", 72, RED)
	_centre(root, _wrong_way, -150.0)
	_wrong_way.visible = false


func _column(parent: Control, preset: Control.LayoutPreset, offset: Vector2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override(&"separation", -6)
	parent.add_child(box)
	box.set_anchors_and_offsets_preset(preset)
	box.position += offset
	if preset == Control.PRESET_TOP_RIGHT or preset == Control.PRESET_BOTTOM_RIGHT:
		box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	return box


func _centre(parent: Control, label: Label, y: float) -> void:
	parent.add_child(label)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.position.y += y
	label.resized.connect(func() -> void: label.pivot_offset = label.size * 0.5)


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override(&"font", _font)
	label.add_theme_font_size_override(&"font_size", size)
	label.add_theme_color_override(&"font_color", color)
	label.add_theme_color_override(&"font_outline_color", Color(0.02, 0.05, 0.16))
	label.add_theme_constant_override(&"outline_size", maxi(size / 6, 6))
	label.add_theme_color_override(&"font_shadow_color", Color(0.0, 0.0, 0.0, 0.45))
	label.add_theme_constant_override(&"shadow_offset_x", 3)
	label.add_theme_constant_override(&"shadow_offset_y", 4)
	return label


func _process(_delta: float) -> void:
	if race == null or race.player == null:
		return
	var racer := race.player
	_lap_value.text = "%d/%d" % [mini(racer.laps_done + 1, race.laps), race.laps]
	var shown_time := racer.finish_time if racer.finished else race.race_time
	_time_value.text = Race.format_time(shown_time)
	_speed_value.text = "%d" % roundi(racer.craft.speed * 3.6)
	_wrong_way.visible = racer.wrong_way and not racer.finished and race.phase == Race.Phase.RACING
	var lines := PackedStringArray()
	var best := racer.best_lap()
	for i in racer.lap_times.size():
		var mark := "  BEST" if racer.lap_times.size() > 1 and racer.lap_times[i] == best else ""
		lines.append("L%d  %s%s" % [i + 1, Race.format_time(racer.lap_times[i]), mark])
	_lap_list.text = "\n".join(lines)


## Shows [param text] big in the middle of the screen for [param duration] seconds.
func show_message(text: String, color: Color = WHITE, duration: float = 1.2) -> void:
	_message.text = text
	_message.add_theme_color_override(&"font_color", color)
	if _message_tween != null:
		_message_tween.kill()
	_message.modulate.a = 1.0
	_message.scale = Vector2(1.6, 1.6)
	_message_tween = create_tween()
	_message_tween.tween_property(_message, ^"scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_message_tween.tween_interval(maxf(duration - 0.5, 0.0))
	_message_tween.tween_property(_message, ^"modulate:a", 0.0, 0.3)


## Shows a smaller line under the middle, for buoy calls.
func show_sub_message(text: String, color: Color = WHITE, duration: float = 0.9) -> void:
	_sub_message.text = text
	_sub_message.add_theme_color_override(&"font_color", color)
	if _sub_tween != null:
		_sub_tween.kill()
	_sub_message.modulate.a = 1.0
	_sub_message.scale = Vector2(1.3, 1.3)
	_sub_tween = create_tween()
	_sub_tween.tween_property(_sub_message, ^"scale", Vector2.ONE, 0.15)
	_sub_tween.tween_interval(maxf(duration - 0.4, 0.0))
	_sub_tween.tween_property(_sub_message, ^"modulate:a", 0.0, 0.25)


func _on_countdown(seconds_left: int) -> void:
	if seconds_left > 0:
		show_message(str(seconds_left), YELLOW, 0.95)


func _on_started() -> void:
	show_message("GO!", CYAN, 1.0)


func _on_gate_judged(racer: RacerState, gate: CourseGate, correct: bool) -> void:
	if not racer.is_player:
		return
	if correct:
		show_sub_message("NICE", gate.buoy.color().lightened(0.3) if gate.buoy != null else WHITE, 0.7)
	else:
		show_sub_message("MISSED BUOY", RED, 1.2)


func _on_lap_completed(racer: RacerState, lap: int, lap_time: float) -> void:
	if not racer.is_player or racer.finished:
		return
	var text := "FINAL LAP" if lap == race.laps - 1 else "LAP %d" % (lap + 1)
	show_message(text, YELLOW if lap == race.laps - 1 else WHITE, 1.6)
	show_sub_message(Race.format_time(lap_time), WHITE, 1.6)


func _on_finished() -> void:
	show_message("FINISH", YELLOW, 3.0)
	show_sub_message(Race.format_time(race.player.finish_time), WHITE, 3.0)
