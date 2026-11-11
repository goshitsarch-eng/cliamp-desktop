class_name LibraryPage
extends Page
## The generic library page of the Flutter app (_content / _fetch / _navigate):
## Queue, Play next, Playlists, Favorites and History share this class and
## differ only in `page_id`. Subclasses set page_id in _init().
##
## Loads are guarded by a generation counter. The track list is a VirtualList
## whose rows are built once and rebound on scroll, load, filter and state
## changes, never per frame.

const ICONS := {
	"queue": "queue_music", "next": "playlist_play", "playlists": "library_music",
	"favorites": "favorite_border", "history": "history",
}
const SUBTITLES := {
	"queue": "Your next favorite moment starts here.",
	"next": "A little intention for what comes after this.",
	"favorites": "The tracks you always come back to.",
	"history": "Pick up where the music took you.",
	"playlists": "Soundtracks for every part of your day.",
}
const PAGE_LIMIT := 200
const WIDE_ART := 980.0
const WIDE_COLUMNS := 1040.0
const WIDE_SPECTRUM := 1200.0

var page_id := "queue"

# Load state, as in the Dart _LibraryState.
var _items: Array[Dictionary] = []
var _sorts: Array[Dictionary] = []
var _listening: Dictionary = {}
var _kind := "tracks"
var _request := "queue.list"
var _params: Dictionary = {}
var _total := 0
var _list_revision: Variant = null
var _catalog_offset := 0
var _catalog_more := false
var _load_generation := 0
var _loading := false
var _load_error := ""
var _collection := ""
var _collection_title := ""
var _caps: Dictionary = {}
var _caps_provider := ""
var _playlist_list_undo: Dictionary = {}

# Selection and filtering.
var _marked: Dictionary = {}
var _selecting := false
var _anchor := -1
var _visible := PackedInt32Array()

var _active := false
var _last_revision: Variant = null
var _state_sig := ""
var _compact := false
var _wide_columns := false

# Nodes.
var _header_margin: MarginContainer
var _header: LibraryHeader
var _provider_bar: ScrollContainer
var _provider_row: HBoxContainer
var _list_bar: HBoxContainer
var _list_title: Label
var _list_total: Label
var _list_actions: HBoxContainer
var _selection_bar: ScrollContainer
var _selection_row: HBoxContainer
var _progress: ProgressBar
var _stack: MarginContainer
var _track_view: VBoxContainer
var _column_head: MarginContainer
var _album_head: Label
var _list: VirtualList
var _grid_scroll: ScrollContainer
var _grid: GridContainer
var _cards: Array[CollectionCard] = []
var _empty: EmptyState
var _more: Button
var _more_wrap: Control


func _ready() -> void:
	_build()
	Store.state_changed.connect(_on_state)
	Store.filter_changed.connect(func(_t: String) -> void: _apply_filter())
	Store.lists_stale.connect(_on_lists_stale)
	Store.connection_changed.connect(_on_connection)
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void:
		if _active:
			_render()
			_list.rebind())
	resized.connect(_on_resized)
	_grid_scroll.resized.connect(_update_columns)
	_update_layout_flags()


# ---------------------------------------------------------------- Page API

func activate() -> void:
	_active = true
	_reset()
	_last_revision = Store.playlist_revision()
	_state_sig = _signature()
	_update_layout_flags()
	_render()
	if Store.connected:
		await _load_initial()


func deactivate() -> void:
	_active = false
	_load_generation += 1
	_loading = false


func refresh() -> void:
	await _refresh_list()


func undo() -> void:
	await _undo()


func handles_escape() -> bool:
	return _selecting


## Leaves select mode and clears the selection.
func finish_selecting() -> void:
	_selecting = false
	_marked.clear()
	_anchor = -1
	_render_selection()
	_list.rebind()


func _unhandled_key_input(event: InputEvent) -> void:
	if _active and _selecting and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		finish_selecting()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- Navigation

func _reset() -> void:
	_marked.clear()
	_selecting = false
	_anchor = -1
	Store.provider_seed = {}
	Store.provider_action = ""
	_collection = ""
	_collection_title = ""
	_load_error = ""
	_items = []
	_total = 0
	_list_revision = null
	_catalog_more = false
	_sorts = []
	_listening = {}
	_loading = false
	_load_generation += 1
	match page_id:
		"playlists":
			_kind = "playlists"
		"history":
			_kind = "history"
		_:
			_kind = "tracks"
	_rebuild_data()


func _load_initial() -> void:
	match page_id:
		"queue":
			await _fetch("queue.list", {})
		"next":
			await _fetch("playnext.list", {})
		"playlists":
			Store.provider = "local"
			await _fetch("provider.playlists", {"provider": Store.provider}, "playlists")
		"favorites":
			Store.provider = "local"
			_collection = "Favorites"
			await _fetch("provider.tracks", {"provider": "local", "playlist": "Favorites"})
		"history":
			await _fetch("history", {}, "history")


func _is_live() -> bool:
	return page_id == "queue" or page_id == "next"


# ---------------------------------------------------------------- Loading

