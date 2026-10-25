class_name Palette
extends RefCounted
## Resolves engine theme colors into readable desktop surfaces. The terminal's
## default ANSI theme has no RGB colors, so it keeps the desktop's own palette.

var background := Color("101217")
var surface := Color("191c24")
var sidebar := Color("14161d")
var foreground := Color("f4f5f8")
var muted := Color("9da4b6")
var accent := Color("81e6cd")
var secondary := Color("a29bfe")
var dark := true
## Text color for validation errors, readable on this theme's surfaces.
var error := Color("ff8a80")


static func from_engine(theme: Dictionary) -> Palette:
	var p := Palette.new()
	var bg = _hex(theme.get("bg"))
	if bg == null:
		return p
	p.background = bg
	p.dark = relative_luminance(bg) < 0.179
	p.error = Color("ff8a80") if p.dark else Color("b3261e")
	var fallback := Color.WHITE if p.dark else Color.BLACK
	var fg = _hex(theme.get("bright_fg"))
	if fg == null:
		fg = _hex(theme.get("fg"))
	if fg == null:
		fg = fallback
	p.foreground = _readable(fg, bg, fallback, 4.5)
	p.surface = bg.lerp(p.foreground, 0.045)
	p.sidebar = bg.lerp(p.foreground, 0.02)
	var acc = _hex(theme.get("accent"))
	if acc == null:
		acc = _hex(theme.get("green"))
	if acc == null:
		acc = p.foreground
	p.accent = _readable(acc, p.surface, fallback, 3.0)
	var mut = _hex(theme.get("fg"))
	if mut == null:
		mut = bg.lerp(p.foreground, 0.65)
	p.muted = _readable(mut, p.surface, p.foreground, 4.5)
	var sec = _hex(theme.get("green"))
	if sec == null:
		sec = p.accent
	p.secondary = _readable(sec, p.surface, p.foreground, 3.0)
	return p


func on_accent() -> Color:
	return Color.BLACK if relative_luminance(accent) > 0.179 else Color.WHITE


static func _hex(value: Variant) -> Variant:
	var text := str(value) if value != null else ""
	if text.length() != 7 or not text.begins_with("#") or not Color.html_is_valid(text):
		return null
	return Color(text)


static func _contrast(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## WCAG relative luminance (linear light). Color.get_luminance works on the
## gamma-encoded values, which overstates contrast thresholds.
static func relative_luminance(c: Color) -> float:
	var lin := func(v: float) -> float: return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


static func _readable(color: Color, background: Color, fallback: Color, ratio: float) -> Color:
	if _contrast(color, background) >= ratio:
		return color
	for i in range(1, 21):
		var candidate := color.lerp(fallback, i / 20.0)
		if _contrast(candidate, background) >= ratio:
			return candidate
	return fallback
