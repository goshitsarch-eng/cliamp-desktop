extends Page
## Renders the engine's own visualizers (including Lua ones) as ANSI frames.
## Changes are previews until applied; restore_appearance() cancels a preview.

const DEFAULT_BG := Color("0b0d12")
const FRAME_DELAY := 0.067
const MAX_BACKOFF := 5.0

var _supported := false
var _is_active := false
var _loop_generation := 0
var _reading := false
var _backoff := 0.0

var _modes: Array[String] = []
var _themes: Array[String] = []
var _mode := ""
var _mode_index := -1
var _theme := ""
var _error := ""
var _background := DEFAULT_BG
var _foreground := Color.WHITE
var _last_frame := ""

var _original_mode := -1
var _original_theme := ""
var _changing := false
var _restoring := false
var _show_info := true
var _transport_busy := false

var _mode_picker: OptionButton
var _theme_picker: OptionButton
var _next_btn: Button
var _cancel_btn: Button
var _apply_btn: Button
var _view: AnsiView
var _error_box: VBoxContainer
var _error_label: Label
var _caption: Label
var _unsupported: Label
var _controls: Control
var _canvas_box: Control

var _fs: Window
var _fs_view: AnsiView
var _fs_caption: Label
var _fs_cancel: Button
var _fs_apply: Button
var _fs_info_btn: Button
var _fs_title: Label
var _fs_detail: Label
var _fs_toggle: Button
var _fs_volume: Label
var _fs_error: Label
var _fs_buttons: Array[Button] = []
var _fs_info_box: VBoxContainer


func _init() -> void:
	super()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title := Label.new()
	title.text = Pages.LIST[Pages.index_of("visualizer")]["title"]
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	var sub := Label.new()
	sub.text = "Original Cliamp visualizers, including your Lua extensions."
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate = Color(1, 1, 1, 0.65)
	root.add_child(sub)

	_unsupported = Label.new()
	_unsupported.text = "Visualizers require the desktop-enabled Cliamp engine."
	_unsupported.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_unsupported.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unsupported.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_unsupported.visible = false
	root.add_child(_unsupported)

	var controls := HFlowContainer.new()
	controls.add_theme_constant_override("h_separation", 14)
	controls.add_theme_constant_override("v_separation", 8)
	root.add_child(controls)
	_controls = controls
	_mode_picker = OptionButton.new()
	_mode_picker.custom_minimum_size = Vector2(240, 0)
	_mode_picker.accessibility_name = "Visualizer"
	_mode_picker.item_selected.connect(_on_mode_selected)
	controls.add_child(_mode_picker)
	_theme_picker = OptionButton.new()
	_theme_picker.custom_minimum_size = Vector2(200, 0)
	_theme_picker.accessibility_name = "Theme"
	_theme_picker.item_selected.connect(_on_theme_selected)
	controls.add_child(_theme_picker)
	_next_btn = Icons.button("skip_next", "Next visualizer", func() -> void: _select("desktop.vis", {"name": "next"}))
	controls.add_child(_next_btn)
	controls.add_child(Icons.button("fullscreen", "Enter fullscreen visualizer", _open_fullscreen))
	_cancel_btn = _text_button("Cancel preview", _cancel_preview)
	controls.add_child(_cancel_btn)
	_apply_btn = _text_button("Apply appearance", _apply_preview)
	controls.add_child(_apply_btn)

	_canvas_box = PanelContainer.new()
	_canvas_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_box.clip_contents = true
	var box := StyleBoxFlat.new()
	box.bg_color = DEFAULT_BG
	box.set_corner_radius_all(16)
	box.set_border_width_all(1)
	box.border_color = Color(1, 1, 1, 0.06)
	box.set_content_margin_all(12)
	_canvas_box.add_theme_stylebox_override("panel", box)
	root.add_child(_canvas_box)
	var stack := Control.new()
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_box.add_child(stack)
	_view = AnsiView.new()
	stack.add_child(_view)
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_error_box = VBoxContainer.new()
	_error_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_error_box.visible = false
	stack.add_child(_error_box)
	_error_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_error_label = Label.new()
	_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_box.add_child(_error_label)
	var retry := _text_button("Try again", _retry)
	retry.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_error_box.add_child(retry)

	_caption = Label.new()
	_caption.add_theme_font_size_override("font_size", 11)
	_caption.modulate = Color(1, 1, 1, 0.65)
	root.add_child(_caption)

	Store.state_changed.connect(_on_state)
	_update_chrome()


