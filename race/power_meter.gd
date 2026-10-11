class_name PowerMeter
extends Control
## The power meter on the HUD: a row of slanted segments, one per level, filling from
## yellow to red. A new level flashes; losing the meter flashes every segment red.

## Number of segments.
@export_range(1, 10, 1) var levels: int = 5:
	set(value):
		levels = value
		queue_redraw()
## Filled segments.
@export_range(0, 10, 1) var value: int = 0:
	set(new_value):
		new_value = clampi(new_value, 0, levels)
		if new_value == value:
			return
		if new_value > value:
			_flash_index = new_value - 1
			_flash_time = FLASH_TIME
		elif new_value < value:
			_drain_time = DRAIN_TIME
			_drained_from = value
		value = new_value
		queue_redraw()
## Colour of the first and of the last segment; the ones between blend.
@export var low_color: Color = Color(1.0, 0.86, 0.12)
@export var high_color: Color = Color(1.0, 0.25, 0.12)
@export var empty_color: Color = Color(0.02, 0.05, 0.16, 0.55)
@export var outline_color: Color = Color(0.85, 0.9, 1.0, 0.55)
## How far each segment leans, as a share of its height.
@export_range(0.0, 1.0, 0.01) var slant: float = 0.35
## Gap between segments, in pixels.
@export_range(0.0, 20.0, 0.5) var gap: float = 6.0

const FLASH_TIME := 0.5
const DRAIN_TIME := 0.6

var _flash_index := -1
var _flash_time := 0.0
var _drain_time := 0.0
var _drained_from := 0
var _clock := 0.0


func _process(delta: float) -> void:
	_clock += delta
	var animating := _flash_time > 0.0 or _drain_time > 0.0 or value == levels
	_flash_time = maxf(_flash_time - delta, 0.0)
	_drain_time = maxf(_drain_time - delta, 0.0)
	if animating:
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var lean := h * slant
	var width := (size.x - lean - gap * (levels - 1)) / levels
	var full := value == levels
	for i in levels:
		var x := i * (width + gap)
		var points := PackedVector2Array([
			Vector2(x + lean, 0.0), Vector2(x + lean + width, 0.0),
			Vector2(x + width, h), Vector2(x, h),
		])
		var color := empty_color
		if i < value:
			color = low_color.lerp(high_color, float(i) / maxf(levels - 1, 1))
			if full:
				color = color.lightened(0.25 * (0.5 + 0.5 * sin(_clock * TAU * 2.0)))
			if i == _flash_index and _flash_time > 0.0:
				color = color.lerp(Color.WHITE, _flash_time / FLASH_TIME)
		elif _drain_time > 0.0 and i < _drained_from:
			color = high_color.lerp(empty_color, 1.0 - _drain_time / DRAIN_TIME)
		draw_colored_polygon(points, color)
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, outline_color, 3.0, true)
