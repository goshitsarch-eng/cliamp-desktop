class_name TrackRow
extends PanelContainer
## One row of the track list: select box, play or playing marker, artwork,
## title / artist / listening marker, album or play date, favorite, duration
## and the action menu. Reused by VirtualList, so apply() only sets values.

signal play_requested(position: int)
signal mark_requested(position: int)
signal favorite_requested(position: int)
signal action_requested(action: String, position: int)

## Callable(position: int) -> Array of [action_id, label] pairs for the menu.
var menu_provider: Callable

var _position := -1
var _disabled := false
var _selecting := false
var _style := StyleBoxFlat.new()
var _check := CheckBox.new()
var _eq := Icons.label("graphic_eq", 17)
var _play := Icons.button("play_arrow", "Play", Callable(), 18)
var _art := Artwork.new()
var _title := Label.new()
var _artist := Label.new()
var _listening := Label.new()
var _album := Label.new()
var _album_box: Control
var _favorite := Icons.button("favorite_border", "Add favorite", Callable(), 17)
var _duration := Label.new()
var _menu := MenuButton.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_style.set_corner_radius_all(10)
	_style.content_margin_left = 13
	_style.content_margin_right = 8
	_style.content_margin_top = 8
	_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", _style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	_check.focus_mode = Control.FOCUS_ALL
	_check.toggled.connect(func(_on: bool) -> void: mark_requested.emit(_position))
	row.add_child(_check)

	var slot := CenterContainer.new()
	slot.custom_minimum_size = Vector2(40, 0)
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	_eq.custom_minimum_size = Vector2(24, 24)
	slot.add_child(_eq)
	_play.pressed.connect(func() -> void: play_requested.emit(_position))
	slot.add_child(_play)
	row.add_child(slot)

	_art.custom_minimum_size = Vector2(42, 42)
	_art.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_art.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_art)
	row.add_child(_spacer(13))

	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_stretch_ratio = 5.0
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	_title.add_theme_font_size_override("font_size", 13)
	_artist.add_theme_font_size_override("font_size", 11)
	_listening.add_theme_font_size_override("font_size", 10)
	for l: Label in [_title, _artist, _listening, _album, _duration]:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		l.mouse_filter = Control.MOUSE_FILTER_PASS
	text.add_child(_title)
	text.add_child(_artist)
	text.add_child(_listening)
	row.add_child(text)

	var album_box := MarginContainer.new()
	album_box.add_theme_constant_override("margin_left", 20)
	album_box.add_theme_constant_override("margin_right", 20)
	album_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	album_box.size_flags_stretch_ratio = 3.0
	album_box.mouse_filter = Control.MOUSE_FILTER_PASS
	_album.add_theme_font_size_override("font_size", 12)
	_album.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	album_box.add_child(_album)
	row.add_child(album_box)
	_album_box = album_box

	_favorite.pressed.connect(func() -> void: favorite_requested.emit(_position))
	row.add_child(_favorite)

	_duration.custom_minimum_size = Vector2(50, 0)
	_duration.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_duration.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_duration.add_theme_font_size_override("font_size", 11)
	row.add_child(_duration)

	_menu.flat = true
	_menu.text = Icons.glyph("more_horiz")
	_menu.add_theme_font_override("font", Icons.font())
	_menu.add_theme_font_size_override("font_size", 19)
	_menu.custom_minimum_size = Vector2(38, 31)
	_menu.tooltip_text = "Track actions"
	_menu.accessibility_name = "Track actions"
	_menu.focus_mode = Control.FOCUS_ALL
	var popup := _menu.get_popup()
	popup.about_to_popup.connect(_fill_menu)
	popup.id_pressed.connect(func(id: int) -> void:
		action_requested.emit(str(popup.get_item_metadata(popup.get_item_index(id))), _position))
	row.add_child(_menu)


func _spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _fill_menu() -> void:
	var popup := _menu.get_popup()
	popup.clear()
	if not menu_provider.is_valid():
		return
	var entries: Array = menu_provider.call(_position)
	for i in entries.size():
		popup.add_item(entries[i][1], i)
		popup.set_item_metadata(i, entries[i][0])


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.double_click:
		if not _disabled and not _selecting:
			play_requested.emit(_position)
		elif _selecting:
			mark_requested.emit(_position)
	elif _selecting:
		mark_requested.emit(_position)


## `d`: position, track_title, artist, album, listening, duration, bookmark,
## current, playing, disabled, marked, selecting, odd, show_album, connected,
## art (track Dictionary), label (accessibility name).
func apply(d: Dictionary) -> void:
	var p := ThemeBuilder.palette
	_position = d["position"]
	_disabled = d["disabled"]
	_selecting = d["selecting"]
	var current: bool = d["current"]
	if d["marked"]:
		_style.bg_color = Color(p.secondary.r, p.secondary.g, p.secondary.b, 0.14)
	elif current:
		_style.bg_color = Color(p.accent.r, p.accent.g, p.accent.b, 0.065)
	elif d["odd"]:
		_style.bg_color = Color(p.foreground.r, p.foreground.g, p.foreground.b, 0.016)
	else:
		_style.bg_color = Color(0, 0, 0, 0)
	var label: String = d["label"]
	_check.visible = _selecting
	_check.set_pressed_no_signal(d["marked"])
	_check.accessibility_name = "Select " + label
	var playing_here: bool = current and d["playing"]
	_eq.visible = playing_here
	_eq.add_theme_color_override("font_color", p.accent)
	_play.visible = not playing_here
	_play.disabled = _disabled
	_play.tooltip_text = "Play " + label
	_play.accessibility_name = "Play " + label
	UiKit.tint(_play, p.muted)
	_art.set_track(d["art"])
	_title.text = d["track_title"]
	_title.add_theme_color_override("font_color", p.muted if _disabled else (p.accent if current else p.foreground))
	_artist.text = d["artist"]
	_artist.add_theme_color_override("font_color", p.muted)
	var listening: String = d["listening"]
	_listening.visible = not listening.is_empty()
	_listening.text = listening
	_listening.add_theme_color_override("font_color", p.accent)
	_album_box.visible = d["show_album"]
	_album.text = d["album"]
	_album.add_theme_color_override("font_color", p.muted)
	var bookmark: bool = d["bookmark"]
	Icons.set_glyph(_favorite, "favorite" if bookmark else "favorite_border")
	_favorite.tooltip_text = "Remove favorite" if bookmark else "Add favorite"
	_favorite.accessibility_name = _favorite.tooltip_text
	UiKit.tint(_favorite, p.accent if bookmark else p.muted)
	_duration.text = d["duration"]
	_duration.add_theme_color_override("font_color", p.muted)
	_menu.disabled = not d["connected"]
	UiKit.tint(_menu, p.muted)
	accessibility_name = label