func _text_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.accessibility_name = text
	b.pressed.connect(callback)
	return b


func activate() -> void:
	_is_active = true
	_supported = Store.supports("desktop.vis.frame")
	_controls.visible = _supported
	_canvas_box.visible = _supported
	_caption.visible = _supported
	_unsupported.visible = not _supported
	if not _supported:
		return
	await _load_lists()
	_start_loop()


func deactivate() -> void:
	_is_active = false
	_loop_generation += 1
	_close_fullscreen()
	restore_appearance()


func refresh() -> void:
	_retry()


func handles_escape() -> bool:
	return _previewing()


## Cancels any uncommitted preview (visualizer and theme). Safe to call repeatedly.
func restore_appearance() -> void:
	while _restoring:
		await get_tree().create_timer(0.02).timeout
	_restoring = true
	while _changing:
		await get_tree().create_timer(0.02).timeout
	if _original_mode >= 0:
		await Backend.call_op("desktop.vis.preview", {"index": _original_mode})
		if not _original_theme.is_empty():
			await Backend.call_op("desktop.theme.preview", {"name": _original_theme})
		_original_mode = -1
		_original_theme = ""
	_restoring = false
	_update_chrome()


func _previewing() -> bool:
	return _original_mode >= 0


func _preview_supported() -> bool:
	return Store.supports("desktop.theme.preview") and Store.supports("desktop.vis.preview")


# Lists and frames

func _load_lists() -> void:
	var modes: Variant = await Backend.call_op("desktop.vis", {"name": "list"})
	var themes: Variant = await Backend.call_op("desktop.theme", {"name": "list"})
	for r in [modes, themes]:
		if Backend.failed(r):
			_error = r["error"]["message"]
			_update_chrome()
			return
	_modes = []
	for m in _array(modes.get("items")):
		_modes.append(str(m))
	_mode_index = int(Util.number(modes.get("index")))
	_themes = []
	for t in _array(themes.get("items")):
		if not str(t) in _themes:
			_themes.append(str(t))
	_error = ""
	_rebuild_pickers()
	_update_chrome()


func _rebuild_pickers() -> void:
	_mode_picker.clear()
	for i in _modes.size():
		_mode_picker.add_item(_modes[i], i)
	_theme_picker.clear()
	for t in _themes:
		_theme_picker.add_item(t)
	_sync_pickers()


func _sync_pickers() -> void:
	if _mode_index >= 0 and _mode_index < _modes.size():
		_mode_picker.select(_mode_index)
	else:
		_mode_picker.select(-1)
	if _theme.is_empty():
		# Until a frame reports it, the shared snapshot already names the theme.
		_theme = Util.text(Util.object(Store.state.get("theme")).get("name"))
	_theme_picker.select(_themes.find(_theme))


func _start_loop() -> void:
	_loop_generation += 1
	_backoff = 0.0
	var generation := _loop_generation
	while _is_active and generation == _loop_generation:
		var wait := FRAME_DELAY if _backoff == 0.0 else _backoff
		await get_tree().create_timer(wait).timeout
		if not _is_active or generation != _loop_generation:
			break
		await _read_frame()


func _target_view() -> AnsiView:
	return _fs_view if _fs != null and is_instance_valid(_fs_view) else _view


func _read_frame() -> void:
	if _reading:
		while _reading:
			await get_tree().create_timer(0.02).timeout
		return
	_reading = true
	await _fetch_frame()
	_reading = false


