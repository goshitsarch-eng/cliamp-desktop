class_name UiKit
extends RefCounted
## Small control factories shared by the library widgets and dialogs.

static var _mixed_font: Font


## The default font with the icon font as fallback, so one label or button can
## hold text and an icon glyph.
static func mixed_font() -> Font:
	if _mixed_font == null:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.fallbacks = [Icons.font()]
		_mixed_font = f
	return _mixed_font


static func tint(b: Control, color: Color) -> void:
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(key, color)
	b.add_theme_color_override("font_disabled_color", Color(color.r, color.g, color.b, 0.4))


static func label(text: String, size := 13, color: Variant = null, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color is Color:
		l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", bold_font())
	return l


static var _bold: Font


static func bold_font() -> Font:
	if _bold == null:
		var f := FontVariation.new()
		f.base_font = ThemeDB.fallback_font
		f.variation_embolden = 0.6
		_bold = f
	return _bold


## A text button with a leading icon glyph (icon_name may be empty).
static func text_button(icon_name: String, text: String, callback: Callable = Callable(), tooltip := "", size := 13) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = (Icons.glyph(icon_name) + "  " + text) if not icon_name.is_empty() else text
	b.add_theme_font_override("font", mixed_font())
	b.add_theme_font_size_override("font_size", size)
	b.tooltip_text = tooltip
	b.accessibility_name = tooltip if not tooltip.is_empty() else text
	b.focus_mode = Control.FOCUS_ALL
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


## Outlined pill button used for the provider browse tabs.
static func chip(icon_name: String, text: String, callback: Callable, selected := false) -> Button:
	var p := ThemeBuilder.palette
	var b := text_button(icon_name, text, callback, text, 11)
	b.flat = false
	var edge := Color(p.accent.r, p.accent.g, p.accent.b, 0.3) if selected else Color(p.foreground.r, p.foreground.g, p.foreground.b, 0.07)
	var fill := Color(p.accent.r, p.accent.g, p.accent.b, 0.06) if selected else Color(0, 0, 0, 0)
	var hover := Color(p.foreground.r, p.foreground.g, p.foreground.b, 0.08)
	b.add_theme_stylebox_override("normal", _pill(fill, edge))
	b.add_theme_stylebox_override("hover", _pill(hover, edge))
	b.add_theme_stylebox_override("pressed", _pill(hover, edge))
	tint(b, p.accent if selected else p.muted)
	return b


static func _pill(fill: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(9)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


## Frees all children immediately-safe (queue_free) and detaches them.
static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Presses the OK button of the dialog that holds `content`, as Enter would.
static func accept(content: Node) -> void:
	var window := content.get_window()
	if window is AcceptDialog:
		(window as AcceptDialog).get_ok_button().pressed.emit()
