extends Page
## Lyrics for the current track. Synced lyrics follow playback until the user
## scrolls; selecting a line seeks. The offset is shared through the engine.

var _lines: Array[Dictionary] = []
var _buttons: Array[Control] = []
var _active := -1
var _follow := true
var _loading := false
var _error := ""
var _generation := 0
var _loaded_track: Dictionary = {}
var _is_active := false
var _synced := false
var _scroll_tween: Tween

var _title: Label
var _subtitle: Label
var _refresh_btn: Button
var _progress: ProgressBar
var _status: Label
var _offset_minus: Button
var _offset_plus: Button
var _offset_label: Label
var _follow_btn: Button
var _scroll: ScrollContainer
var _list: VBoxContainer
var _empty: VBoxContainer
var _empty_title: Label
var _empty_text: Label
var _empty_btn: Button
var _timer: Timer


func _init() -> void:
	super()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var head := MarginContainer.new()
	head.add_theme_constant_override("margin_left", 32)
	head.add_theme_constant_override("margin_right", 32)
	head.add_theme_constant_override("margin_top", 14)
	root.add_child(head)
	var head_row := HBoxContainer.new()
	head.add_child(head_row)
	var head_text := VBoxContainer.new()
	head_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_row.add_child(head_text)
	_title = Label.new()
	_title.text = Pages.LIST[Pages.index_of("lyrics")]["title"]
	_title.add_theme_font_size_override("font_size", 26)
	head_text.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.modulate = Color(1, 1, 1, 0.65)
	_subtitle.clip_text = true
	head_text.add_child(_subtitle)
	_refresh_btn = Icons.button("refresh", "Refresh lyrics", refresh)
	head_row.add_child(_refresh_btn)

	_progress = ProgressBar.new()
	_progress.indeterminate = true
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 3)
	_progress.visible = false
	root.add_child(_progress)

	var bar := MarginContainer.new()
	bar.add_theme_constant_override("margin_left", 40)
	bar.add_theme_constant_override("margin_right", 40)
	root.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 6)
	bar.add_child(bar_row)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 11)
	_status.modulate = Color(1, 1, 1, 0.65)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bar_row.add_child(_status)
	_offset_minus = Icons.button("remove", "Delay lyrics 250 ms", func() -> void: _change_offset(-LyricsLogic.STEP_MS), 16)
	bar_row.add_child(_offset_minus)
	_offset_label = Label.new()
	_offset_label.add_theme_font_size_override("font_size", 11)
	bar_row.add_child(_offset_label)
	_offset_plus = Icons.button("add", "Advance lyrics 250 ms", func() -> void: _change_offset(LyricsLogic.STEP_MS), 16)
	bar_row.add_child(_offset_plus)
	_follow_btn = Button.new()
	_follow_btn.text = "Follow lyrics"
	_follow_btn.toggle_mode = true
	_follow_btn.button_pressed = true
	_follow_btn.accessibility_name = "Follow lyrics"
	_follow_btn.toggled.connect(_on_follow_toggled)
	bar_row.add_child(_follow_btn)

	var body := MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.gui_input.connect(_on_scroll_input)
	_scroll.scroll_started.connect(_stop_following)
	_scroll.get_v_scroll_bar().scrolling.connect(_stop_following)
	body.add_child(_scroll)
	var pad := MarginContainer.new()
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pad.add_theme_constant_override("margin_left", 48)
	pad.add_theme_constant_override("margin_right", 48)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 70)
	_scroll.add_child(pad)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 10)
	pad.add_child(_list)

	_empty = VBoxContainer.new()
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_empty)
	_empty.add_child(Icons.label("lyrics", 48, ThemeBuilder.palette.muted))
	_empty_title = Label.new()
	_empty_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_title.add_theme_font_size_override("font_size", 18)
	_empty.add_child(_empty_title)
	_empty_text = Label.new()
	_empty_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_text.modulate = Color(1, 1, 1, 0.65)
	_empty.add_child(_empty_text)
	_empty_btn = Button.new()
	_empty_btn.text = "Try again"
	_empty_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_btn.pressed.connect(refresh)
	_empty.add_child(_empty_btn)

	_timer = Timer.new()
	_timer.wait_time = 0.25
	_timer.timeout.connect(_update_active)
	add_child(_timer)

	Store.state_changed.connect(_on_state)
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: _style_lines())
	_show_state()


func activate() -> void:
	_is_active = true
	_loaded_track = {}
	_follow = true
	_follow_btn.set_pressed_no_signal(true)
	_load()


func deactivate() -> void:
	_is_active = false
	_generation += 1
	_timer.stop()


func refresh() -> void:
	_load()


func _on_state(_state: Dictionary) -> void:
	if not _is_active:
		return
	var track := Store.track()
	if LyricsLogic.track_changed(track, _loaded_track):
		_load()
		return
	_update_controls()
	_update_active()


