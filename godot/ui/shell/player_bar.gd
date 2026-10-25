class_name PlayerBar
extends PanelContainer
## Transport bar: now playing, controls, seek, volume and playback options.
## Layout follows window width like the Flutter bar: narrow under 780px, the
## speed/download/lyrics buttons above 1030px.

signal lyrics_requested

const SPEEDS: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

var _width := 1280.0
var _narrow := false
var _seek_preview := -1.0
var _volume_preview := -1.0
var _seek_dragging := false
var _volume_dragging := false
var _updating := false

var _artwork: Artwork
var _title: Label
var _artist: Label
var _favorite: Button
var _shuffle: Button
var _prev: Button
var _play: Button
var _next: Button
var _repeat: Button
var _speed: MenuButton
var _download: Button
var _lyrics: Button
var _volume_icon: Button
var _volume: HSlider
var _more: MenuButton
var _seek_row: HBoxContainer
var _seek_time: Button
var _seek: HSlider
var _duration: Label
var _top: HBoxContainer
var _center: VBoxContainer
var _outer: VBoxContainer
var _extras: Array[Control] = []
var _wide_only: Array[Control] = []
var _ticker: Timer
var _buttons: Array[Button] = []


func _init() -> void:
	_outer = VBoxContainer.new()
	_outer.add_theme_constant_override("separation", 0)
	add_child(_outer)
	_top = HBoxContainer.new()
	_top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_top.add_theme_constant_override("separation", 6)
	_outer.add_child(_top)

	_artwork = Artwork.new()
	_artwork.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_top.add_child(_artwork)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(7, 0)
	_top.add_child(gap)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	info.add_theme_constant_override("separation", 3)
	info.custom_minimum_size = Vector2(60, 0)
	_top.add_child(info)
	_title = Label.new()
	_title.clip_text = true
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.add_theme_font_size_override("font_size", 13)
	info.add_child(_title)
	_artist = Label.new()
	_artist.clip_text = true
	_artist.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_artist.add_theme_font_size_override("font_size", 11)
	info.add_child(_artist)

	_favorite = _icon_button("favorite_border", "Favorite current track", func() -> void: ShellActions.favorite(Store.track()), 18)
	_top.add_child(_favorite)
	_wide_only.append(_favorite)

	_center = VBoxContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_center.alignment = BoxContainer.ALIGNMENT_CENTER
	_center.add_theme_constant_override("separation", 0)
	_top.add_child(_center)
	var transport := HBoxContainer.new()
	transport.alignment = BoxContainer.ALIGNMENT_CENTER
	transport.add_theme_constant_override("separation", 4)
	_center.add_child(transport)
	_shuffle = _icon_button("shuffle", "Shuffle", func() -> void: Store.run("shuffle", {"name": "toggle"}), 18)
	transport.add_child(_shuffle)
	_wide_only.append(_shuffle)
	_prev = _icon_button("skip_previous", "Previous track", func() -> void: Store.run("prev"), 25)
	transport.add_child(_prev)
	_play = Icons.button("play_arrow", "Play", func() -> void: Store.run("toggle"), 28)
	_play.custom_minimum_size = Vector2(43, 43)
	_play.flat = false
	transport.add_child(_play)
	_next = _icon_button("skip_next", "Next track", func() -> void: Store.run("next"), 25)
	transport.add_child(_next)
	_repeat = _icon_button("repeat", "Repeat: off", func() -> void: Store.run("repeat", {"name": "cycle"}), 18)
	transport.add_child(_repeat)
	_wide_only.append(_repeat)

	_seek_row = HBoxContainer.new()
	_seek_row.add_theme_constant_override("separation", 6)
	_seek_time = Button.new()
	_seek_time.flat = true
	_seek_time.tooltip_text = "Jump to time"
	_seek_time.accessibility_name = "Jump to time"
	_seek_time.custom_minimum_size = Vector2(46, 0)
	_seek_time.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_seek_time.add_theme_font_size_override("font_size", 11)
	_seek_time.pressed.connect(func() -> void: ShellActions.jump_to_time(self))
	_seek_row.add_child(_seek_time)
	_seek = HSlider.new()
	_seek.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_seek.custom_minimum_size = Vector2(60, 20)
	_seek.step = 0.0
	_seek.min_value = 0.0
	_seek.max_value = 1.0
	_seek.accessibility_name = "Seek"
	_seek.drag_started.connect(func() -> void: _seek_dragging = true)
	_seek.drag_ended.connect(_on_seek_drag_ended)
	_seek.value_changed.connect(_on_seek_changed)
	_seek_row.add_child(_seek)
	_duration = Label.new()
	_duration.custom_minimum_size = Vector2(46, 0)
	_duration.add_theme_font_size_override("font_size", 11)
	_seek_row.add_child(_duration)
	_center.add_child(_seek_row)

	_speed = MenuButton.new()
	_speed.flat = true
	_speed.tooltip_text = "Playback speed"
	_speed.accessibility_name = "Playback speed"
	_speed.add_theme_font_size_override("font_size", 12)
	_speed.about_to_popup.connect(_fill_speed)
	_speed.get_popup().id_pressed.connect(func(id: int) -> void: Store.run("speed", {"value": SPEEDS[id]}))
	_top.add_child(_speed)
	_extras.append(_speed)
	_download = _icon_button("download", "Download current track", func() -> void: ShellActions.download(), 18)
	_top.add_child(_download)
	_extras.append(_download)
	_lyrics = _icon_button("lyrics", "Show lyrics", func() -> void: lyrics_requested.emit(), 18)
	_top.add_child(_lyrics)
	_extras.append(_lyrics)

	_volume_icon = _icon_button("volume_up", "Minimum volume", _on_volume_icon, 20)
	_top.add_child(_volume_icon)
	_wide_only.append(_volume_icon)
	_volume = HSlider.new()
	_volume.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_volume.custom_minimum_size = Vector2(95, 20)
	_volume.step = 0.0
	_volume.min_value = -50.0
	_volume.max_value = 6.0
	_volume.accessibility_name = "Volume"
	_volume.drag_started.connect(func() -> void: _volume_dragging = true)
	_volume.drag_ended.connect(_on_volume_drag_ended)
	_volume.value_changed.connect(_on_volume_changed)
	_top.add_child(_volume)
	_wide_only.append(_volume)

	_more = MenuButton.new()
	_more.flat = true
	_more.text = Icons.glyph("more_vert")
	_more.add_theme_font_override("font", Icons.font())
	_more.add_theme_font_size_override("font_size", 18)
	_more.tooltip_text = "Playback options"
	_more.accessibility_name = "Playback options"
	_more.custom_minimum_size = Vector2(36, 36)
	_more.about_to_popup.connect(_fill_more)
	_more.get_popup().id_pressed.connect(_on_more)
	_top.add_child(_more)

	_ticker = Timer.new()
	_ticker.wait_time = 0.2
	_ticker.timeout.connect(_refresh_position)
	add_child(_ticker)


