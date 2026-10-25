class_name Icons
extends RefCounted
## Material Icons Round glyphs by name, e.g. Icons.label("play_arrow"). Names are
## the Flutter Icons names without the "_rounded" suffix, see icon_glyphs.gd.

const FONT_PATH := "res://assets/fonts/MaterialIconsRound.otf"

static var _font: Font


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH)
	return _font


static func glyph(icon_name: String) -> String:
	var code: int = IconGlyphs.CODEPOINTS.get(icon_name, 0)
	return char(code) if code != 0 else ""


## A Label showing one icon. Decorative: hidden from screen readers.
static func label(icon_name: String, size := 20, color: Variant = null) -> Label:
	var l := Label.new()
	l.text = glyph(icon_name)
	l.add_theme_font_override("font", font())
	l.add_theme_font_size_override("font_size", size)
	if color is Color:
		l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Flat icon-only button. `tooltip` is also the accessibility name.
static func button(icon_name: String, tooltip: String, callback: Callable = Callable(), size := 20, toggled := false) -> Button:
	var b := Button.new()
	b.flat = true
	b.text = glyph(icon_name)
	b.tooltip_text = tooltip
	b.accessibility_name = tooltip
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", font())
	b.add_theme_font_size_override("font_size", size)
	b.custom_minimum_size = Vector2(size + 16, size + 12)
	if toggled:
		b.toggle_mode = true
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


## Changes the glyph of a button made with button().
static func set_glyph(b: Button, icon_name: String) -> void:
	b.text = glyph(icon_name)