func _load() -> void:
	_generation += 1
	var generation := _generation
	var track := Store.track()
	_loaded_track = track.duplicate()
	_error = ""
	_lines = []
	_rebuild()
	if track.is_empty():
		_loading = false
		_show_state()
		return
	_loading = true
	_show_state()
	var result: Variant = await Backend.call_op("lyrics", {})
	if generation != _generation or not _is_active:
		return
	_loading = false
	if Backend.failed(result):
		_error = result["error"]["message"]
	elif result.get("ok") == false:
		_error = Util.text(result.get("error"), "Unable to load library.")
	else:
		_lines = Util.objects(result.get("lyrics"))
	_rebuild()
	_show_state()


func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()
	_buttons.clear()
	_active = -1
	_synced = LyricsLogic.is_synced(_lines, Store.track().get("realtime") == true)
	for i in _lines.size():
		var text := Util.text(_lines[i].get("text"), "")
		var interactive: bool = _synced and Store.state.get("seekable") == true
		var node: Control
		if interactive:
			var b := Button.new()
			b.flat = true
			b.text = text
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.accessibility_name = text
			b.tooltip_text = "Seek to this line"
			b.pressed.connect(_on_line_pressed.bind(i))
			node = b
		else:
			var l := Label.new()
			l.text = text
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			node = l
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_list.add_child(node)
		_buttons.append(node)
	_style_lines()
	_update_controls()
	if _synced and _is_active:
		_timer.start()
		_update_active()
	else:
		_timer.stop()


func _style_lines() -> void:
	var p := ThemeBuilder.palette
	for i in _buttons.size():
		var node := _buttons[i]
		var current := i == _active
		var color: Color = p.accent if current else (p.foreground if not _synced else p.muted)
		node.add_theme_font_size_override("font_size", 30 if current else 25)
		node.add_theme_color_override("font_color", color)
		node.add_theme_color_override("font_hover_color", color)
		node.add_theme_color_override("font_pressed_color", color)
		node.add_theme_color_override("font_focus_color", color)


func _update_active() -> void:
	if not _synced or _lines.is_empty():
		return
	var offset := int(Util.number(Store.state.get("lyrics_offset_ms")))
	var now := LyricsLogic.active_index(_lines, Store.position(), offset)
	if now == _active:
		return
	_active = now
	_style_lines()
	if _follow and now >= 0:
		_scroll_to_line.call_deferred(now)


func _scroll_to_line(index: int) -> void:
	if index >= _buttons.size() or not is_instance_valid(_buttons[index]):
		return
	var node := _buttons[index]
	var target := node.get_global_rect().get_center().y - _scroll.get_global_rect().position.y + _scroll.scroll_vertical - _scroll.size.y * 0.4
	if _scroll_tween != null:
		_scroll_tween.kill()
	_scroll_tween = create_tween()
	_scroll_tween.tween_property(_scroll, "scroll_vertical", maxi(0, int(target)), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _on_scroll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_stop_following()


func _stop_following() -> void:
	if _follow:
		_follow = false
		_follow_btn.set_pressed_no_signal(false)
		if _scroll_tween != null:
			_scroll_tween.kill()


func _on_follow_toggled(on: bool) -> void:
	_follow = on
	if on and _active >= 0:
		_scroll_to_line(_active)


func _on_line_pressed(index: int) -> void:
	var offset := int(Util.number(Store.state.get("lyrics_offset_ms")))
	await Store.run("seek.absolute", {"value": LyricsLogic.seek_target(_lines[index], offset)})


func _change_offset(delta: int) -> void:
	var current := int(Util.number(Store.state.get("lyrics_offset_ms")))
	await Store.run("lyrics.offset", {"value": LyricsLogic.clamp_offset(current + delta)})


func _update_controls() -> void:
	var offset := int(Util.number(Store.state.get("lyrics_offset_ms")))
	var can_offset := _synced and Store.supports("lyrics.offset")
	_offset_minus.visible = can_offset
	_offset_plus.visible = can_offset
	_offset_label.visible = can_offset
	_follow_btn.visible = _synced
	_offset_minus.disabled = offset <= -LyricsLogic.MAX_OFFSET_MS
	_offset_plus.disabled = offset >= LyricsLogic.MAX_OFFSET_MS
	_offset_label.text = LyricsLogic.offset_text(offset)
	if _synced:
		_status.text = "Synced lyrics · select a line to seek"
	elif Store.track().get("realtime") == true:
		_status.text = "Live stream · lyrics shown without timing"
	else:
		_status.text = "Lyrics"
	var track := Store.track()
	_subtitle.text = "Play a track to find its lyrics." if track.is_empty() else "%s · %s" % [Store.title(), Util.text(track.get("artist"))]
	_refresh_btn.visible = not track.is_empty()


func _show_state() -> void:
	var track := Store.track()
	_progress.visible = _loading
	var message := ""
	var heading := ""
	var retry := false
	if track.is_empty():
		heading = "Nothing is playing"
		message = "Start a track and its lyrics will show up here."
	elif not _error.is_empty():
		heading = "Lyrics unavailable"
		message = _error
		retry = true
	elif _lines.is_empty() and not _loading:
		heading = "Let the music speak"
		message = "No lyrics are available for this track."
	_empty.visible = not heading.is_empty()
	_empty_title.text = heading
	_empty_text.text = message
	_empty_btn.visible = retry
	_scroll.visible = heading.is_empty()
	_update_controls()
