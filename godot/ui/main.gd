extends Control
## Application shell: sidebar, top bar, page host, banners, player bar, toasts,
## keyboard shortcuts and the command palette. Pages are created lazily from
## Pages.LIST and own their headers.

const COMPACT_WIDTH := 860.0

var _sidebar: ShellSidebar
var _topbar: ShellTopbar
var _library: HBoxContainer
var _progress: ProgressBar
var _progress_gap: Control
var _connection_banner: Control
var _connection_label: Label
var _stream_banner: Control
var _stream_label: Label
var _page_host: MarginContainer
var _connection_view: ShellEmptyState
var _compact_view: CenterContainer
var _compact_art: Artwork
var _compact_title: Label
var _player: PlayerBar
var _toasts: Toasts
var _pages: Dictionary = {}
var _active: Page
var _page_active := false
var _compact_player := false
var _was_compact := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	Store.connection_changed.connect(_on_connection_changed)
	Store.pending_changed.connect(func(_n: int) -> void: _refresh_chrome())
	Store.state_changed.connect(func(_s: Dictionary) -> void:
		_refresh_chrome()
		_refresh_compact())
	Store.navigate_requested.connect(show_page)
	Store.focus_search_requested.connect(_focus_search)
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: _restyle())
	resized.connect(_on_resized)
	Prefs.before_close.append(_restore_appearance)
	_restyle()
	_on_resized()
	_show_page_node(Store.current_page)
	_refresh_chrome()
	Store.start()


func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_library = HBoxContainer.new()
	_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library.add_theme_constant_override("separation", 0)
	root.add_child(_library)
	_sidebar = ShellSidebar.new()
	_sidebar.page_selected.connect(show_page)
	_library.add_child(_sidebar)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 0)
	_library.add_child(content)
	_topbar = ShellTopbar.new()
	_topbar.add_requested.connect(add_source)
	_topbar.palette_requested.connect(open_command_palette)
	_topbar.jobs_requested.connect(func() -> void: JobsPanel.open(self))
	content.add_child(_topbar)

	_progress = ProgressBar.new()
	_progress.indeterminate = true
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 2)
	content.add_child(_progress)
	_progress_gap = Control.new()
	_progress_gap.custom_minimum_size = Vector2(0, 2)
	content.add_child(_progress_gap)

	_connection_banner = _make_banner(true)
	_connection_label = _connection_banner.get_meta("label")
	content.add_child(_connection_banner)
	_stream_banner = _make_banner(false)
	_stream_label = _stream_banner.get_meta("label")
	content.add_child(_stream_banner)

	_page_host = MarginContainer.new()
	_page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.clip_contents = true
	content.add_child(_page_host)
	_connection_view = ShellEmptyState.new()
	_connection_view.visible = false
	content.add_child(_connection_view)

	_compact_view = CenterContainer.new()
	_compact_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_compact_view.visible = false
	root.add_child(_compact_view)
	var compact_column := VBoxContainer.new()
	compact_column.add_theme_constant_override("separation", 12)
	compact_column.custom_minimum_size = Vector2(320, 0)
	_compact_view.add_child(compact_column)
	_compact_art = Artwork.new(true)
	_compact_art.custom_minimum_size = Vector2(130, 130)
	_compact_art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	compact_column.add_child(_compact_art)
	_compact_title = Label.new()
	_compact_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compact_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compact_title.max_lines_visible = 2
	_compact_title.add_theme_font_size_override("font_size", 22)
	compact_column.add_child(_compact_title)
	var open_library := Button.new()
	open_library.text = "Open library"
	open_library.accessibility_name = "Open library"
	open_library.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	open_library.pressed.connect(func() -> void: set_compact_player(false))
	compact_column.add_child(open_library)

	_player = PlayerBar.new()
	_player.lyrics_requested.connect(func() -> void: show_page("lyrics"))
	_player.resized.connect(func() -> void:
		if _toasts != null:
			_toasts.set_bottom_inset(_player.size.y))
	root.add_child(_player)

	_toasts = Toasts.new()
	add_child(_toasts)
	_toasts.set_bottom_inset(_player.custom_minimum_size.y)


func _make_banner(retry: bool) -> Control:
	var panel := PanelContainer.new()
	panel.visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	row.add_child(Icons.label("info_outline", 18, Toasts.ERROR_FG))
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.max_lines_visible = 3
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Toasts.ERROR_FG)
	row.add_child(label)
	if retry:
		var b := Button.new()
		b.text = "Retry"
		b.flat = true
		b.accessibility_name = "Retry connection"
		b.add_theme_color_override("font_color", Toasts.ERROR_FG)
		b.add_theme_color_override("font_hover_color", Toasts.ERROR_FG)
		b.pressed.connect(func() -> void: Store.start())
		row.add_child(b)
	var style := StyleBoxFlat.new()
	style.bg_color = Toasts.ERROR_BG
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	panel.add_theme_stylebox_override("panel", style)
	panel.set_meta("label", label)
	return panel