func _fetch(operation: String, params: Dictionary, kind := "tracks", append := false, quiet := false) -> void:
	_load_generation += 1
	var generation := _load_generation
	var requested: Variant = Store.state.get("playlist_revision")
	requested = int(requested) if requested is int or requested is float else null
	var prev_marked_entries: Array = []
	if quiet and not append and _selecting:
		var sorted_marked := _marked.keys()
		sorted_marked.sort()
		for p: int in sorted_marked:
			if p >= 0 and p < _items.size():
				var mp := Util.text(LibraryLogic.track_of(_items[p], _kind).get("path"))
				if not mp.is_empty():
					prev_marked_entries.append([p, mp])
	var target_count := maxi(PAGE_LIMIT, _items.size()) if quiet and not append else PAGE_LIMIT
	_request = operation
	_params = params
	_kind = kind
	_loading = true
	_load_error = ""
	if not append and not quiet:
		_items = []
	if not append:
		_marked.clear()
		_anchor = -1
	if page_id == "playlists" and not append:
		_caps = {}
		_caps_provider = ""
	if not quiet and not append:
		_rebuild_data()
	_render()
	var request := params.duplicate()
	if kind != "lyrics" and kind != "devices":
		request["limit"] = PAGE_LIMIT
	if append:
		request["offset"] = _catalog_offset if operation == "provider.catalog" else _items.size()
	var data := await Backend.call_op(operation, request)
	if generation != _load_generation:
		return
	if Backend.failed(data):
		_fail_load(data["error"]["message"])
		return
	if data.get("ok") == false:
		_fail_load(Util.text(data.get("error"), "Unable to load library."))
		return
	var items := Util.objects(data.get(kind))
	var listening := Util.object(data.get("listening")).duplicate()
	var total_count := int(Util.number(data.get("total"), items.size()))
	if quiet and not append and operation != "provider.catalog" and target_count > PAGE_LIMIT:
		var goal := mini(target_count, total_count)
		while items.size() < goal:
			var extra_req := params.duplicate()
			extra_req["limit"] = PAGE_LIMIT
			extra_req["offset"] = items.size()
			var extra := await Backend.call_op(operation, extra_req)
			if generation != _load_generation:
				return
			if Backend.failed(extra) or extra.get("ok") == false:
				break
			var page := Util.objects(extra.get(kind))
			if page.is_empty():
				break
			items.append_array(page)
			listening.merge(Util.object(extra.get("listening")), true)
	if (kind == "tracks" or kind == "history") and not items.is_empty() and Store.supports("provider.playback_state"):
		var tracks: Array = []
		for item in items.slice(0, 1000):
			tracks.append(Util.object(item.get("track")) if kind == "history" else item)
		var status := await Backend.call_op("provider.playback_state", {"tracks": tracks})
		if generation != _load_generation:
			return
		# Old engines or unavailable providers can still show playable tracks.
		if not Backend.failed(status):
			listening.merge(Util.object(status.get("listening")), true)
	var capabilities: Variant = null
	var capability_provider := Util.text(params.get("provider"))
	if page_id == "playlists" and not capability_provider.is_empty() and Store.supports("playlist.capabilities"):
		var caps := await Backend.call_op("playlist.capabilities", {"provider": capability_provider})
		if generation != _load_generation:
			return
		capabilities = {} if Backend.failed(caps) else caps
	if capabilities != null:
		_caps = capabilities
		_caps_provider = capability_provider
	if append:
		var merged := _listening.duplicate()
		merged.merge(listening, true)
		_listening = merged
	else:
		_listening = listening
	if append and operation != "provider.catalog":
		_items.append_array(items)
	else:
		_items = items
		if not prev_marked_entries.is_empty() and _selecting:
			var unmatched: Array[String] = []
			for entry: Array in prev_marked_entries:
				var old_pos: int = entry[0]
				var mp: String = entry[1]
				if old_pos < _items.size() and not _marked.has(old_pos) \
						and Util.text(LibraryLogic.track_of(_items[old_pos], _kind).get("path")) == mp:
					_marked[old_pos] = true
				else:
					unmatched.append(mp)
			for mp in unmatched:
				for idx in _items.size():
					if not _marked.has(idx) and Util.text(LibraryLogic.track_of(_items[idx], _kind).get("path")) == mp:
						_marked[idx] = true
						break
	_total = int(Util.number(data.get("total"), _items.size()))
	_sorts = Util.objects(data.get("sorts"))
	if operation == "queue.list" or operation == "playnext.list":
		_list_revision = requested
	if operation == "provider.catalog":
		_catalog_offset = (_catalog_offset if append else 0) + _total
		_catalog_more = _total > 0
		_total = _items.size()
	else:
		_catalog_more = false
	_loading = false
	_rebuild_data()
	_render()
	if (operation == "queue.list" or operation == "playnext.list") and _active:
		var latest: Variant = Store.state.get("playlist_revision")
		latest = int(latest) if latest is int or latest is float else null
		if latest != _list_revision:
			_last_revision = latest
			_fetch.call_deferred(_request, _params, "tracks", false, true)


func _fail_load(message: String) -> void:
	_load_error = message
	_loading = false
	_render()


func _refresh_list() -> void:
	await _fetch(_request, _params, _kind, false, true)


func _on_state(state: Dictionary) -> void:
	if not _active:
		return
	var revision: Variant = state.get("playlist_revision")
	var changed: bool = revision != _last_revision
	_last_revision = revision
	if changed and _is_live() and not _loading:
		_fetch(_request, _params, "tracks", false, true)
	var sig := _signature()
	if sig != _state_sig:
		_state_sig = sig
		_update_header()
		_list.rebind()


