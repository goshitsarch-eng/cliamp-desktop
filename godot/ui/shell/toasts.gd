class_name Toasts
extends MarginContainer
## Floating notices from Store.notice. Normal ones last 4s, errors 8s, and each
## has a close button. At most three show at once.

const MAX_VISIBLE := 3
const ERROR_BG := Color("8c1d18")
const ERROR_FG := Color("ffdad6")

var _stack: VBoxContainer


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack = VBoxContainer.new()
	_stack.alignment = BoxContainer.ALIGNMENT_END
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stack.add_theme_constant_override("separation", 8)
	add_child(_stack)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Store.notice.connect(show_notice)


## Distance between the window bottom and the toasts, so they clear the player bar.
func set_bottom_inset(pixels: float) -> void:
	add_theme_constant_override("margin_bottom", int(pixels) + 16)


func show_notice(message: String, is_error := false) -> void:
	var p := ThemeBuilder.palette
	while _stack.get_child_count() >= MAX_VISIBLE:
		var oldest := _stack.get_child(0)
		_stack.remove_child(oldest)
		oldest.queue_free()
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ERROR_BG if is_error else p.foreground
	style.set_corner_radius_all(8)
	style.content_margin_left = 16
	style.content_margin_right = 6
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.shadow_color = Color(0, 0, 0, 0.35)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var fg := ERROR_FG if is_error else p.background
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var max_w := minf(520.0, maxf(160.0, size.x - 80.0))
	label.custom_minimum_size = Vector2(max_w, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", fg)
	if message.length() > 220 or message.count("\n") > 3:
		var sc := ScrollContainer.new()
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(max_w, minf(120.0, maxf(64.0, size.y * 0.2)))
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(label)
		row.add_child(sc)
	else:
		row.add_child(label)
	var close := Icons.button("close", "Dismiss notice", func() -> void: _dismiss(center), 16)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		close.add_theme_color_override(key, fg)
	row.add_child(close)
	center.add_child(panel)
	center.set_meta("serial", Time.get_ticks_usec())
	_stack.add_child(center)
	var timer := get_tree().create_timer(8.0 if is_error else 4.0)
	timer.timeout.connect(func() -> void: _dismiss(center))


func _dismiss(toast: Node) -> void:
	if is_instance_valid(toast) and toast.get_parent() == _stack:
		_stack.remove_child(toast)
		toast.queue_free()