func _ready() -> void:
	Store.state_changed.connect(func(_s: Dictionary) -> void: _refresh())
	Store.connection_changed.connect(_refresh)
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: _restyle())
	_restyle()
	set_width(_width)
	_refresh()


func set_width(width: float) -> void:
	_width = width
	_narrow = width < 780.0
	custom_minimum_size.y = 148 if _narrow else 112
	_restyle_panel()
	_artwork.custom_minimum_size = Vector2(46, 46) if _narrow else Vector2(58, 58)
	_title.get_parent().size_flags_stretch_ratio = 3.0 if _narrow else 4.0
	_center.size_flags_stretch_ratio = 5.0 if _narrow else 7.0
	for c in _wide_only:
		c.visible = not _narrow
	for c in _extras:
		c.visible = width > 1030.0
	_volume.custom_minimum_size.x = 95 if width > 1100.0 else 64
	if _narrow:
		if _seek_row.get_parent() != _outer:
			_seek_row.reparent(_outer, false)
	elif _seek_row.get_parent() != _center:
		_seek_row.reparent(_center, false)


func _icon_button(icon_name: String, tooltip: String, callback: Callable, size: int) -> Button:
	var b := Icons.button(icon_name, tooltip, callback, size)
	_buttons.append(b)
	return b


func _tint(b: Button, color: Color) -> void:
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, color)
	b.add_theme_color_override("font_disabled_color", Color(color, 0.35))