func _signature() -> String:
	var t := Store.track()
	return "%s|%s|%s|%s|%s|%d" % [t.get("path"), t.get("title"), t.get("artist"), Store.is_playing(), Store.state.get("total"), roundi(Util.number(Store.state.get("duration")))]


func _on_lists_stale() -> void:
	if _active and _is_live():
		_refresh_list()


func _on_connection() -> void:
	if _active and Store.connected and _items.is_empty() and not _loading and _load_error.is_empty():
		_load_initial()


# ---------------------------------------------------------------- Capability helpers

func _can_playlist(action: String) -> bool:
	return Store.connected and _caps_provider == Store.provider and _caps.get(action) == true


func _can_remove_saved(multiple := false) -> bool:
	return page_id == "playlists" and not _collection.is_empty() \
		and not LibraryLogic.SYSTEM_PLAYLISTS.has(_collection) \
		and _can_playlist("remove_many" if multiple else "remove")


func _revision() -> Dictionary:
	return Store.revision(_list_revision if _is_live() else null)


func _run(operation: String, params := {}, message := "") -> Variant:
	return await Store.run(operation, params, message)


func _page_label() -> String:
	return Pages.LIST[Pages.index_of(page_id)]["label"]


# ---------------------------------------------------------------- UI construction

func _build() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_header_margin = MarginContainer.new()
	_header = LibraryHeader.new()
	_header_margin.add_child(_header)
	root.add_child(_header_margin)

	_provider_bar = _hscroll()
	_provider_row = HBoxContainer.new()
	_provider_row.add_theme_constant_override("separation", 7)
	_provider_bar.add_child(_provider_row)
	root.add_child(_margined(_provider_bar, 32, 0, 32, 12))

	_list_bar = HBoxContainer.new()
	_list_bar.add_theme_constant_override("separation", 9)
	_list_title = UiKit.label("", 15, null, true)
	_list_bar.add_child(_list_title)
	_list_total = UiKit.label("", 12)
	_list_bar.add_child(_list_total)
	var actions_scroll := _hscroll()
	actions_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_actions = HBoxContainer.new()
	_list_actions.alignment = BoxContainer.ALIGNMENT_END
	_list_actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_scroll.add_child(_list_actions)
	_list_bar.add_child(actions_scroll)
	root.add_child(_margined(_list_bar, 16, 0, 12, 6))

	_selection_bar = _hscroll()
	_selection_row = HBoxContainer.new()
	_selection_bar.add_child(_margined(_selection_row, 0, 0, 0, 6))
	var selection_margin := _margined(_selection_bar, 32, 0, 24, 8)
	selection_margin.visible = false
	_selection_bar.set_meta("wrapper", selection_margin)
	root.add_child(selection_margin)

	var slot := Control.new()
	slot.custom_minimum_size = Vector2(0, 2)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.indeterminate = true
	_progress.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_progress.visible = false
	slot.add_child(_progress)
	root.add_child(slot)

	_stack = MarginContainer.new()
	_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_stack)

	_track_view = VBoxContainer.new()
	_track_view.add_theme_constant_override("separation", 0)
	_track_view.visible = false
	_column_head = MarginContainer.new()
	_column_head.add_theme_constant_override("margin_left", 37)
	_column_head.add_theme_constant_override("margin_right", 32)
	_column_head.add_theme_constant_override("margin_top", 4)
	_column_head.add_theme_constant_override("margin_bottom", 11)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	var hash_label := UiKit.label("#", 11)
	hash_label.custom_minimum_size = Vector2(95, 0)
	head.add_child(hash_label)
	var title_label := UiKit.label("TITLE", 10)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_stretch_ratio = 5.0
	head.add_child(title_label)
	_album_head = UiKit.label("ALBUM", 10)
	_album_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_album_head.size_flags_stretch_ratio = 3.0
	_album_head.visible = false
	head.add_child(_album_head)
	var clock := Icons.label("schedule", 14)
	clock.custom_minimum_size = Vector2(121, 0)
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(clock)
	_column_head.add_child(head)
	_column_head.set_meta("labels", [hash_label, title_label, _album_head, clock])
	_track_view.add_child(_column_head)
	_list = VirtualList.new()
	_list.make_row = _make_row
	_list.bind_row = _bind_row
	_track_view.add_child(_list)
	_stack.add_child(_track_view)

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_grid_scroll.visible = false
	var grid_margin := MarginContainer.new()
	grid_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		grid_margin.add_theme_constant_override("margin_" + side, 32)
	grid_margin.add_theme_constant_override("margin_bottom", 24)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_margin.add_child(_grid)
	_grid_scroll.add_child(grid_margin)
	_stack.add_child(_grid_scroll)

	_empty = EmptyState.new()
	_empty.visible = false
	_stack.add_child(_empty)

	_more = Button.new()
	_more.flat = true
	_more.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_more.pressed.connect(func() -> void: _fetch(_request, _params, _kind, true))
	_more_wrap = _margined(_more, 0, 6, 0, 6)
	_more_wrap.visible = false
	root.add_child(_more_wrap)


func _hscroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	return s


