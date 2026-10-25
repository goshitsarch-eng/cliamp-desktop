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
	# Icon-only buttons are sized by their glyph, so they get compact padding.
	t.set_type_variation("IconButton", "Button")
	t.set_stylebox("normal", "IconButton", _box(Color(0, 0, 0, 0), 10, 4, 2))
	t.set_stylebox("hover", "IconButton", _box(_alpha(p.foreground, 0.10), 10, 4, 2))
	t.set_stylebox("pressed", "IconButton", _box(_alpha(p.foreground, 0.18), 10, 4, 2))
	t.set_stylebox("disabled", "IconButton", _box(Color(0, 0, 0, 0), 10, 4, 2))
	t.set_stylebox("focus", "IconButton", _outline(p.accent, 10))
	for type_name in ["OptionButton", "MenuButton", "LinkButton"]:
		t.set_color("font_color", type_name, p.foreground)
		t.set_color("font_hover_color", type_name, p.foreground)
		t.set_color("font_pressed_color", type_name, p.foreground)
		t.set_color("font_hover_pressed_color", type_name, p.foreground)
		t.set_color("font_focus_color", type_name, p.foreground)
		t.set_color("font_disabled_color", type_name, _alpha(p.foreground, 0.4))
	t.set_color("font_disabled_color", "Button", _alpha(p.foreground, 0.4))
	t.set_color("font_focus_color", "Button", p.foreground)
	t.set_color("font_hover_pressed_color", "Button", p.on_accent())
	for type_name in ["OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type_name, _box(_alpha(p.foreground, 0.06), 10, 14, 8))
		t.set_stylebox("hover", type_name, _box(_alpha(p.foreground, 0.12), 10, 14, 8))
		t.set_stylebox("pressed", type_name, _box(_alpha(p.foreground, 0.16), 10, 14, 8))
		t.set_stylebox("focus", type_name, _outline(p.accent, 10))
	for type_name in ["TextEdit", "CodeEdit"]:
		t.set_color("font_color", type_name, p.foreground)
		t.set_color("font_readonly_color", type_name, p.foreground)
		t.set_color("font_placeholder_color", type_name, p.muted)
		t.set_color("caret_color", type_name, p.foreground)
		t.set_color("selection_color", type_name, _alpha(p.accent, 0.35))
		t.set_color("background_color", type_name, Color(0, 0, 0, 0))
		t.set_stylebox("normal", type_name, _box(_alpha(p.foreground, 0.045), 12, 14, 10))
		t.set_stylebox("focus", type_name, _outline(p.accent, 12))
		t.set_stylebox("read_only", type_name, _box(_alpha(p.foreground, 0.03), 12, 14, 10))
	t.set_color("selection_color", "LineEdit", _alpha(p.accent, 0.35))
	t.set_color("caret_color", "LineEdit", p.foreground)
	t.set_color("font_uneditable_color", "LineEdit", p.muted)
	var dialog_panel := _box(p.surface.lerp(p.foreground, 0.03), 0, 20, 16)
	for type_name in ["AcceptDialog", "ConfirmationDialog", "FileDialog"]:
		t.set_stylebox("panel", type_name, dialog_panel)
	var popup := _box(p.surface.lerp(p.foreground, 0.06), 8, 4, 4)
	popup.border_color = _alpha(p.foreground, 0.12)
	popup.set_border_width_all(1)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _box(_alpha(p.accent, 0.22), 6))
	var rule := StyleBoxLine.new()
	rule.color = _alpha(p.foreground, 0.12)
	t.set_stylebox("separator", "PopupMenu", rule)
	for key in ["font_color", "font_hover_color", "font_accelerator_color"]:
		t.set_color(key, "PopupMenu", p.foreground if key != "font_accelerator_color" else p.muted)
	t.set_color("font_disabled_color", "PopupMenu", _alpha(p.foreground, 0.4))
	t.set_color("font_separator_color", "PopupMenu", p.muted)
	var tip := _box(p.surface.lerp(p.foreground, 0.1), 6, 8, 5)
	tip.border_color = _alpha(p.foreground, 0.18)
	tip.set_border_width_all(1)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", p.foreground)
	for type_name in ["ItemList", "Tree"]:
		t.set_color("font_color", type_name, p.foreground)
		t.set_color("font_selected_color", type_name, p.foreground)
		t.set_color("font_hovered_color", type_name, p.foreground)
	t.set_color("default_color", "RichTextLabel", p.foreground)
	for type_name in ["CheckButton", "CheckBox"]:
		t.set_color("font_color", type_name, p.foreground)
		t.set_color("font_hover_color", type_name, p.foreground)
		t.set_color("font_pressed_color", type_name, p.foreground)
		t.set_color("font_hover_pressed_color", type_name, p.foreground)
		t.set_color("font_focus_color", type_name, p.foreground)
		t.set_stylebox("focus", type_name, _outline(p.accent, 10))
		var clear := _box(Color(0, 0, 0, 0), 10, 0, 6)
		var hover := _box(_alpha(p.foreground, 0.05), 10, 0, 6)
		t.set_stylebox("normal", type_name, clear)
		t.set_stylebox("pressed", type_name, clear)
		t.set_stylebox("disabled", type_name, clear)
		t.set_stylebox("hover", type_name, hover)
		t.set_stylebox("hover_pressed", type_name, hover)
	var on := _switch(p.accent, p.on_accent(), true)
	var off := _switch(_alpha(p.foreground, 0.28), p.foreground, false)
	var on_disabled := _switch(_alpha(p.accent, 0.35), _alpha(p.on_accent(), 0.6), true)
	var off_disabled := _switch(_alpha(p.foreground, 0.12), _alpha(p.foreground, 0.4), false)
	t.set_icon("checked", "CheckButton", on)
	t.set_icon("unchecked", "CheckButton", off)
	t.set_icon("checked_disabled", "CheckButton", on_disabled)
	t.set_icon("unchecked_disabled", "CheckButton", off_disabled)
	t.set_icon("checked_mirrored", "CheckButton", on)
	t.set_icon("unchecked_mirrored", "CheckButton", off)
	t.set_icon("checked_disabled_mirrored", "CheckButton", on_disabled)
	t.set_icon("unchecked_disabled_mirrored", "CheckButton", off_disabled)
	return t


## An antialiased switch: pill track with a round knob on the right when on.
static func _switch(track: Color, knob: Color, on: bool) -> ImageTexture:
	var w := 44
	var h := 24
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var radius := h / 2.0
	var knob_center := Vector2(w - radius if on else radius, radius)
	for y in h:
		for x in w:
			var pos := Vector2(x + 0.5, y + 0.5)
			var nearest := Vector2(clampf(pos.x, radius, w - radius), radius)
			var track_cover := clampf(radius - pos.distance_to(nearest) + 0.5, 0.0, 1.0)
			var knob_cover := clampf(radius - 4.0 - pos.distance_to(knob_center) + 0.5, 0.0, 1.0)
			var c := Color(track.r, track.g, track.b, track.a * track_cover)
			if knob_cover > 0.0:
				c = c.lerp(Color(knob.r, knob.g, knob.b, 1.0), knob_cover * knob.a)
			image.set_pixel(x, y, c)
	return ImageTexture.create_from_image(image)


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
