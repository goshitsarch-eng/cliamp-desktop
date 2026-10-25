class_name CollectionCard
extends PanelContainer
## A playlist, album or artist tile: artwork, name, subtitle and (for playlists)
## an actions menu. Built once per load; filtering only toggles visibility.

signal activated(item: Dictionary)
signal action_requested(action: String, item: Dictionary)

var item: Dictionary = {}
var _menu: MenuButton
## Callable(item: Dictionary) -> Array of [action_id, label].
var menu_provider: Callable


func _init(data: Dictionary, kind: String, subtitle: String, connected: bool, has_menu: bool, provider: Callable) -> void:
	item = data
	menu_provider = provider
	var p := ThemeBuilder.palette
	custom_minimum_size = Vector2(0, 222)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var box := StyleBoxFlat.new()
	box.bg_color = p.surface
	box.set_corner_radius_all(14)
	box.set_content_margin_all(13)
	add_theme_stylebox_override("panel", box)
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = p.accent
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(14)
	add_theme_stylebox_override("focus", focus)
	var name_text := Util.text(data.get("name"), "Untitled")
	accessibility_name = name_text
	tooltip_text = name_text

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(col)
	var icon := "person_outline" if kind == "artists" else ("album" if kind == "albums" else ("favorite" if data.get("id") == "Favorites" else "queue_music"))
	var art := Artwork.new(true, icon)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_PASS
	art.set_track({"title": data.get("name")})
	col.add_child(art)
	col.add_child(_gap(11))
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_PASS
	var title := UiKit.label(name_text, 14, p.foreground, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.mouse_filter = Control.MOUSE_FILTER_PASS
	head.add_child(title)
	if has_menu:
		_menu = MenuButton.new()
		_menu.flat = true
		_menu.text = Icons.glyph("more_horiz")
		_menu.add_theme_font_override("font", Icons.font())
		_menu.add_theme_font_size_override("font_size", 19)
		_menu.custom_minimum_size = Vector2(30, 24)
		_menu.tooltip_text = "Playlist actions"
		_menu.accessibility_name = "Playlist actions for " + name_text
		_menu.disabled = not connected
		UiKit.tint(_menu, p.muted)
		var popup := _menu.get_popup()
		popup.about_to_popup.connect(_fill_menu)
		popup.id_pressed.connect(func(id: int) -> void:
			action_requested.emit(str(popup.get_item_metadata(popup.get_item_index(id))), item))
		head.add_child(_menu)
	col.add_child(head)
	var sub := UiKit.label(subtitle, 11, p.muted)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	sub.mouse_filter = Control.MOUSE_FILTER_PASS
	col.add_child(sub)


func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _fill_menu() -> void:
	var popup := _menu.get_popup()
	popup.clear()
	if not menu_provider.is_valid():
		return
	var entries: Array = menu_provider.call(item)
	for i in entries.size():
		popup.add_item(entries[i][1], i)
		popup.set_item_metadata(i, entries[i][0])


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		activated.emit(item)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		activated.emit(item)
		accept_event()
