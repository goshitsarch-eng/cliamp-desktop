class_name ShellEmptyState
extends CenterContainer
## Centered icon, title, description and an optional action button.

var _icon_box: PanelContainer
var _icon: Label
var _title: Label
var _description: Label
var _action: Button


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	column.custom_minimum_size = Vector2(440, 0)
	add_child(column)
	_icon_box = PanelContainer.new()
	_icon_box.custom_minimum_size = Vector2(72, 72)
	_icon_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_icon = Icons.label("graphic_eq", 30)
	_icon_box.add_child(_icon)
	column.add_child(_icon_box)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 11)
	column.add_child(gap)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_size_override("font_size", 19)
	column.add_child(_title)
	_description = Label.new()
	_description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description.add_theme_font_size_override("font_size", 12)
	column.add_child(_description)
	var holder := CenterContainer.new()
	_action = Button.new()
	_action.visible = false
	holder.add_child(_action)
	column.add_child(holder)
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: _restyle())
	_restyle()


func configure(icon_name: String, title: String, description: String, action_label := "", action := Callable()) -> void:
	_icon.text = Icons.glyph(icon_name)
	_title.text = title
	_description.text = description
	_action.visible = action.is_valid() and not action_label.is_empty()
	_action.text = action_label
	_action.accessibility_name = action_label
	for connection in _action.pressed.get_connections():
		_action.pressed.disconnect(connection["callable"])
	if action.is_valid():
		_action.pressed.connect(action)


func _restyle() -> void:
	var p := ThemeBuilder.palette
	var box := StyleBoxFlat.new()
	box.bg_color = Color(p.accent, 0.06)
	box.border_color = Color(p.accent, 0.09)
	box.set_border_width_all(1)
	box.set_corner_radius_all(24)
	_icon_box.add_theme_stylebox_override("panel", box)
	_icon.add_theme_color_override("font_color", p.accent)
	_description.add_theme_color_override("font_color", p.muted)