func _restyle() -> void:
	var p := ThemeBuilder.palette
	RenderingServer.set_default_clear_color(p.background)
	var fill := StyleBoxFlat.new()
	fill.bg_color = p.accent
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0)
	_progress.add_theme_stylebox_override("fill", fill)
	_progress.add_theme_stylebox_override("background", back)
	_compact_title.add_theme_color_override("font_color", p.foreground)


func _on_resized() -> void:
	var compact := size.x < COMPACT_WIDTH
	_sidebar.set_compact(compact)
	_topbar.set_compact(compact)
	_topbar.set_width(size.x)
	_player.set_width(size.x)
	_was_compact = compact


# Pages

func show_page(page_id: String) -> void:
	if Pages.index_of(page_id) < 0:
		return
	if _compact_player:
		set_compact_player(false)
	_show_page_node(page_id)


func _show_page_node(page_id: String) -> void:
	if _active != null and _page_active:
		_active.deactivate()
	_page_active = false
	Store.current_page = page_id
	if _topbar.has_text() or not Store.filter.is_empty():
		_topbar.clear_search()
	_sidebar.set_current(page_id)
	_topbar.update_for_page(page_id)
	var page := _page_for(page_id)
	for id: String in _pages:
		(_pages[id] as Page).visible = _pages[id] == page
	_active = page
	if Store.connected:
		_page_active = true
		page.activate()


func _page_for(page_id: String) -> Page:
	if _pages.has(page_id):
		return _pages[page_id]
	var entry: Dictionary = Pages.LIST[Pages.index_of(page_id)]
	var page: Page = null
	var path: String = entry["script"]
	if ResourceLoader.exists(path):
		var script: Variant = load(path)
		if script is GDScript:
			var instance: Variant = (script as GDScript).new()
			if instance is Page:
				page = instance
			elif instance is Object and not (instance is Node):
				(instance as Object).free()
	if page == null:
		page = _placeholder(entry)
	page.name = "Page_" + page_id
	_pages[page_id] = page
	_page_host.add_child(page)
	return page


func _placeholder(entry: Dictionary) -> Page:
	var page := Page.new()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = "%s is not available yet." % entry["title"]
	label.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
	center.add_child(label)
	page.add_child(center)
	return page


func _restore_appearance() -> void:
	for id: String in _pages:
		var page: Object = _pages[id]
		if page.has_method("restore_appearance"):
			await page.call("restore_appearance")


# Connection and chrome

func _on_connection_changed() -> void:
	_refresh_chrome()
	if Store.connected and not _page_active and _active != null:
		_page_active = true
		_active.activate()
	elif not Store.connected and _page_active:
		_page_active = false
		_active.deactivate()


func _refresh_chrome() -> void:
	var busy := Store.pending > 0 or Store.connecting
	_progress.visible = busy
	_progress_gap.visible = not busy
	var error := Store.connection_error
	_connection_banner.visible = not error.is_empty()
	_connection_label.text = error
	var stream_error := Util.text(Store.state.get("stream_error"))
	_stream_banner.visible = not stream_error.is_empty()
	_stream_label.text = stream_error
	_page_host.visible = Store.connected
	_connection_view.visible = not Store.connected
	if Store.connecting:
		_connection_view.configure("graphic_eq", "Opening your music space", "Starting the Cliamp audio engine...")
	else:
		_connection_view.configure("power_off", "Let's reconnect your player",
			"The audio engine could not be reached. Check that the Cliamp engine is installed beside the app, then retry.",
			"Retry connection", Callable(Store, "start"))


func _refresh_compact() -> void:
	if not _compact_player:
		return
	_compact_art.set_track(Store.track())
	_compact_title.text = Store.title()


func set_compact_player(value: bool) -> void:
	_compact_player = value
	_library.visible = not value
	_compact_view.visible = value
	_refresh_compact()


func _focus_search() -> void:
	if _compact_player:
		set_compact_player(false)
	_topbar.focus_search()


# Actions

func add_source() -> void:
	AddSourceDialog.run(self)


