class_name LibraryHeader
extends PanelContainer
## The gradient card at the top of a library page: artwork, eyebrow, title,
## subtitle, count line with a now-playing marker, and the spectrum on wide
## windows. The gradient is drawn once per size or palette change.

var _bg := Control.new()
var _art := Artwork.new(true)
var _eyebrow: Label
var _title: Label
var _subtitle: Label
var _dot := Control.new()
var _count: Label
var _playing_icon: Label
var _playing_text: Label
var _spectrum := SpectrumView.new()
var _margin := MarginContainer.new()
var _art_slot := Control.new()
var _text_col := VBoxContainer.new()
var _compact := false


func _init() -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var clip := StyleBoxFlat.new()
	clip.bg_color = Color.BLACK
	clip.set_corner_radius_all(18)
	add_theme_stylebox_override("panel", clip)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.draw.connect(_draw_bg)
	add_child(_bg)
	_margin.add_theme_constant_override("margin_left", 25)
	_margin.add_theme_constant_override("margin_right", 25)
	_margin.add_theme_constant_override("margin_top", 25)
	_margin.add_theme_constant_override("margin_bottom", 25)
	add_child(_margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	_margin.add_child(row)
	_art_slot.custom_minimum_size = Vector2(115, 115)
	_art_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Godot cannot nest clip_children; the header already clips to its rounded corners.
	_art.disable_clip()
	_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_art_slot.add_child(_art)
	row.add_child(_art_slot)
	_text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_text_col.add_theme_constant_override("separation", 6)
	row.add_child(_text_col)
	_eyebrow = UiKit.label("", 9)
	_text_col.add_child(_eyebrow)
	_title = UiKit.label("", 31, null, true)
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.clip_text = true
	_text_col.add_child(_title)
	_subtitle = UiKit.label("", 12)
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.max_lines_visible = 2
	_text_col.add_child(_subtitle)
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 7)
	_text_col.add_child(count_row)
	_dot.custom_minimum_size = Vector2(6, 6)
	_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dot.draw.connect(func() -> void: _dot.draw_circle(Vector2(3, 3), 3.0, ThemeBuilder.palette.accent))
	count_row.add_child(_dot)
	_count = UiKit.label("", 11)
	count_row.add_child(_count)
	_playing_icon = Icons.label("graphic_eq", 15)
	_playing_text = UiKit.label("Now playing", 11)
	count_row.add_child(_playing_icon)
	count_row.add_child(_playing_text)
	_spectrum.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_spectrum)
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: _recolor())


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_bg.queue_redraw()


func _draw_bg() -> void:
	var p := ThemeBuilder.palette
	var c0 := p.surface.lerp(p.accent, 0.13)
	var c1 := p.surface.lerp(p.secondary, 0.10)
	var c2 := p.surface
	var r := Rect2(Vector2.ZERO, _bg.size)
	var tl := r.position
	var tr := Vector2(r.end.x, r.position.y)
	var br := r.end
	var bl := Vector2(r.position.x, r.end.y)
	var mid := r.get_center()
	_bg.draw_polygon(PackedVector2Array([mid, tl, tr]), PackedColorArray([c1, c0, c1]))
	_bg.draw_polygon(PackedVector2Array([mid, tr, br]), PackedColorArray([c1, c1, c2]))
	_bg.draw_polygon(PackedVector2Array([mid, br, bl]), PackedColorArray([c1, c2, c1]))
	_bg.draw_polygon(PackedVector2Array([mid, bl, tl]), PackedColorArray([c1, c1, c0]))
	var edge := StyleBoxFlat.new()
	edge.draw_center = false
	edge.border_color = Color(p.foreground.r, p.foreground.g, p.foreground.b, 0.055)
	edge.set_border_width_all(1)
	edge.set_corner_radius_all(18)
	_bg.draw_style_box(edge, r)


func _recolor() -> void:
	var p := ThemeBuilder.palette
	_eyebrow.add_theme_color_override("font_color", p.muted)
	_title.add_theme_color_override("font_color", p.foreground)
	_subtitle.add_theme_color_override("font_color", p.muted)
	_count.add_theme_color_override("font_color", p.muted)
	_playing_icon.add_theme_color_override("font_color", p.accent)
	_playing_text.add_theme_color_override("font_color", p.accent)
	_dot.queue_redraw()
	_bg.queue_redraw()


## `d`: title, eyebrow, subtitle, count, icon, track, compact, show_art,
## show_spectrum, now_playing.
func apply(d: Dictionary) -> void:
	_compact = d["compact"]
	var pad := 12 if _compact else 25
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_" + side, pad)
	_art_slot.visible = d["show_art"]
	_art.icon_name = d["icon"]
	_art.set_track(d["track"])
	_eyebrow.visible = not _compact
	_eyebrow.text = d["eyebrow"]
	_title.text = d["title"]
	_title.add_theme_font_size_override("font_size", 20 if _compact else 31)
	_subtitle.visible = not _compact
	_subtitle.text = d["subtitle"]
	_count.text = d["count"]
	var np: bool = d["now_playing"]
	_playing_icon.visible = np
	_playing_text.visible = np
	_spectrum.visible = d["show_spectrum"]
	_recolor()
