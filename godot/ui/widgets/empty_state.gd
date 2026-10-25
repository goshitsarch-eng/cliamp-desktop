class_name EmptyState
extends CenterContainer
## Centered icon, title, description and optional action, as the library's
## empty and error views. Drops the icon when the area is short.

var _icon_box: PanelContainer
var _title: Label
var _description: Label
var _button: Button
var _action: Callable


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_icon_box = PanelContainer.new()
	_icon_box.custom_minimum_size = Vector2(72, 72)
	_icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_icon_box)
	_title = UiKit.label("", 19, null, true)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_description = UiKit.label("", 12)
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.custom_minimum_size = Vector2(440, 0)
	col.add_child(_description)
	_button = Button.new()
	_button.pressed.connect(func() -> void:
		if _action.is_valid():
			_action.call())
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_button)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		var compact := size.y < 230.0
		_icon_box.visible = not compact
		_title.add_theme_font_size_override("font_size", 16 if compact else 19)


func show_message(icon_name: String, title: String, description: String, action: Callable = Callable(), action_label := "", action_icon := "add") -> void:
	var p := ThemeBuilder.palette
	UiKit.clear(_icon_box)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(p.accent.r, p.accent.g, p.accent.b, 0.06)
	box.border_color = Color(p.accent.r, p.accent.g, p.accent.b, 0.09)
	box.set_border_width_all(1)
	box.set_corner_radius_all(24)
	_icon_box.add_theme_stylebox_override("panel", box)
	_icon_box.add_child(Icons.label(icon_name, 30, p.accent))
	_title.text = title
	_title.add_theme_color_override("font_color", p.foreground)
	_description.text = description
	_description.add_theme_color_override("font_color", p.muted)
	_action = action
	_button.visible = action.is_valid()
	_button.text = Icons.glyph(action_icon) + "  " + (action_label if not action_label.is_empty() else "Continue")
	_button.add_theme_font_override("font", UiKit.mixed_font())
	_button.accessibility_name = action_label if not action_label.is_empty() else "Continue"