func open_command_palette() -> void:
	var actions: Array = [
		["Play / pause", "Space", func() -> void: Store.run("toggle")],
		["Previous track", "Ctrl+Left", func() -> void: Store.run("prev")],
		["Next track", "Ctrl+Right", func() -> void: Store.run("next")],
		["Seek back 10 seconds", "Alt+Left", func() -> void: Store.run("seek", {"value": -10})],
		["Jump to time", "Ctrl+J", func() -> void: ShellActions.jump_to_time(self)],
		["Seek forward 10 seconds", "Alt+Right", func() -> void: Store.run("seek", {"value": 10})],
		["Volume up", "Ctrl+Up", func() -> void: Store.run("volume.adjust", {"value": 1})],
		["Volume down", "Ctrl+Down", func() -> void: Store.run("volume.adjust", {"value": -1})],
		["Add files, folder, or URL", "Ctrl+O", add_source],
		["Search this view", "Ctrl+F", _focus_search],
		["Download playing track", "Ctrl+S", ShellActions.download],
		["Undo playlist / queue edit", "Ctrl+Z", _undo],
		["Compact player", "Ctrl+X", func() -> void: set_compact_player(not _compact_player)],
		["Toggle shuffle", "", func() -> void: Store.run("shuffle", {"name": "toggle"})],
		["Cycle repeat", "", func() -> void: Store.run("repeat", {"name": "cycle"})],
	]
	for binding in Store.plugin_bindings:
		var key := Util.text(binding.get("key"))
		actions.append(["%s: %s" % [Util.text(binding.get("plugin")), Util.text(binding.get("description"), key)], key,
			func() -> void: Store.run("plugin.key", {"name": key})])
	for page: Dictionary in Pages.LIST:
		var id: String = page["id"]
		actions.append(["Open %s" % page["label"], "", func() -> void: show_page(id)])
	var chosen: Variant = await CommandPalette.open(self, actions)
	if chosen is Callable:
		(chosen as Callable).call()


func _undo() -> void:
	if _active != null and _page_active:
		_active.undo()


# Keyboard

func _text_focused() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


func _shortcut_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var command := (key.ctrl_pressed or key.meta_pressed) and not key.alt_pressed and not key.shift_pressed
	var alt := key.alt_pressed and not key.ctrl_pressed and not key.meta_pressed and not key.shift_pressed
	var code := key.keycode
	# These work even while a text field has focus.
	if command and code == KEY_O:
		add_source()
	elif command and code == KEY_F:
		Store.focus_search_requested.emit()
	elif (command and code == KEY_K) or (code == KEY_F1 and not key.ctrl_pressed and not key.alt_pressed):
		open_command_palette()
	elif _text_focused():
		return
	elif command and code == KEY_RIGHT:
		Store.run("next")
	elif command and code == KEY_LEFT:
		Store.run("prev")
	elif alt and code == KEY_RIGHT:
		Store.run("seek", {"value": 10})
	elif alt and code == KEY_LEFT:
		Store.run("seek", {"value": -10})
	elif command and code == KEY_UP:
		Store.run("volume.adjust", {"value": 1})
	elif command and code == KEY_DOWN:
		Store.run("volume.adjust", {"value": -1})
	elif command and code == KEY_Z:
		_undo()
	elif command and code == KEY_R:
		if _active != null and _page_active:
			_active.refresh()
	elif command and code == KEY_S:
		ShellActions.download()
	elif command and code == KEY_J:
		ShellActions.jump_to_time(self)
	elif command and code == KEY_X:
		set_compact_player(not _compact_player)
	elif not _plugin_key(key):
		return
	get_viewport().set_input_as_handled()


## Space plays or pauses, Escape clears the search and leaves compact mode.
## Both run after focused controls had their turn, so buttons and pages win.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var plain := not (key.ctrl_pressed or key.alt_pressed or key.meta_pressed or key.shift_pressed)
	if key.keycode == KEY_SPACE and plain:
		if not _text_focused():
			Store.run("toggle")
			get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and plain:
		if _active != null and _page_active and _active.handles_escape():
			return
		if _topbar.has_text() or not Store.filter.is_empty():
			_topbar.clear_search()
		set_compact_player(false)
		get_viewport().set_input_as_handled()


## Runs a plugin binding for the pressed combination. Returns true when handled.
func _plugin_key(key: InputEventKey) -> bool:
	if Store.plugin_bindings.is_empty():
		return false
	if key.keycode in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
		return false
	var parts: Array[String] = []
	if key.ctrl_pressed:
		parts.append("ctrl")
	if key.alt_pressed:
		parts.append("alt")
	if key.meta_pressed:
		parts.append("super")
	if key.shift_pressed:
		parts.append("shift")
	parts.append(OS.get_keycode_string(key.keycode).to_lower())
	var combo := "+".join(parts)
	for binding in Store.plugin_bindings:
		if binding.get("key") == combo:
			Store.run("plugin.key", {"name": combo})
			return true
	return false
