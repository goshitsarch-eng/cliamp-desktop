class_name ShellSidebar
extends PanelContainer
## Navigation rail. 218px wide with labels, 76px with icons only.

signal page_selected(page_id: String)

const WIDE := 218
const NARROW := 76

var compact := false
var _current := "queue"
var _items: Dictionary = {}
var _rows: Dictionary = {}
var _brand_label: Label
var _eyebrow: Label
var _status_dot: Control
var _status_label: Label
var _status_icon: Label
var _queue_count: Label
var _scroll: ScrollContainer
var _list: VBoxContainer
var _brand_mark: PanelContainer


func _init() -> void:
	custom_minimum_size = Vector2(WIDE, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	var brand_row := HBoxContainer.new()
	brand_row.add_theme_constant_override("separation", 11)
	var brand_margin := MarginContainer.new()
	brand_margin.add_theme_constant_override("margin_top", 14)
	brand_margin.add_theme_constant_override("margin_bottom", 10)
	brand_margin.add_theme_constant_override("margin_left", 18)
	brand_margin.add_theme_constant_override("margin_right", 12)
	brand_margin.add_child(brand_row)
	column.add_child(brand_margin)
	_brand_mark = PanelContainer.new()
	_brand_mark.custom_minimum_size = Vector2(32, 32)
	_brand_mark.add_child(Icons.label("graphic_eq", 20))
	brand_row.add_child(_brand_mark)
	_brand_label = Label.new()
	_brand_label.text = "cliamp"
	_brand_label.add_theme_font_size_override("font_size", 22)
	_brand_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_brand_label.clip_text = true
	brand_row.add_child(_brand_label)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	var scroll_margin := MarginContainer.new()
	scroll_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_margin.add_theme_constant_override("margin_left", 12)
	scroll_margin.add_theme_constant_override("margin_right", 12)
	_scroll.add_child(scroll_margin)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 2)
	scroll_margin.add_child(_list)
	_eyebrow = Label.new()
	_eyebrow.text = "YOUR MUSIC"
	_eyebrow.add_theme_font_size_override("font_size", 9)
	var eyebrow_margin := MarginContainer.new()
	eyebrow_margin.add_theme_constant_override("margin_left", 12)
	eyebrow_margin.add_theme_constant_override("margin_bottom", 4)
	eyebrow_margin.add_child(_eyebrow)
	_list.add_child(eyebrow_margin)
	for page: Dictionary in Pages.LIST:
		if page["id"] == "lyrics":
			_list.add_child(HSeparator.new())
		_list.add_child(_make_item(page))

	var footer := MarginContainer.new()
	footer.add_theme_constant_override("margin_left", 12)
	footer.add_theme_constant_override("margin_right", 12)
	footer.add_theme_constant_override("margin_top", 8)
	footer.add_theme_constant_override("margin_bottom", 10)
	column.add_child(footer)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 9)
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_child(status)
	_status_icon = Icons.label("cloud_off", 19)
	status.add_child(_status_icon)
	_status_dot = Control.new()
	_status_dot.custom_minimum_size = Vector2(7, 7)
	_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_dot.draw.connect(_draw_dot)
	status.add_child(_status_dot)
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.clip_text = true
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(_status_label)


func _ready() -> void:
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: _restyle())
	Store.connection_changed.connect(_restyle)
	Store.state_changed.connect(func(_s: Dictionary) -> void: _update_count())
	_restyle()
	_apply_compact()


func _draw_dot() -> void:
	var p := ThemeBuilder.palette
	_status_dot.draw_circle(Vector2(3.5, 3.5), 3.5, p.accent if Store.connected else p.muted)


func set_compact(value: bool) -> void:
	if value == compact:
		return
	compact = value
	_apply_compact()


func set_current(page_id: String) -> void:
	_current = page_id
	_restyle()
	var item: Control = _items.get(page_id)
	if item != null and is_inside_tree():
		_scroll.call_deferred("ensure_control_visible", item)


func _make_item(page: Dictionary) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 36)
	button.focus_mode = Control.FOCUS_ALL
	button.accessibility_name = page["label"]
	button.pressed.connect(func() -> void: page_selected.emit(page["id"]))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 13)
	var icon := Icons.label(page["icon"], 20)
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(24, 0)
	row.add_child(icon)
	var text := Label.new()
	text.name = "Text"
	text.text = page["label"]
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.clip_text = true
	row.add_child(text)
	if page["id"] == "queue":
		_queue_count = Label.new()
		_queue_count.add_theme_font_size_override("font_size", 11)
		_queue_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(_queue_count)
	button.add_child(row)
	_items[page["id"]] = button
	_rows[page["id"]] = row
	return button


func _apply_compact() -> void:
	custom_minimum_size.x = NARROW if compact else WIDE
	_brand_label.visible = not compact
	_eyebrow.visible = not compact
	_status_label.visible = not compact
	_status_dot.visible = not compact
	_status_icon.visible = compact
	for page: Dictionary in Pages.LIST:
		var row: HBoxContainer = _rows[page["id"]]
		var button: Button = _items[page["id"]]
		row.get_node("Text").visible = not compact
		row.alignment = BoxContainer.ALIGNMENT_CENTER if compact else BoxContainer.ALIGNMENT_BEGIN
		row.offset_left = 0 if compact else 12
		row.offset_right = 0 if compact else -12
		button.tooltip_text = page["label"] if compact else ""
	_update_count()


func _update_count() -> void:
	if _queue_count == null:
		return
	var total := Util.number(Store.state.get("total"))
	_queue_count.visible = total > 0 and not compact
	_queue_count.text = str(int(total))


static func outline(color: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = color
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	return s


func _restyle() -> void:
	var p := ThemeBuilder.palette
	var panel := StyleBoxFlat.new()
	panel.bg_color = p.sidebar
	panel.border_color = Color(p.foreground, 0.05)
	panel.border_width_right = 1
	panel.set_corner_radius_all(0)
	add_theme_stylebox_override("panel", panel)
	var mark := StyleBoxFlat.new()
	mark.bg_color = p.accent
	mark.set_corner_radius_all(10)
	_brand_mark.add_theme_stylebox_override("panel", mark)
	(_brand_mark.get_child(0) as Label).add_theme_color_override("font_color", p.on_accent())
	_eyebrow.add_theme_color_override("font_color", p.muted)
	_status_label.add_theme_color_override("font_color", p.muted)
	_status_label.text = "Engine connected" if Store.connected else "Engine offline"
	_status_icon.text = Icons.glyph("cloud_done" if Store.connected else "cloud_off")
	_status_icon.add_theme_color_override("font_color", p.accent if Store.connected else p.muted)
	_status_dot.queue_redraw()
	if _queue_count != null:
		_queue_count.add_theme_color_override("font_color", p.muted)
	for page: Dictionary in Pages.LIST:
		var button: Button = _items[page["id"]]
		var selected: bool = page["id"] == _current
		var color: Color = p.accent if selected else p.muted
		var row: HBoxContainer = _rows[page["id"]]
		(row.get_node("Icon") as Label).add_theme_color_override("font_color", color)
		(row.get_node("Text") as Label).add_theme_color_override("font_color", color)
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(p.accent, 0.10) if selected else Color(0, 0, 0, 0)
		normal.set_corner_radius_all(9)
		var hover := normal.duplicate() as StyleBoxFlat
		hover.bg_color = Color(p.accent, 0.14) if selected else Color(p.foreground, 0.06)
		button.add_theme_stylebox_override("normal", normal)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
		button.add_theme_stylebox_override("focus", outline(p.accent, 9))