func _fetch_frame() -> void:
	var generation := _loop_generation
	var grid := _target_view().grid_size()
	var result: Dictionary = await Backend.read_frame(grid.x, grid.y)
	if generation != _loop_generation or not _is_active:
		return
	if Backend.failed(result):
		_error = result["error"]["message"]
		_backoff = minf(MAX_BACKOFF, maxf(0.5, _backoff * 2.0))
		_update_chrome()
		return
	_backoff = 0.0
	_error = ""
	var frame := Util.text(result.get("frame"))
	_mode = Util.text(result.get("visualizer"), _mode)
	_mode_index = int(Util.number(result.get("index")))
	var theme: Variant = result.get("theme")
	if theme is Dictionary:
		_theme = Util.text(theme.get("name"))
		_background = _parse_color(theme.get("bg"), DEFAULT_BG)
		_foreground = _parse_color(theme.get("fg"), Color.WHITE)
	else:
		_theme = Util.text(theme)
	_view.set_colors(_foreground, _background)
	_view.set_frame(frame)
	if _fs != null and is_instance_valid(_fs_view):
		_fs_view.set_colors(_foreground, _background)
		_fs_view.set_frame(frame)
	_last_frame = frame
	_update_chrome()


static func _parse_color(value: Variant, fallback: Color) -> Color:
	var hex := str(value).trim_prefix("#")
	return Color("#" + hex) if hex.length() == 6 and hex.is_valid_hex_number() else fallback


func _retry() -> void:
	if not _supported:
		return
	_backoff = 0.0
	_error = ""
	await _load_lists()
	_update_chrome()
	_start_loop()


# Selection and preview

func _on_mode_selected(position: int) -> void:
	_select("desktop.vis", {"index": _mode_picker.get_item_id(position)})


func _on_theme_selected(position: int) -> void:
	_select("desktop.theme", {"name": _theme_picker.get_item_text(position)})


func _select(operation: String, params: Dictionary) -> void:
	if _changing or _theme.is_empty() or _mode_index < 0:
		_sync_pickers()
		return
	if _preview_supported() and not _previewing():
		_original_mode = _mode_index
		_original_theme = _theme
	if operation == "desktop.vis" and params.get("name") == "next":
		params = {"index": (_mode_index + 1) % maxi(1, _modes.size())}
	_changing = true
	_update_chrome()
	var requested := operation + ".preview" if _preview_supported() else operation
	var result := await Backend.call_op(requested, params)
	if Backend.failed(result):
		Store.notify(result["error"]["message"], true)
	elif operation == "desktop.vis" and result.has("index"):
		_mode_index = int(Util.number(result.get("index")))
	await _read_frame()
	_changing = false
	_sync_pickers()
	_update_chrome()


func _cancel_preview() -> void:
	if _changing:
		return
	await restore_appearance()
	_changing = true
	await _read_frame()
	_changing = false
	_sync_pickers()
	_update_chrome()


func _apply_preview() -> void:
	if _changing or not _previewing():
		return
	_changing = true
	_update_chrome()
	var a := await Backend.call_op("desktop.vis", {"index": _mode_index})
	var b := await Backend.call_op("desktop.theme", {"name": _theme})
	for r in [a, b]:
		if Backend.failed(r):
			Store.notify(r["error"]["message"], true)
			break
	if not Backend.failed(a) and not Backend.failed(b):
		_original_mode = -1
		_original_theme = ""
	await _read_frame()
	_changing = false
	_sync_pickers()
	_update_chrome()


func _on_state(_state: Dictionary) -> void:
	if _fs != null and is_instance_valid(_fs):
		_update_fullscreen_player()


func _update_chrome() -> void:
	var busy := _changing
	_mode_picker.disabled = busy
	_theme_picker.disabled = busy
	_next_btn.disabled = busy
	_cancel_btn.visible = _previewing()
	_apply_btn.visible = _previewing()
	_cancel_btn.disabled = busy
	_apply_btn.disabled = busy
	_error_box.visible = not _error.is_empty()
	_error_label.text = _error
	_caption.text = "Start a track to bring your music to life." if _mode.is_empty() else "%s · %s" % [_mode, _theme]
	var canvas_style := _canvas_box.get_theme_stylebox("panel") as StyleBoxFlat
	if canvas_style != null:
		canvas_style.bg_color = _background
	if _fs != null and is_instance_valid(_fs):
		_fs_caption.text = "%s · %s" % [_mode, _theme]
		_fs_cancel.visible = _previewing()
		_fs_apply.visible = _previewing()
		_fs_cancel.disabled = busy
		_fs_apply.disabled = busy


