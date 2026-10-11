class_name MenuStyle
extends RefCounted
## The look shared by the menus and the end-of-race screens: a bold slanted font, outlined
## labels, slanted buttons with a yellow focus frame, and a dark blue panel with a yellow
## border. Built in code, so there are no theme files to keep in step.

const YELLOW := Color(1.0, 0.86, 0.12)
const WHITE := Color(1.0, 1.0, 1.0)
const DIM := Color(0.72, 0.8, 0.95)
const RED := Color(1.0, 0.3, 0.22)
const CYAN := Color(0.45, 0.92, 1.0)
const OUTLINE := Color(0.02, 0.05, 0.16)

static var _font: FontVariation


## The bold, slanted font every menu uses.
static func font() -> FontVariation:
	if _font == null:
		_font = FontVariation.new()
		_font.base_font = ThemeDB.fallback_font
		_font.variation_embolden = 0.9
		_font.variation_transform = Transform2D(Vector2(1.0, 0.0), Vector2(-0.18, 1.0), Vector2.ZERO)
	return _font


static func label(text: String, size: int, color: Color = WHITE) -> Label:
	var node := Label.new()
	node.text = text
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_theme_font_override(&"font", font())
	node.add_theme_font_size_override(&"font_size", size)
	node.add_theme_color_override(&"font_color", color)
	node.add_theme_color_override(&"font_outline_color", OUTLINE)
	node.add_theme_constant_override(&"outline_size", maxi(size / 7, 4))
	return node


static func button(text: String, size: int = 38, min_size: Vector2 = Vector2(300, 72)) -> Button:
	var node := Button.new()
	node.text = text
	node.add_theme_font_override(&"font", font())
	node.add_theme_font_size_override(&"font_size", size)
	node.custom_minimum_size = min_size
	for state in [&"normal", &"hover", &"pressed", &"focus", &"disabled"]:
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(10)
		style.skew = Vector2(0.15, 0.0)
		# Room for the slant, so text never touches the edge.
		style.content_margin_left = 26
		style.content_margin_right = 26
		match state:
			&"normal":
				style.bg_color = Color(0.08, 0.24, 0.62)
			&"hover":
				style.bg_color = Color(0.12, 0.34, 0.8)
			&"pressed":
				style.bg_color = Color(0.9, 0.6, 0.05)
			&"disabled":
				style.bg_color = Color(0.1, 0.14, 0.26)
			&"focus":
				style.bg_color = Color(0, 0, 0, 0)
				style.border_color = YELLOW
				style.set_border_width_all(5)
				style.draw_center = false
		node.add_theme_stylebox_override(state, style)
	node.add_theme_color_override(&"font_color", WHITE)
	node.add_theme_color_override(&"font_focus_color", YELLOW)
	node.add_theme_color_override(&"font_hover_color", YELLOW)
	node.add_theme_color_override(&"font_disabled_color", Color(0.45, 0.5, 0.6))
	return node


## A dark blue panel with a yellow border, slightly slanted.
static func panel(margin_x: int = 64, margin_y: int = 38) -> PanelContainer:
	var node := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.12, 0.36, 0.92)
	style.border_color = YELLOW
	style.set_border_width_all(6)
	style.set_corner_radius_all(14)
	style.skew = Vector2(0.06, 0.0)
	style.content_margin_left = margin_x
	style.content_margin_right = margin_x
	style.content_margin_top = margin_y
	style.content_margin_bottom = margin_y
	node.add_theme_stylebox_override(&"panel", style)
	return node


## Drops the shared font, at exit.
static func release() -> void:
	_font = null
