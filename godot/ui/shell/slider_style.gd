class_name SliderStyle
extends RefCounted
## Thin accent sliders matching the Flutter player bar (3px track, round thumb).

static var _grabbers: Dictionary = {}


static func apply(slider: Slider, radius := 5) -> void:
	var p := ThemeBuilder.palette
	var track := StyleBoxFlat.new()
	track.bg_color = Color(p.foreground, 0.18)
	track.set_corner_radius_all(2)
	track.content_margin_top = 1.5
	track.content_margin_bottom = 1.5
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = p.accent
	slider.add_theme_stylebox_override("slider", track)
	slider.add_theme_stylebox_override("grabber_area", fill)
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var grabber := _grabber(p.accent, radius)
	slider.add_theme_icon_override("grabber", grabber)
	slider.add_theme_icon_override("grabber_highlight", grabber)
	slider.add_theme_icon_override("grabber_disabled", _grabber(Color(p.foreground, 0.3), radius))


static func _grabber(color: Color, radius: int) -> Texture2D:
	var key := "%s:%d" % [color.to_html(), radius]
	if _grabbers.has(key):
		return _grabbers[key]
	var size := radius * 2 + 2
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha := clampf(radius - d + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(color, alpha))
	var texture := ImageTexture.create_from_image(image)
	_grabbers[key] = texture
	return texture