func _margined(child: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.add_child(child)
	return m


func _tool(icon_name: String, tooltip: String, callback: Callable, active := false) -> Button:
	var b := Icons.button(icon_name, tooltip, callback, 21)
	UiKit.tint(b, ThemeBuilder.palette.accent if active else ThemeBuilder.palette.muted)
	return b


# ---------------------------------------------------------------- Rendering

func _on_resized() -> void:
	if _update_layout_flags() and _active:
		_update_header()
		_list.rebind()


## Recomputes the width and height dependent layout; true when something changed.
func _update_layout_flags() -> bool:
	var compact := size.y > 0.0 and size.y < 340.0
	var wide := _width() > WIDE_COLUMNS
	var changed := compact != _compact or wide != _wide_columns
	_compact = compact
	_wide_columns = wide
	_album_head.visible = wide
	return changed


func _width() -> float:
	return get_viewport_rect().size.x


func _render() -> void:
	_update_header()
	_render_provider_bar()
	_render_list_bar()
	_render_selection()
	_progress.visible = _loading
	_progress.indeterminate = _loading
	_update_body()
	var catalog := _catalog_more
	_more_wrap.visible = _items.size() < _total or catalog
	_more.disabled = _loading
	_more.text = "Load more from catalog" if catalog else "Load more · %d of %d" % [_items.size(), _total]
	_more.accessibility_name = _more.text
	var p := ThemeBuilder.palette
	for l: Label in _column_head.get_meta("labels"):
		l.add_theme_color_override("font_color", p.muted)


func _update_header() -> void:
	var queue := page_id == "queue"
	var width := _width()
	var playing := Store.is_playing()
	var count := LibraryLogic.count_line(queue, _kind, _total, Util.number(Store.state.get("total")))
	var margin := 16 if _compact else 32
	_header_margin.add_theme_constant_override("margin_left", margin)
	_header_margin.add_theme_constant_override("margin_right", margin)
	_header_margin.add_theme_constant_override("margin_top", 2 if _compact else 7)
	_header_margin.add_theme_constant_override("margin_bottom", 4 if _compact else 18)
	_header.apply({
		"title": _collection_title if not _collection_title.is_empty() else Pages.LIST[Pages.index_of(page_id)]["title"],
		"eyebrow": "LISTEN WITHOUT LIMITS" if queue else "YOUR COLLECTION",
		"subtitle": SUBTITLES.get(page_id, ""),
		"count": count,
		"icon": ICONS.get(page_id, "music_note"),
		"track": Store.track() if queue else {},
		"compact": _compact,
		"show_art": not _compact and width > WIDE_ART,
		"show_spectrum": not _compact and width > WIDE_SPECTRUM and queue and playing,
		"now_playing": queue and playing,
	})


func _render_provider_bar() -> void:
	var visible_bar := page_id == "playlists"
	(_provider_bar.get_parent() as Control).visible = visible_bar
	if not visible_bar:
		return
	UiKit.clear(_provider_row)
	var provider := _current_provider()
	var dropdown := OptionButton.new()
	dropdown.accessibility_name = "Provider"
	dropdown.flat = true
	var selected := -1
	for i in Store.providers.size():
		dropdown.add_item(Util.text(Store.providers[i].get("name")), i)
		if Store.providers[i].get("key") == Store.provider:
			selected = i
	dropdown.select(selected)
	dropdown.item_selected.connect(_on_provider_selected)
	_provider_row.add_child(dropdown)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(15, 0)
	_provider_row.add_child(gap)
	_provider_row.add_child(UiKit.chip("add_link", "Connect service", _configure_provider))
	_provider_row.add_child(UiKit.chip("library_music", "Playlists", _browse_provider.bind("playlists"), _kind == "playlists"))
	if provider.get("browse_artists") == true:
		_provider_row.add_child(UiKit.chip("person_outline", "Artists", _browse_provider.bind("artists"), _kind == "artists"))
	if provider.get("browse_albums") == true:
		_provider_row.add_child(UiKit.chip("album", "Albums", _browse_provider.bind("albums"), _kind == "albums"))
	if provider.get("catalog") == true:
		_provider_row.add_child(UiKit.chip("public", "Catalog", _browse_provider.bind("catalog")))
	if provider.get("authenticatable") == true and Store.supports("provider.auth"):
		_provider_row.add_child(UiKit.text_button("login", "Sign in", _authenticate.bind(provider), "Sign in", 12))
	if _kind == "albums" and not _sorts.is_empty():
		var sort := OptionButton.new()
		sort.accessibility_name = "Sort albums"
		sort.flat = true
		var current := Util.text(_params.get("sort"))
		var index := 0
		for i in _sorts.size():
			sort.add_item(Util.text(_sorts[i].get("label")), i)
			if Util.text(_sorts[i].get("id")) == current:
				index = i
		sort.select(index)
		sort.item_selected.connect(func(i: int) -> void:
			_fetch("provider.albums", {"provider": Store.provider, "sort": Util.text(_sorts[i].get("id"))}, "albums"))
		_provider_row.add_child(sort)
	if not _collection_title.is_empty():
		_provider_row.add_child(UiKit.text_button("arrow_back", "Back to browse", _browse_provider.bind("playlists"), "Back to browse", 12))


func _current_provider() -> Dictionary:
	for p in Store.providers:
		if p.get("key") == Store.provider:
			return p
	return {}


func _render_list_bar() -> void:
	var p := ThemeBuilder.palette
	var titles := {"tracks": "Tracks", "history": "Listening history", "playlists": "Made for listening", "albums": "Albums"}
	_list_title.text = titles.get(_kind, "Artists")
	_list_title.add_theme_color_override("font_color", p.foreground)
	_list_total.text = str(_total)
	_list_total.add_theme_color_override("font_color", p.muted)
	UiKit.clear(_list_actions)
	var tracky := _kind == "tracks" or _kind == "history"
	if tracky:
		_list_actions.add_child(_tool("checklist", "Select tracks", _toggle_selecting, _selecting))
	if _is_live() and Store.supports("queue.undo"):
		_list_actions.add_child(_tool("undo", "Undo last queue edit", _undo))
	if page_id == "playlists" and _kind == "playlists":
		if _playlist_list_undo.has(Store.provider) and _can_playlist("undo"):
			_list_actions.add_child(_tool("undo", "Undo last playlist edit", _undo))
		if _can_playlist("create"):
			_list_actions.add_child(UiKit.text_button("add", "New playlist", _create_playlist, "New playlist", 13))
	if page_id == "playlists" and not _collection.is_empty() and not LibraryLogic.SYSTEM_PLAYLISTS.has(_collection):
		for action in ["directories", "undo", "sort", "move", "import"]:
			if _can_playlist(action):
				_list_actions.add_child(_tool("edit_note", "Playlist tools: files, directories, sorting and undo", _playlist_tools))
				break
	if page_id == "queue" and not _items.is_empty():
		_list_actions.add_child(_tool("save", "Save queue as playlist", _save_queue))
	if (_is_live() or page_id == "history") and not _items.is_empty():
		var label := _page_label().to_lower()
		_list_actions.add_child(_tool("delete_sweep", "Clear " + label, _clear_list))
	if not _collection.is_empty() and _kind == "tracks" and page_id == "playlists":
		_list_actions.add_child(UiKit.text_button("play_arrow", "Load collection", _load_collection, "Load collection", 13))
	_list_actions.add_child(_tool("refresh", "Refresh", _refresh_list))


func _render_selection() -> void:
	var wrapper: Control = _selection_bar.get_meta("wrapper")
	wrapper.visible = _selecting
	if not _selecting:
		return
	UiKit.clear(_selection_row)
	var empty := _marked.is_empty()
	_selection_row.add_child(UiKit.label("%d selected" % _marked.size(), 13))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(12, 0)
	_selection_row.add_child(gap)
	_selection_row.add_child(UiKit.text_button("", "Select visible", _select_visible, "Select visible"))
	for entry in [["append", "Append"], ["next", "Play next"], ["replace", "Replace queue"], ["save", "Save to playlist"]]:
		var b := UiKit.text_button("", entry[1], _batch_tracks.bind(entry[0]), entry[1])
		b.disabled = empty
		_selection_row.add_child(b)
	if _is_live() or _can_remove_saved(true):
		var remove := UiKit.text_button("", "Remove", _batch_tracks.bind("remove"), "Remove")
		remove.disabled = empty
		_selection_row.add_child(remove)
	_selection_row.add_child(_tool("close", "Finish selecting", finish_selecting))


func _update_body() -> void:
	var tracky := _kind == "tracks" or _kind == "history"
	_track_view.visible = false
	_grid_scroll.visible = false
	_empty.visible = false
	if not _load_error.is_empty():
		_empty.show_message("wifi_off", "Couldn’t load this view", _load_error, _refresh_list, "Try again", "refresh")
		_empty.visible = true
	elif _items.is_empty():
		if not _loading:
			_show_empty_for_page()
	elif tracky:
		if _visible.is_empty():
			_empty.show_message("search", "No matching tracks", "Try another title, artist, or album.")
			_empty.visible = true
		else:
			_track_view.visible = true
	else:
		_grid_scroll.visible = true


func _show_empty_for_page() -> void:
	_empty.visible = true
	match page_id:
		"queue":
			_empty.show_message("library_music", "Your music belongs here",
				"Add a file, folder, playlist, or stream.\nEverything you love, in one listening space.",
				_add_source, "Add your first tracks")
		"next":
			_empty.show_message("playlist_play", "Choose what comes next", "Use a track’s menu to add it to Play next.")
		"favorites":
			_empty.show_message("favorite_border", "Keep the good ones close", "Tap the heart beside any track to find it here.")
		"history":
			_empty.show_message("history", "Your listening story starts here", "Tracks appear here as you listen.")
		"playlists":
			var can_create := _can_playlist("create")
			_empty.show_message("library_music", "A playlist for every mood",
				"Create your first playlist and add tracks from any collection." if can_create else "This provider has no saved playlists to show.",
				_create_playlist if can_create else Callable(), "Create playlist")
		_:
			_empty.show_message("explore", "Nothing here yet", "Try another collection or search this provider.")


## Recomputes what is shown from _items and the filter after a load.
func _rebuild_data() -> void:
	var tracky := _kind == "tracks" or _kind == "history"
	if tracky:
		_visible = LibraryLogic.visible_tracks(_items, Store.filter, _kind)
		_list.set_count(_visible.size())
		_list.rebind()
		_clear_cards()
	else:
		_visible = LibraryLogic.visible_collection(_items, Store.filter, _kind)
		_list.set_count(0)
		_rebuild_cards()


func _apply_filter() -> void:
	if not _active:
		return
	var tracky := _kind == "tracks" or _kind == "history"
	if tracky:
		_visible = LibraryLogic.visible_tracks(_items, Store.filter, _kind)
		_list.set_count(_visible.size(), true)
	else:
		_visible = LibraryLogic.visible_collection(_items, Store.filter, _kind)
		var shown := {}
		for p in _visible:
			shown[p] = true
		for i in _cards.size():
			_cards[i].visible = shown.has(i)
	_update_body()


# ---------------------------------------------------------------- Track rows

func _make_row() -> Control:
	var row := TrackRow.new()
	row.menu_provider = _menu_entries
	row.play_requested.connect(func(pos: int) -> void: _track_action("play", _track_at(pos), pos))
	row.mark_requested.connect(_mark)
	row.favorite_requested.connect(func(pos: int) -> void: _favorite(_track_at(pos)))
	row.action_requested.connect(func(action: String, pos: int) -> void: _track_action(action, _track_at(pos), pos))
	return row


func _track_at(pos: int) -> Dictionary:
	if pos < 0 or pos >= _items.size():
		return {}
	return LibraryLogic.track_of(_items[pos], _kind)


func _bind_row(row: Control, k: int) -> void:
	if k >= _visible.size():
		return
	var pos := _visible[k]
	var item := _items[pos]
	var track := LibraryLogic.track_of(item, _kind)
	var now := Store.track()
	var current: bool = now.get("path") != null and track.get("path") == now.get("path")
	var dur := Util.number(track.get("duration_secs"))
	if dur <= 0.0 and current:
		dur = Util.number(Store.state.get("duration"))
	var label := Util.text(track.get("title"), "track %d" % (pos + 1))
	(row as TrackRow).apply({
		"position": pos,
		"track_title": LibraryLogic.title_of(track),
		"artist": LibraryLogic.artist_of(track),
		"album": LibraryLogic.history_date(item.get("played_at")) if _kind == "history" else Util.text(track.get("album"), "—"),
		"listening": LibraryLogic.listening_text(Util.object(_listening.get(Util.text(track.get("path"))))),
		"duration": "LIVE" if track.get("realtime") == true else Util.duration_or_unknown(dur),
		"bookmark": track.get("bookmark") == true,
		"current": current,
		"playing": Store.is_playing(),
		"disabled": track.get("unplayable") == true,
		"marked": _marked.has(pos),
		"selecting": _selecting,
		"odd": k % 2 == 1,
		"show_album": _wide_columns,
		"connected": Store.connected,
		"art": track,
		"label": label,
	})


func _menu_entries(pos: int) -> Array:
	var entries: Array = [["next", "Play next"], ["playlist", "Add to playlist…"]]
	if _is_live():
		if pos > 0:
			entries.append(["up", "Move up"])
		if pos < maxi(_items.size(), _total) - 1:
			entries.append(["down", "Move down"])
	if _is_live() or _can_remove_saved():
		entries.append(["remove", "Remove from list"])
	if Store.supports("provider.related"):
		entries.append(["related", "Related tracks"])
	if Store.supports("provider.track_artist"):
		entries.append(["artist", "Go to artist"])
	entries.append(["details", "Track details"])
	return entries


func _toggle_selecting() -> void:
	_selecting = not _selecting
	if not _selecting:
		_marked.clear()
		_anchor = -1
	_render_list_bar()
	_render_selection()
	_list.rebind()


func _mark(pos: int) -> void:
	if Input.is_key_pressed(KEY_SHIFT) and _anchor != -1:
		for p in LibraryLogic.shift_range(_visible, _anchor, pos):
			_marked[p] = true
	elif _marked.has(pos):
		_marked.erase(pos)
	else:
		_marked[pos] = true
	_anchor = pos
	_render_selection()
	_list.rebind()


func _select_visible() -> void:
	_marked = LibraryLogic.toggle_visible(_visible, _marked)
	_render_selection()
	_list.rebind()


# ---------------------------------------------------------------- Collection grid

func _clear_cards() -> void:
	_cards.clear()
	UiKit.clear(_grid)


func _rebuild_cards() -> void:
	_clear_cards()
	var shown := {}
	for p in _visible:
		shown[p] = true
	for i in _items.size():
		var item := _items[i]
		var card := CollectionCard.new(item, _kind, LibraryLogic.collection_subtitle(item, Store.provider),
			Store.connected, _kind == "playlists", _playlist_menu_entries)
		card.activated.connect(_open_collection)
		card.action_requested.connect(_playlist_action)
		card.visible = shown.has(i)
		_grid.add_child(card)
		_cards.append(card)
	_update_columns()


func _update_columns() -> void:
	var width := _grid_scroll.size.x - 64.0
	_grid.columns = maxi(1, ceili(width / (250.0 + 18.0)))


func _playlist_menu_entries(item: Dictionary) -> Array:
	var entries: Array = [["load", "Load playlist"]]
	if item.get("favoritable") == true:
		entries.append(["favorite", "Remove favorite" if item.get("favorite") == true else "Add favorite"])
	if not LibraryLogic.SYSTEM_PLAYLISTS.has(Util.text(item.get("id"))):
		if _can_playlist("rename"):
			entries.append(["rename", "Rename…"])
		if _can_playlist("delete"):
			entries.append(["delete", "Delete…"])
	return entries


# ---------------------------------------------------------------- Provider toolbar actions

func _on_provider_selected(index: int) -> void:
	if index < 0 or index >= Store.providers.size():
		return
	Store.provider = Util.text(Store.providers[index].get("key"))
	Store.provider_seed = {}
	Store.provider_action = ""
	_browse_provider("playlists")


func _browse_provider(tab := "playlists") -> void:
	_collection = ""
	_collection_title = ""
	await _fetch("provider." + tab, {"provider": Store.provider}, "playlists" if tab == "catalog" else tab)


func _authenticate(provider: Dictionary) -> void:
	var script: Variant = _optional_script("res://ui/dialogs/provider_sign_in_dialog.gd")
	if script == null:
		return
	var connected: Variant = await script.open(self, Util.text(provider.get("key")), Util.text(provider.get("name")))
	if connected == true and is_inside_tree():
		Store.notify("Connected to %s" % Util.text(provider.get("name")))
		await _browse_provider()


func _configure_provider() -> void:
	var script: Variant = _optional_script("res://ui/dialogs/provider_setup_dialog.gd")
	if script == null:
		return
	var restarted: Variant = await script.open(self)
	if restarted == true and is_inside_tree():
		await Store.start()
		if Store.connected and _active:
			await activate()


## Loads a dialog script written by another part of the app; tells the user
## when it is not there yet.
func _optional_script(path: String) -> Variant:
	if not ResourceLoader.exists(path):
		Store.notify("This dialog is not available yet.", true)
		return null
	return load(path)


func _open_collection(item: Dictionary) -> void:
	_collection = Util.text(item.get("id"))
	_collection_title = Util.text(item.get("name"))
	if _kind == "artists":
		await _fetch("provider.artist_albums", {"provider": Store.provider, "artist": _collection}, "albums")
	elif _kind == "albums":
		await _fetch("provider.album_tracks", {"provider": Store.provider, "album": _collection})
	else:
		await _fetch("provider.tracks", {"provider": Store.provider, "playlist": _collection})


# ---------------------------------------------------------------- Actions

func _add_source() -> void:
	var script: Variant = _optional_script("res://ui/dialogs/add_source_dialog.gd")
	if script != null:
		await script.run(self)


func _favorite(track: Dictionary) -> void:
	if await _run("playlist.bookmark", {"provider": "local", "track": track}) != null:
		if _active and is_inside_tree() and (_kind == "tracks" or _kind == "history"):
			await _refresh_list()


func _track_action(action: String, track: Dictionary, pos: int) -> void:
	var live := page_id == "queue"
	var next := page_id == "next"
	var index := pos
	if live and track.get("index") != null:
		index = int(Util.number(track.get("index"), pos))
	match action:
		"play":
			var params := {"index": index} if live else {"track": track}
			params.merge(_revision())
			await _run("queue.play" if live else "track.play", params)
		"next":
			var params := {"index": index} if live else {"track": track}
			params.merge(_revision())
			await _run("queue.enqueue" if live else "track.queue", params, "Added to play next")
		"favorite":
			await _favorite(track)
		"playlist":
			await SaveToPlaylistDialog.save(self, [track])
		"remove":
			if not live and not next and not _can_remove_saved():
				return
			var operation := "queue.remove" if live else ("playnext.remove" if next else "playlist.remove")
			var params := {"index": index}
			if not live and not next:
				params["provider"] = Store.provider
				params["playlist"] = _collection
			else:
				params.merge(_revision())
			if await _run(operation, params) != null and _active and is_inside_tree():
				await _refresh_list()
		"up", "down":
			var to := index - 1 if action == "up" else index + 1
			if to < 0 or to >= _total:
				return
			var params := {"index": index, "to": to}
			params.merge(_revision())
			if await _run("playnext.move" if next else "queue.move", params) != null and _active and is_inside_tree():
				await _refresh_list()
		"related", "artist":
			await _open_track_provider(track, action)
		"details":
			var script: Variant = _optional_script("res://ui/dialogs/track_details_dialog.gd")
			if script != null:
				await script.open(self, track)


func _open_track_provider(track: Dictionary, action: String) -> void:
	var params := {"track": track}
	if action == "related":
		params["limit"] = 1
	var found: Variant = await _run("provider.track_artist" if action == "artist" else "provider.related", params)
	if found == null or not is_inside_tree():
		return
	var key := Util.text(found.get("provider"))
	if key.is_empty():
		Store.notify("This source does not support that action.")
		return
	Store.provider = key
	Store.provider_seed = track
	Store.provider_action = action
	Store.navigate("providers")


func _undo() -> void:
	var provider := Store.provider
	var playlist := _collection if not _collection.is_empty() else Util.text(_playlist_list_undo.get(provider))
	if not _is_live() and (page_id != "playlists" or playlist.is_empty()):
		return
	var params := _revision() if _is_live() else {"provider": provider, "playlist": playlist}
	if await _run("queue.undo" if _is_live() else "playlist.undo", params) != null and _active and is_inside_tree():
		if not _is_live() and _playlist_list_undo.get(provider) == playlist:
			_playlist_list_undo.erase(provider)
		await _refresh_list()


func _clear_list() -> void:
	var label := _page_label().to_lower()
	if not await Dialogs.confirm(self, "Clear %s?" % label, "This removes the entries from this list. Your music files are kept.", "Clear"):
		return
	var operation := "queue.clear" if page_id == "queue" else ("playnext.clear" if page_id == "next" else "history.clear")
	await _run(operation, {} if page_id == "history" else _revision())
	if _active and is_inside_tree():
		await _refresh_list()


func _load_collection() -> void:
	var album := _request == "provider.album_tracks"
	var params := {"provider": Store.provider}
	params["album" if album else "playlist"] = _collection
	if await _run("provider.load_album" if album else "provider.load", params) != null:
		Store.navigate("queue")


func _save_queue() -> void:
	var playlist_name: Variant = await Dialogs.prompt(self, "Save queue as playlist", "Playlist name", "", "", false, "Save", LibraryLogic.playlist_name_error)
	if playlist_name == null:
		return
	var params := {"provider": "local", "playlist": playlist_name}
	params.merge(_revision())
	await _run("playlist.save_queue", params, "Queue saved as %s" % playlist_name)


func _name_validator() -> Callable:
	return LibraryLogic.playlist_name_error if Store.provider == "local" else Callable()


func _create_playlist() -> void:
	if not _can_playlist("create"):
		return
	var provider := Store.provider
	var undoable := _can_playlist("undo")
	var playlist_name: Variant = await Dialogs.prompt(self, "Create a playlist", "Playlist name", "", "", false, "Create", _name_validator())
	if playlist_name == null:
		return
	var result: Variant = await _run("playlist.create", {"provider": provider, "playlist": playlist_name}, "Playlist created")
	if result != null and is_inside_tree():
		if undoable:
			_playlist_list_undo[provider] = Util.text(result.get("playlist"), playlist_name)
		if _active and page_id == "playlists" and Store.provider == provider:
			await _refresh_list()


func _playlist_tools() -> void:
	var changed := await PlaylistToolsDialog.open(self, Store.provider, _collection)
	if changed and _active and is_inside_tree():
		await _refresh_list()


func _playlist_action(action: String, item: Dictionary) -> void:
	if (action == "rename" or action == "delete") and not _can_playlist(action):
		return
	var params := {"provider": Store.provider, "playlist": item.get("id")}
	var provider := Store.provider
	var undoable := _can_playlist("undo")
	match action:
		"load":
			if await _run("provider.load", params) != null:
				Store.navigate("queue")
		"favorite":
			await _run("provider.favorite", params)
			if _active and is_inside_tree():
				await _refresh_list()
		"rename":
			var new_name: Variant = await Dialogs.prompt(self, "Rename playlist", "Playlist name", Util.text(item.get("name")), "", false, "Save", _name_validator())
			if new_name == null:
				return
			var renamed := params.duplicate()
			renamed["new_name"] = new_name
			if await _run("playlist.rename", renamed) != null and is_inside_tree():
				if undoable:
					_playlist_list_undo[provider] = new_name
				if _active:
					await _refresh_list()
		"delete":
			if await Dialogs.confirm(self, "Delete %s?" % Util.text(item.get("name")),
					"This deletes the saved playlist. Your music files are kept.", "Delete") \
					and await _run("playlist.delete", params) != null and is_inside_tree():
				if undoable:
					_playlist_list_undo[provider] = Util.text(item.get("id"))
				if _active:
					await _refresh_list()


func _batch_tracks(action: String) -> void:
	var positions: Array = _marked.keys()
	positions.sort()
	var picked: Array = []
	var used: Array = []
	for p: int in positions:
		if p < _items.size():
			picked.append(LibraryLogic.track_of(_items[p], _kind))
			used.append(p)
	if picked.is_empty():
		return
	if action == "save":
		await SaveToPlaylistDialog.save(self, picked)
		return
	if action == "remove":
		if not _is_live() and not _can_remove_saved(true):
			return
		if not await Dialogs.confirm(self, "Remove %d tracks?" % picked.size(), "The selected entries will be removed from this list.", "Remove"):
			return
		var indexes: Array = []
		for p: int in used:
			indexes.append(_items[p].get("index", p) if page_id == "queue" else p)
		var operation := "playlist.remove_many"
		if page_id == "queue":
			operation = "queue.remove_many"
		elif page_id == "next":
			operation = "playnext.remove_many"
		var params := {"indexes": indexes, "tracks": picked}
		if _is_live():
			params.merge(_revision())
		else:
			params["provider"] = Store.provider
			params["playlist"] = _collection
		await _run(operation, params)
	elif action == "next":
		var params := {"tracks": picked}
		params.merge(_revision())
		await _run("tracks.enqueue", params)
	else:
		if action == "replace" and Util.number(Store.state.get("total")) > 0 \
				and not await Dialogs.confirm(self, "Replace the queue?", "The selected tracks become the current playlist.", "Replace"):
			return
		var params := {"tracks": picked, "play": action == "replace"}
		params.merge(_revision())
		await _run("tracks.replace" if action == "replace" else "tracks.append", params)
	if _active and is_inside_tree():
		await _refresh_list()
