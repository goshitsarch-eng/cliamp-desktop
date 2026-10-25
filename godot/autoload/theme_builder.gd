extends Node
## Builds the application Theme from a Palette and applies it to the root window.

signal palette_changed(palette: Palette)

var palette := Palette.new()


func _ready() -> void:
	apply(palette)


func apply_engine_theme(theme: Dictionary) -> void:
	apply(Palette.from_engine(theme))


func apply(p: Palette) -> void:
	palette = p
	get_tree().root.theme = build(p)
	palette_changed.emit(p)


static func build(p: Palette) -> Theme:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", p.foreground)
	t.set_color("font_color", "Button", p.foreground)
	t.set_color("font_hover_color", "Button", p.foreground)
	t.set_color("font_pressed_color", "Button", p.on_accent())
	t.set_color("font_color", "LineEdit", p.foreground)
	t.set_color("font_placeholder_color", "LineEdit", p.muted)
	t.set_stylebox("panel", "PanelContainer", _box(p.surface, 12))
	t.set_stylebox("panel", "Panel", _box(p.surface, 12))
	t.set_stylebox("normal", "Button", _box(_alpha(p.foreground, 0.06), 10, 14, 8))
	t.set_stylebox("hover", "Button", _box(_alpha(p.foreground, 0.12), 10, 14, 8))
	t.set_stylebox("pressed", "Button", _box(p.accent, 10, 14, 8))
	t.set_stylebox("focus", "Button", _outline(p.accent, 10))
	t.set_stylebox("normal", "LineEdit", _box(_alpha(p.foreground, 0.045), 12, 16, 10))
	t.set_stylebox("focus", "LineEdit", _outline(p.accent, 12))
	return t


static func _alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


static func _box(color: Color, radius: int, pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


static func _outline(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = color
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	return s