func _restyle_panel() -> void:
	var p := ThemeBuilder.palette
	var panel := StyleBoxFlat.new()
	panel.bg_color = p.surface
	panel.border_color = Color(p.foreground, 0.08)
	panel.border_width_top = 1
	panel.set_corner_radius_all(0)
	panel.content_margin_top = 12
	panel.content_margin_bottom = 10
	panel.content_margin_left = 15 if _narrow else 26
	panel.content_margin_right = 15 if _narrow else 26
	add_theme_stylebox_override("panel", panel)


func _restyle() -> void:
	var p := ThemeBuilder.palette
	_restyle_panel()
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(p.foreground, 0.18)
	pressed.set_corner_radius_all(10)
	for b in _buttons:
		b.add_theme_stylebox_override("pressed", pressed)
	var round_normal := StyleBoxFlat.new()
	round_normal.bg_color = p.accent
	round_normal.set_corner_radius_all(22)
	var round_hover := round_normal.duplicate() as StyleBoxFlat
	round_hover.bg_color = p.accent.lightened(0.12)
	var round_off := round_normal.duplicate() as StyleBoxFlat
	round_off.bg_color = Color(p.foreground, 0.12)
	_play.add_theme_stylebox_override("normal", round_normal)
	_play.add_theme_stylebox_override("hover", round_hover)
	_play.add_theme_stylebox_override("pressed", round_hover)
	_play.add_theme_stylebox_override("disabled", round_off)
	_play.add_theme_stylebox_override("focus", ShellSidebar.outline(p.foreground, 22))
	_tint(_play, p.on_accent())
	_play.add_theme_color_override("font_disabled_color", p.muted)
	_title.add_theme_color_override("font_color", p.foreground)
	_artist.add_theme_color_override("font_color", p.muted)
	_duration.add_theme_color_override("font_color", p.muted)
	_tint(_seek_time, p.muted)
	_tint(_speed, p.muted)
	_tint(_more, p.muted)
	SliderStyle.apply(_seek, 4)
	SliderStyle.apply(_volume, 5)
	_refresh()


func _refresh() -> void:
	var p := ThemeBuilder.palette
	var s := Store.state
	var track := Store.track()
	var connected := Store.connected
	_artwork.set_track(track)
	_title.text = "Ready when you are" if track.is_empty() else Store.title()
	_title.tooltip_text = _title.text
	var fallback := "Add music to get started"
	if not track.is_empty():
		fallback = "Live stream" if track.get("realtime") == true else "Unknown artist"
	_artist.text = Util.text(track.get("artist"), fallback)

	var bookmarked: bool = track.get("bookmark") == true
	Icons.set_glyph(_favorite, "favorite" if bookmarked else "favorite_border")
	_favorite.tooltip_text = "Remove favorite" if bookmarked else "Favorite current track"
	_favorite.accessibility_name = _favorite.tooltip_text
	_favorite.disabled = track.is_empty()
	_tint(_favorite, p.accent if bookmarked else p.muted)

	for b in [_shuffle, _prev, _next, _repeat, _volume_icon, _download, _lyrics]:
		_tint(b, p.muted)
		b.disabled = not connected
	_download.disabled = track.is_empty() or not connected
	_lyrics.disabled = false
	_tint(_shuffle, p.accent if s.get("shuffle") == true else p.muted)
	var repeat_text := Util.text(s.get("repeat"), "off")
	var repeat_on := s.get("repeat") != null and repeat_text.to_lower() != "off"
	Icons.set_glyph(_repeat, "repeat_one" if repeat_text.to_lower() == "one" else "repeat")
	_repeat.tooltip_text = "Repeat: %s" % repeat_text
	_repeat.accessibility_name = _repeat.tooltip_text
	_tint(_repeat, p.accent if repeat_on else p.muted)

	var playing := Store.is_playing()
	Icons.set_glyph(_play, "pause" if playing else "play_arrow")
	_play.tooltip_text = "Pause" if playing else "Play"
	_play.accessibility_name = _play.tooltip_text
	_play.disabled = not connected

	var speed := Util.number(s.get("speed"), 1.0)
	_speed.text = ("%d" % int(speed) if fmod(speed, 1.0) == 0.0 else "%.2f" % speed) + "x"
	_speed.disabled = not connected
	_more.disabled = not connected

	var floor_db := ShellActions.volume_floor()
	_updating = true
	_volume.min_value = floor_db
	_volume.max_value = 6.0
	if not _volume_dragging:
		_volume.set_value_no_signal(clampf(Util.number(s.get("volume")), floor_db, 6.0))
	_updating = false
	_volume.editable = connected
	var shown := _volume.value if _volume_dragging else clampf(Util.number(s.get("volume")), floor_db, 6.0)
	var at_floor := shown <= floor_db
	Icons.set_glyph(_volume_icon, "volume_off" if at_floor else "volume_up")
	_volume_icon.tooltip_text = "Restore volume" if at_floor else "Minimum volume"
	_volume_icon.accessibility_name = _volume_icon.tooltip_text
	_volume.accessibility_description = "%d decibels" % roundi(shown)

	var seekable: bool = s.get("seekable") == true
	_seek.editable = connected and seekable
	_seek_time.disabled = not (connected and seekable)
	_duration.text = "LIVE" if track.get("realtime") == true else Util.duration(s.get("duration"))
	if playing and seekable:
		if _ticker.is_stopped():
			_ticker.start()
	else:
		_ticker.stop()
	_refresh_position()