# Fullscreen

func _open_fullscreen() -> void:
	if _fs != null:
		return
	_fs = Window.new()
	_fs.title = "Visualizer"
	_fs.size = Vector2i(1280, 720)
	_fs.close_requested.connect(_close_fullscreen)
	_fs.window_input.connect(_on_fs_input)
	var root := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = _background
	root.add_theme_stylebox_override("panel", bg)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fs.add_child(root)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	root.add_child(col)

	var top := _fs_bar(16, 8)
	col.add_child(top)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top.add_child(top_row)
	_fs_caption = Label.new()
	_fs_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(_fs_caption)
	_fs_cancel = _text_button("Cancel preview", _cancel_preview)
	top_row.add_child(_fs_cancel)
	_fs_apply = _text_button("Apply appearance", _apply_preview)
	top_row.add_child(_fs_apply)
	_fs_info_btn = Icons.button("visibility", "Hide track information (T)", _toggle_info)
	top_row.add_child(_fs_info_btn)
	top_row.add_child(Icons.button("graphic_eq", "Next visualizer", func() -> void: _select("desktop.vis", {"name": "next"})))
	top_row.add_child(Icons.button("fullscreen_exit", "Exit fullscreen visualizer", _close_fullscreen))

	_fs_view = AnsiView.new()
	_fs_view.set_colors(_foreground, _background)
	_fs_view.set_frame(_last_frame)
	_fs_view.custom_minimum_size = Vector2(320, 160)
	col.add_child(_fs_view)

	var bottom := _fs_bar(16, 10)
	col.add_child(bottom)
	var bcol := VBoxContainer.new()
	bcol.add_theme_constant_override("separation", 6)
	bottom.add_child(bcol)
	_fs_info_box = VBoxContainer.new()
	bcol.add_child(_fs_info_box)
	_fs_title = Label.new()
	_fs_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fs_title.clip_text = true
	_fs_title.add_theme_font_size_override("font_size", 16)
	_fs_info_box.add_child(_fs_title)
	_fs_detail = Label.new()
	_fs_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fs_detail.clip_text = true
	_fs_detail.add_theme_font_size_override("font_size", 12)
	_fs_detail.modulate = Color(1, 1, 1, 0.65)
	_fs_info_box.add_child(_fs_detail)
	var transport := HBoxContainer.new()
	transport.alignment = BoxContainer.ALIGNMENT_CENTER
	transport.add_theme_constant_override("separation", 6)
	bcol.add_child(transport)
	_fs_buttons.clear()
	_transport_button(transport, "skip_previous", "Previous track (,)", "prev")
	_transport_button(transport, "replay_5", "Seek back 5 seconds (Left)", "seek", {"value": -5})
	_fs_toggle = Button.new()
	_fs_toggle.pressed.connect(func() -> void: _transport("toggle"))
	transport.add_child(_fs_toggle)
	_transport_button(transport, "forward_5", "Seek forward 5 seconds (Right)", "seek", {"value": 5})
	_transport_button(transport, "skip_next", "Next track (.)", "next")
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(16, 0)
	transport.add_child(gap)
	_transport_button(transport, "volume_down", "Lower volume (-)", "volume.adjust", {"value": -1})
	_fs_volume = Label.new()
	_fs_volume.custom_minimum_size = Vector2(56, 0)
	_fs_volume.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transport.add_child(_fs_volume)
	_transport_button(transport, "volume_up", "Raise volume (+)", "volume.adjust", {"value": 1})
	var hint := Label.new()
	hint.text = "Space: play / pause · T: track information · V: visualizer · Esc: exit"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(1, 1, 1, 0.65)
	bcol.add_child(hint)
	_fs_error = Label.new()
	_fs_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fs_error.add_theme_color_override("font_color", ThemeBuilder.palette.error)
	_fs_error.visible = false
	bcol.add_child(_fs_error)

	Util.host(self).add_child(_fs)
	_fs.mode = Window.MODE_FULLSCREEN
	_fs.popup_centered()
	_update_fullscreen_player()
	_update_chrome()


