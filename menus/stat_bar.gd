class_name StatBar
extends Control
## A rider's stat as a row of slanted segments, like the power meter: [member value] of
## [member segments] filled, in half steps. It eases toward a new value.

@export_range(1, 10, 1) var segments: int = 5
@export_range(0.0, 10.0, 0.5) var value: float = 3.0
@export var fill_color: Color = Color(1.0, 0.86, 0.12)
@export var empty_color: Color = Color(0.02, 0.05, 0.16, 0.55)
@export var outline_color: Color = Color(0.02, 0.05, 0.16, 0.9)
@export_range(0.0, 20.0, 0.5) var gap: float = 6.0
@export_range(0.0, 1.0, 0.01) var slant: float = 0.35

var _shown := 0.0


func _ready() -> void:
	_shown = value


func _process(delta: float) -> void:
	if not is_equal_approx(_shown, value):
		_shown = move_toward(_shown, value, delta * 12.0)
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var lean := h * slant
	var width := (size.x - lean - gap * (segments - 1)) / segments
	for i in segments:
		var x := i * (width + gap)
		var corners := PackedVector2Array([
			Vector2(x + lean, 0.0), Vector2(x + lean + width, 0.0),
			Vector2(x + width, h), Vector2(x, h),
		])
		draw_colored_polygon(corners, empty_color)
		var fill := clampf(_shown - i, 0.0, 1.0)
		if fill > 0.0:
			# Fill the left part of the segment, keeping its slant.
			var w := width * fill
			draw_colored_polygon(PackedVector2Array([
				Vector2(x + lean, 0.0), Vector2(x + lean + w, 0.0),
				Vector2(x + w, h), Vector2(x, h),
			]), fill_color)
		var closed := corners.duplicate()
		closed.append(corners[0])
		draw_polyline(closed, outline_color, 3.0, true)