func _refresh_position() -> void:
	var duration := Util.number(Store.state.get("duration"))
	var limit := maxf(duration, 1.0)
	var position := _seek_preview if _seek_preview >= 0.0 else Store.position()
	_updating = true
	_seek.max_value = limit
	if not _seek_dragging:
		_seek.set_value_no_signal(clampf(position, 0.0, limit))
	_updating = false
	_seek_time.text = Util.duration(_seek.value if _seek_dragging else position)
	_seek.accessibility_description = Util.duration(position)


func _on_seek_changed(value: float) -> void:
	if _updating:
		return
	if _seek_dragging:
		_seek_preview = value
		_seek_time.text = Util.duration(value)
	else:
		# Keyboard adjustment: no drag, so commit directly.
		_commit_seek(value)


func _on_seek_drag_ended(changed: bool) -> void:
	_seek_dragging = false
	if changed:
		_commit_seek(_seek.value)
	else:
		_seek_preview = -1.0


func _commit_seek(value: float) -> void:
	_seek_preview = value
	await Store.run("seek.absolute", {"value": value})
	if is_instance_valid(self):
		_seek_preview = -1.0
		_refresh_position()


func _on_volume_changed(value: float) -> void:
	if _updating:
		return
	_volume_preview = value
	if not _volume_dragging:
		_commit_volume(value)


func _on_volume_drag_ended(changed: bool) -> void:
	_volume_dragging = false
	if changed:
		_commit_volume(_volume.value)


func _commit_volume(value: float) -> void:
	await Store.run("volume", {"value": value})
	if is_instance_valid(self):
		_volume_preview = -1.0
		_refresh()


func _on_volume_icon() -> void:
	var floor_db := ShellActions.volume_floor()
	var current := clampf(Util.number(Store.state.get("volume")), floor_db, 6.0)
	Store.run("volume", {"value": 0 if current <= floor_db else floor_db})


func _fill_speed() -> void:
	var popup := _speed.get_popup()
	popup.clear()
	var current := Util.number(Store.state.get("speed"), 1.0)
	for i in SPEEDS.size():
		popup.add_radio_check_item("%sx" % str(SPEEDS[i]), i)
		popup.set_item_checked(i, is_equal_approx(SPEEDS[i], current))


func _fill_more() -> void:
	var popup := _more.get_popup()
	popup.clear()
	var track := Store.track()
	if _narrow:
		popup.add_item("Remove favorite" if track.get("bookmark") == true else "Favorite track", 0)
		popup.set_item_disabled(popup.get_item_index(0), track.is_empty())
	popup.add_item("Stop playback", 1)
	popup.add_item("Download track", 2)
	popup.add_item("Adjust volume...", 3)
	popup.add_item("Switch to stereo" if Store.state.get("mono") == true else "Switch to mono", 4)
	popup.add_item("Toggle shuffle", 5)
	popup.add_item("Repeat: %s" % Util.text(Store.state.get("repeat"), "off"), 6)


func _on_more(id: int) -> void:
	match id:
		0: ShellActions.favorite(Store.track())
		1: Store.run("stop")
		2: ShellActions.download()
		3: ShellActions.adjust_volume(self)
		4: Store.run("mono", {"name": "toggle"})
		5: Store.run("shuffle", {"name": "toggle"})
		6: Store.run("repeat", {"name": "cycle"})