## A full-width bar with square corners and breathing room, instead of the
## default rounded panel that has no content margins.
func _fs_bar(side: int, vertical: int) -> PanelContainer:
	var bar := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = ThemeBuilder.palette.surface
	style.content_margin_left = side
	style.content_margin_right = side
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	bar.add_theme_stylebox_override("panel", style)
	return bar


func _transport_button(parent: Control, icon: String, tip: String, operation: String, params := {}) -> void:
	var b := Icons.button(icon, tip, func() -> void: _transport(operation, params))
	b.set_meta("operation", operation)
	parent.add_child(b)
	_fs_buttons.append(b)


func _close_fullscreen() -> void:
	if _fs == null:
		return
	var w := _fs
	_fs = null
	_fs_view = null
	_fs_buttons.clear()
	w.queue_free()


func _toggle_info() -> void:
	_show_info = not _show_info
	_update_fullscreen_player()


func _update_fullscreen_player() -> void:
	var track := Store.track()
	_fs_info_box.visible = _show_info
	_fs_title.text = Util.text(track.get("title"), Util.text(track.get("path"), "Nothing playing"))
	var detail: PackedStringArray = []
	for field in ["artist", "album"]:
		if not Util.text(track.get(field)).is_empty():
			detail.append(Util.text(track.get(field)))
	_fs_detail.text = " · ".join(detail)
	_fs_detail.visible = not detail.is_empty()
	_fs_toggle.text = "Pause" if Store.is_playing() else "Play"
	_fs_toggle.disabled = _transport_busy or not Store.supports("toggle")
	_fs_toggle.accessibility_name = _fs_toggle.text
	_fs_volume.text = "%d dB" % roundi(Util.number(Store.state.get("volume")))
	Icons.set_glyph(_fs_info_btn, "visibility" if _show_info else "visibility_off")
	_fs_info_btn.tooltip_text = ("Hide" if _show_info else "Show") + " track information (T)"
	_fs_info_btn.accessibility_name = _fs_info_btn.tooltip_text
	for b in _fs_buttons:
		var op: String = b.get_meta("operation")
		b.disabled = _transport_busy or not Store.supports(op) or (op == "seek" and Store.state.get("seekable") != true)


func _transport(operation: String, params := {}) -> void:
	if _transport_busy or not Store.supports(operation):
		return
	if operation == "seek" and Store.state.get("seekable") != true:
		return
	_transport_busy = true
	if _fs != null:
		_fs_error.visible = false
		_update_fullscreen_player()
	var result := await Backend.call_op(operation, params)
	if Backend.failed(result):
		if _fs != null and is_instance_valid(_fs):
			_fs_error.text = result["error"]["message"]
			_fs_error.visible = true
		Store.notify(result["error"]["message"], true)
	else:
		await Store.refresh_state()
	_transport_busy = false
	if _fs != null and is_instance_valid(_fs):
		_update_fullscreen_player()


func _on_fs_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var handled := true
	var jump: bool = event.ctrl_pressed or event.meta_pressed
	match event.keycode:
		KEY_ESCAPE:
			_close_fullscreen()
		KEY_SPACE:
			_transport("toggle")
		KEY_COMMA:
			_transport("prev")
		KEY_PERIOD:
			_transport("next")
		KEY_LEFT:
			if jump:
				_transport("prev")
			else:
				_transport("seek", {"value": -5})
		KEY_RIGHT:
			if jump:
				_transport("next")
			else:
				_transport("seek", {"value": 5})
		KEY_MINUS, KEY_KP_SUBTRACT:
			_transport("volume.adjust", {"value": -1})
		KEY_EQUAL, KEY_KP_ADD:
			_transport("volume.adjust", {"value": 1})
		KEY_T:
			_toggle_info()
		KEY_V:
			_select("desktop.vis", {"name": "next"})
		_:
			handled = false
	if handled and _fs != null:
		_fs.set_input_as_handled()


static func _array(value: Variant) -> Array:
	return value if value is Array else []
