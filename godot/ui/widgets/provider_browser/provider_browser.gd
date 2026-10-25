class_name ProviderBrowser
extends VBoxContainer
## Provider-owned browsing and actions, ported from provider_browser.dart. Which
## controls appear depends on the flags in the provider.list entry and in the
## provider.browse result. Full track dictionaries are forwarded to the page
## callbacks so provider identity, episode metadata and resume flags stay intact.

## Each callback takes the track Dictionary and may be a coroutine.
var on_play_track: Callable
var on_queue_track: Callable
var on_add_to_playlist: Callable
var on_toggle_favorite: Callable
## Called after an action replaced the queue with a provider collection.
var on_queue_loaded: Callable

var _provider: Dictionary = {}
var _seed: Dictionary = {}
var _initial_action := ""
var _browse: Dictionary = {}
var _response: Dictionary = {}
var _items: Array[Dictionary] = []
var _trail: Array = []
var _view := ProviderBrowse.View.new("provider.playlists", "playlists", "Playlists")
var _generation := 0
var _total := 0
var _catalog_offset := 0
var _catalog_more := false
var _loading := true
var _busy := false
var _pinned_only := false
var _filter := ""
var _error := ""
var _notice := ""
var _failed: Array[String] = []
var _operations: Dictionary = {}

var _search: LineEdit
var _refresh_button: Button
var _routes: HBoxContainer
var _progress: ProgressBar
var _chrome: VBoxContainer
var _list: VBoxContainer
var _footer: Button


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var toolbar := MarginContainer.new()
	_margins(toolbar, 32, 6, 32, 12)
	var tools := VBoxContainer.new()
	toolbar.add_child(tools)
	var top := HBoxContainer.new()
	_search = LineEdit.new()
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(_on_search_changed)
	_search.text_submitted.connect(_search_provider)
	top.add_child(_search)
	_refresh_button = Icons.button("refresh", "Reload collection", _refresh)
	top.add_child(_refresh_button)
	tools.add_child(top)
	var route_scroll := ScrollContainer.new()
	route_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	route_scroll.custom_minimum_size = Vector2(0, 44)
	_routes = HBoxContainer.new()
	_routes.add_theme_constant_override("separation", 8)
	route_scroll.add_child(_routes)
	tools.add_child(route_scroll)
	add_child(toolbar)
	_progress = ProgressBar.new()
	_progress.indeterminate = true
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0, 2)
	add_child(_progress)
	_chrome = VBoxContainer.new()
	add_child(_chrome)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var pad := MarginContainer.new()
	_margins(pad, 32, 0, 32, 20)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	pad.add_child(_list)
	scroll.add_child(pad)
	add_child(scroll)
	_footer = Button.new()
	_footer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_footer.pressed.connect(func() -> void: _show(_view, false, true))
	add_child(_footer)


func _ready() -> void:
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: _render())


## Loads `provider` (a provider.list entry). A seed track with action "artist" or
## "related" opens that track's artist or related tracks instead of the default.
func configure(provider: Dictionary, seed := {}, action := "") -> void:
	_provider = provider
	_seed = seed
	_initial_action = action
	_trail = []
	_browse = {}
	_search.text = ""
	_filter = ""
	_initialize()


func focus_search() -> void:
	_search.grab_focus()
	_search.select_all()


## The shell search box changed: narrow the visible list.
func set_filter(text: String) -> void:
	_filter = text.to_lower()
	_search.text = text
	_render_list()


## Enter in the shell search box.
func submit_search(text: String) -> void:
	_search.text = text
	_search_provider(text)


func reload() -> void:
	_refresh()


func is_busy() -> bool:
	return _busy


func _provider_key() -> String:
	return Util.text(_provider.get("key"))


func _owner() -> String:
	return Util.text(_view.params.get("provider"), _provider_key())


func _is_genres() -> bool:
	return _view.kind == "genres"


func _is_tracks() -> bool:
	return _view.kind == "tracks"


func _is_subscriptions() -> bool:
	return _view.kind == "subscriptions"


# Loading

func _initialize() -> void:
	_generation += 1
	var generation := _generation
	_loading = true
	_error = ""
	_notice = ""
	_items = []
	_render()
	var result := await Backend.call_op("provider.browse", {"provider": _provider_key()})
	if generation != _generation:
		return
	if Backend.failed(result):
		_loading = false
		_error = result["error"]["message"]
		_render()
		return
	_browse = Util.object(result.get("browse"))
	_operations.clear()
	for o in Store.operations:
		_operations[Util.text(o.get("name"))] = true
	if not _seed.is_empty() and _initial_action == "artist":
		await _artist_for(_seed)
	elif not _seed.is_empty() and _initial_action == "related":
		await _related(_seed)
	else:
		await _open_mode(Util.text(_browse.get("default_mode"), "playlists"))


func _show(view: ProviderBrowse.View, push := true, append := false) -> void:
	_generation += 1
	var generation := _generation
	if push:
		_trail.append(_view)
	_view = view
	_loading = true
	_error = ""
	if not append:
		_items = []
		_filter = ""
		_pinned_only = false
	_render()
	var params := {"provider": _provider_key()}
	params.merge(view.params, true)
	params["limit"] = 100
	if append:
		params["offset"] = _catalog_offset if view.operation == "provider.catalog" else _items.size()
	var result := await Backend.call_op(view.operation, params)
	if generation != _generation:
		return
	if Backend.failed(result):
		_loading = false
		_error = result["error"]["message"]
		_render()
		return
	var rows := Util.objects(result.get(view.kind))
	var prior := Util.object(_response.get("listening")) if append else {}
	_response = result.duplicate()
	if not prior.is_empty() or result.has("listening"):
		var merged := prior.duplicate()
		merged.merge(Util.object(result.get("listening")), true)
		_response["listening"] = merged
	if append and view.operation != "provider.catalog":
		_items.append_array(rows)
	else:
		_items = rows
	var total = result.get("total")
	_total = int(total) if total is int or total is float else _items.size()
	_catalog_more = false
	if view.operation == "provider.catalog":
		_catalog_offset = (_catalog_offset if append else 0) + _total
		_catalog_more = _total > 0
		_total = _items.size()
	_loading = false
	_render()
	if view.kind == "tracks" and not result.has("listening"):
		await _read_listening(generation, rows)


func _read_listening(generation: int, tracks: Array[Dictionary]) -> void:
	if tracks.is_empty():
		return
	var result := await Backend.call_op("provider.playback_state", {"provider": _owner(), "tracks": tracks})
	if generation != _generation:
		return
	if Backend.failed(result):
		# Older engines can omit the optional listening-state operation.
		var code: String = result["error"]["code"]
		if code != "unavailable" and code != "unknown_operation":
			_notice = "Listening progress is unavailable: " + result["error"]["message"]
			_render()
		return
	var merged := Util.object(_response.get("listening")).duplicate()
	merged.merge(Util.object(result.get("listening")), true)
	_response["listening"] = merged
	_render_list()


## Runs a provider action with the busy guard. Returns the result or null.
func _action(operation: String, params := {}) -> Variant:
	if _busy:
		return null
	_busy = true
	_error = ""
	_notice = ""
	_failed = []
	_render()
	var changes := ProviderBrowse.changes_queue(operation, params)
	var call_params := {"provider": _owner()}
	call_params.merge(params, true)
	if changes:
		var snapshot := await Backend.snapshot()
		if Backend.failed(snapshot):
			_busy = false
			_error = snapshot["error"]["message"]
			_render()
			return null
		call_params["if_revision"] = snapshot.get("playlist_revision", 0)
	var result := await Backend.call_op(operation, call_params)
	_busy = false
	if Backend.failed(result):
		_error = result["error"]["message"]
		_render()
		return null
	var failed = result.get("failed")
	if failed is Array:
		for name in failed:
			_failed.append(str(name))
	_render()
	return result


func _queue_loaded() -> void:
	if on_queue_loaded.is_valid():
		on_queue_loaded.call()


# Navigation

func _open_mode(mode: String, entry: Variant = null) -> void:
	_trail = []
	_search.text = ""
	await _show(ProviderBrowse.mode_view(mode, entry, _browse), false)


func _open(item: Dictionary) -> void:
	var id := Util.text(item.get("id"))
	var title := Util.text(item.get("name"), "Collection")
	var owner := {}
	if _view.params.get("provider") != null:
		owner["provider"] = _view.params["provider"]
	var location := Util.object(_browse.get("location"))
	if location.get("needed") == true and str(location.get("id")) == id:
		await _location_consent()
		return
	match _view.kind:
		"genres":
			var params := _view.params.duplicate()
			params["genre"] = id
			if _view.open_in_playlist:
				var loaded = await _action("provider.genre_tracks", _merged(params, {"mode": "load"}))
				if loaded != null:
					_queue_loaded()
			else:
				await _show(ProviderBrowse.View.new("provider.genre_tracks", "tracks", title, params))
		"artists":
			await _show(ProviderBrowse.View.new("provider.artist_albums", "albums", title, _merged(owner, {"artist": id}), _view.open_in_playlist))
		"albums":
			if _view.open_in_playlist:
				var operation := "provider.collection" if _operations.has("provider.collection") else "provider.load_album"
				var params := {"album": id}
				if operation == "provider.collection":
					params["source"] = "album"
					params["mode"] = "replace"
				var loaded = await _action(operation, params)
				if loaded != null:
					_queue_loaded()
			else:
				await _show(ProviderBrowse.View.new("provider.album_tracks", "tracks", title, _merged(owner, {"album": id})))
		"subscriptions":
			await _show(ProviderBrowse.View.new("provider.album_tracks", "tracks", title, {"album": id}))
		_:
			await _show(ProviderBrowse.View.new("provider.tracks", "tracks", title, {"playlist": id}))


static func _merged(base: Dictionary, extra: Dictionary) -> Dictionary:
	var out := base.duplicate()
	out.merge(extra, true)
	return out


func _refresh() -> void:
	if _busy or _loading:
		return
	if _browse.get("refreshable") == true:
		var params := {}
		if _view.params.get("playlist") != null:
			params["playlist"] = _view.params["playlist"]
		var result = await _action("provider.refresh", params)
		if result == null:
			return
		if result.get("playlists") != null and _view.kind != "playlists":
			await _open_mode("playlists")
			return
	await _show(_view, false)


func _on_search_changed(text: String) -> void:
	_filter = text.to_lower()
	_render_list()


func _search_provider(query: String) -> void:
	var q := query.strip_edges()
	match ProviderBrowse.search_plan(query, _view, _browse, _response, _provider):
		"catalog":
			await _show(ProviderBrowse.View.new("provider.catalog.search", "playlists", "Station catalog" if q.is_empty() else "Station search", {"query": q}))
		"clear":
			_filter = ""
			_render_list()
		"genres":
			await _show(ProviderBrowse.View.new("provider.genres", "genres", "Search " + _view.title.to_lower(), _merged(_view.params, {"query": q})))
		"search":
			await _show(ProviderBrowse.View.new("provider.search", "tracks", "Search results", {"query": q}))
		_:
			_filter = query.to_lower()
			_render_list()


func _change_sort(value: String) -> void:
	if _view.operation == "provider.albums" and _browse.get("album_sort_savable") == true:
		if await _action("provider.album_sort", {"sort": value}) == null:
			return
		_browse["album_sort"] = value
	await _show(_view.with_params(_merged(_view.params, {"sort": value})), false)


func _location_consent() -> void:
	var result = await _action("provider.location")
	if result == null:
		return
	var location := Util.object(result.get("location"))
	var label := Label.new()
	label.text = Util.text(location.get("prompt"), "Allow this provider to use your approximate location to find nearby radio stations?")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	var chosen: Variant = await Dialogs.open(self, "Local radio", label, ["Allow location", "Do not use location", "Cancel"])
	# Dismissing is not consent and does not record an answer.
	if chosen == null:
		return
	var allowed: bool = chosen == "Allow location"
	var saved = await _action("provider.location.consent", {"allowed": allowed})
	if saved != null:
		_browse["location"] = saved.get("location")
		_notice = ("Local radio " + Util.text(saved.get("place"))).strip_edges() if allowed else "Location is disabled."
		await _open_mode("playlists")


func _pin_genre(genre: Dictionary) -> void:
	var params := {"genre": genre.get("id")}
	if _view.params.get("entry") != null:
		params["entry"] = _view.params["entry"]
	var result = await _action("provider.genre.favorite", params)
	if result != null:
		genre["favorite"] = result.get("favorite") == true
		_render_list()


func _subscription_action(mode: String, show: Variant = null) -> void:
	var params := {"mode": mode}
	if show != null:
		params["playlist"] = show.get("id")
	var result = await _action("provider.subscriptions.newest" if show == null else "provider.subscription.load", params)
	if result == null:
		return
	_notice = "Added the newest episodes from your subscriptions." if show == null else "Updated the queue from %s." % Util.text(show.get("name"))
	_render()
	# Partial-feed failures stay visible here; successful additions are already
	# in the shared queue and must not be replayed.
	if _failed.is_empty() and mode == "play":
		_queue_loaded()


func _related(track: Dictionary) -> void:
	await _show(ProviderBrowse.View.new("provider.related", "tracks", "Related to " + Util.text(track.get("title"), "this track"), {"track": track, "mode": "read"}))


func _artist_for(track: Dictionary) -> void:
	var result = await _action("provider.track_artist", {"track": track})
	if result == null:
		_loading = false
		_render()
		return
	var artist := Util.object(result.get("artist"))
	_trail.append(_view)
	var params := {"artist": artist.get("id")}
	if result.get("provider") != null:
		params["provider"] = result["provider"]
	_view = ProviderBrowse.View.new("provider.artist_albums", "albums", Util.text(artist.get("name"), "Artist"), params)
	_items = Util.objects(result.get("albums"))
	_response = result
	var total = result.get("total")
	_total = int(total) if total is int or total is float else _items.size()
	_loading = false
	_filter = ""
	_render()


# Playing and queueing

func _load_collection(mode := "play") -> void:
	var params := _view.params
	var source := ProviderBrowse.collection_source(_view.operation)
	var has_collection := _operations.has("provider.collection")
	if mode == "append" and (not has_collection or source.is_empty()):
		return
	var result: Variant = null
	if has_collection and not source.is_empty():
		result = await _action("provider.collection", _merged(params, {"source": source, "filter": _filter, "mode": mode}))
	elif params.get("playlist") != null:
		result = await _action("provider.load", {"playlist": params["playlist"]})
	elif params.get("album") != null:
		result = await _action("provider.load_album", {"album": params["album"]})
	elif _view.operation == "provider.related":
		result = await _action("provider.related", _merged(params, {"mode": "play"}))
	elif params.get("genre") != null:
		result = await _action("provider.genre_tracks", _merged(params, {"mode": "play"}))
	if result == null:
		return
	if mode == "append":
		_notice = "Added the collection to the queue." if _filter.is_empty() else "Added matching tracks to the queue."
		_render()
	else:
		_queue_loaded()


func _track_action(action: String, track: Dictionary) -> void:
	var album := ProviderBrowse.album_id(track)
	if not album.is_empty() and action in ["open", "play", "append", "next"]:
		if action == "open":
			await _show(ProviderBrowse.View.new("provider.album_tracks", "tracks", Util.text(track.get("title"), "Album"), {"album": album, "provider": _owner()}))
		else:
			var result = await _action("provider.collection", {"source": "album", "album": album, "track": track, "mode": action})
			if result != null:
				_queue_loaded()
		return
	if not album.is_empty() and action == "album_favorite":
		await _action("provider.favorite", {"playlist": album})
		return
	match action:
		"play":
			await _play_visible_tracks(track)
		"append":
			var result = await _action("tracks.append", {"tracks": [track]})
			if result != null:
				_notice = "Added %s to the queue." % Util.text(track.get("title"), "track")
				_render()
		"next":
			if on_queue_track.is_valid():
				await on_queue_track.call(track)
		"playlist":
			if on_add_to_playlist.is_valid():
				await on_add_to_playlist.call(track)
		"favorite":
			if on_toggle_favorite.is_valid():
				await on_toggle_favorite.call(track)
			await _show(_view, false)
		"artist":
			await _artist_for(track)
		"related":
			await _related(track)
		"details":
			await _details(track)


func _play_visible_tracks(track: Dictionary) -> void:
	var source := ProviderBrowse.collection_source(_view.operation)
	if _operations.has("provider.collection") and not source.is_empty() and track.get("feed") != true:
		var result = await _action("provider.collection", _merged(_view.params, {"source": source, "filter": _filter, "mode": "play", "selected_path": track.get("path")}))
		if result != null:
			_queue_loaded()
		return
	if not _operations.has("tracks.replace") or track.get("feed") == true:
		if on_play_track.is_valid():
			await on_play_track.call(track)
		return
	if _busy:
		return
	_busy = true
	_error = ""
	_render()
	var failure := await _replace_with_visible(track)
	_busy = false
	_error = failure
	_render()
	if failure.is_empty():
		_queue_loaded()


## Loads the rest of the collection and replaces the queue with the visible
## tracks, starting at `track`. Returns an error message, "" on success.
func _replace_with_visible(track: Dictionary) -> String:
	var view := _view
	var filter := _filter
	var all: Array[Dictionary] = _items.duplicate()
	while all.size() < _total:
		var params := {"provider": _provider_key()}
		params.merge(view.params, true)
		params["offset"] = all.size()
		params["limit"] = 100
		var next := await Backend.call_op(view.operation, params)
		if Backend.failed(next):
			return next["error"]["message"]
		var page := Util.objects(next.get("tracks"))
		if page.is_empty():
			return "This collection changed while loading. Refresh and try again."
		all.append_array(page)
	var visible := ProviderBrowse.filtered(all, filter)
	var selected := -1
	for i in visible.size():
		if visible[i].get("path") == track.get("path") and visible[i].get("title") == track.get("title"):
			selected = i
			break
	if selected < 0:
		return "The selected track is no longer in this collection."
	if visible.size() > 1000:
		return "This selection exceeds the player's track-batch limit. Use Play collection to load the complete source."
	var snapshot := await Backend.snapshot()
	if Backend.failed(snapshot):
		return snapshot["error"]["message"]
	var replaced := await Backend.call_op("tracks.replace", {
		"tracks": visible,
		"play": true,
		"index": selected,
		"if_revision": snapshot.get("playlist_revision", 0),
	})
	if Backend.failed(replaced):
		return replaced["error"]["message"]
	return ""


func _details(track: Dictionary) -> void:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	var fields := {
		"title": "Title", "artist": "Artist", "album": "Album", "genre": "Genre", "year": "Year",
		"track_number": "Track number", "station": "Station", "path": "Location",
	}
	for key: String in fields:
		var value := Util.text(track.get(key))
		if value.is_empty():
			continue
		var name := Label.new()
		name.text = fields[key]
		name.add_theme_font_size_override("font_size", 11)
		name.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
		box.add_child(name)
		var text := RichTextLabel.new()
		text.fit_content = true
		text.selection_enabled = true
		text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		text.text = value
		text.accessibility_name = fields[key]
		box.add_child(text)
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(0, 8)
		box.add_child(gap)
	await Dialogs.open(self, "Track details", box, ["Close"], Vector2i(500, 0))


# Rendering

func _render() -> void:
	_search.placeholder_text = ("Find a country, tag, or genre..." if _is_genres()
		else "Filter subscribed shows..." if _is_subscriptions()
		else "Search %s..." % Util.text(_provider.get("name"), "this provider"))
	_search.editable = not _busy
	_refresh_button.tooltip_text = "Refresh provider from source" if _browse.get("refreshable") == true else "Reload collection"
	_refresh_button.accessibility_name = _refresh_button.tooltip_text
	_refresh_button.disabled = _busy or _loading
	_progress.modulate.a = 1.0 if _loading or _busy else 0.0
	_render_routes()
	_render_chrome()
	_render_list()


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _render_routes() -> void:
	_clear(_routes)
	for route in ProviderBrowse.routes(_browse, _provider):
		var chip := _chip(route["label"], route["icon"])
		chip.disabled = _busy
		var mode: String = route["mode"]
		if mode == "location":
			chip.pressed.connect(_location_consent)
		else:
			chip.pressed.connect(_open_mode.bind(mode, route["entry"]))
		_routes.add_child(chip)


func _render_chrome() -> void:
	_clear(_chrome)
	if not _error.is_empty():
		_chrome.add_child(_message(_error, true))
	if not _notice.is_empty():
		_chrome.add_child(_message(_notice, false))
	if not _failed.is_empty():
		_chrome.add_child(_message("Some shows could not be loaded: %s. Successful episodes were added." % ", ".join(_failed), true))
	_chrome.add_child(_breadcrumbs())
	if _is_subscriptions():
		_chrome.add_child(_subscription_toolbar())
	var sorts := Util.objects(_response.get("sorts"))
	if _is_genres() or not sorts.is_empty():
		_chrome.add_child(_filter_toolbar(sorts))
	_render_footer()


func _render_footer() -> void:
	var more := _items.size() < _total or _catalog_more
	_footer.visible = more
	if more:
		_footer.text = "Load more stations" if _catalog_more else "Load more - %d of %d" % [_items.size(), _total]
		_footer.accessibility_name = _footer.text
		_footer.disabled = _loading


func _visible_items() -> Array[Dictionary]:
	var pool: Array = _items
	if _pinned_only:
		pool = _items.filter(func(item: Dictionary) -> bool: return item.get("favorite") == true)
	return ProviderBrowse.filtered(pool, _filter)


func _narrowed() -> bool:
	return not _filter.strip_edges().is_empty() or _pinned_only


func _render_list() -> void:
	_clear(_list)
	if _loading:
		return
	if _items.is_empty():
		_list.add_child(_empty(false))
		return
	var items := _visible_items()
	if items.is_empty():
		_list.add_child(_empty(_narrowed()))
		return
	if _is_tracks():
		var listening := Util.object(_response.get("listening"))
		for track in items:
			_list.add_child(_track_row(track, listening))
	else:
		var previous := ""
		for item in items:
			var group := ProviderBrowse.group_of(item)
			if not group.is_empty() and group != previous:
				_list.add_child(_group_header(group))
			previous = group
			_list.add_child(_collection_row(item))


func _palette() -> Palette:
	return ThemeBuilder.palette


func _alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)


func _box(color: Color, radius: int, pad_x := 0, pad_y := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad_x
	s.content_margin_right = pad_x
	s.content_margin_top = pad_y
	s.content_margin_bottom = pad_y
	return s


func _margins(m: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)


func _text(text: String, size := 14, color: Variant = null, ellipsis := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if color is Color:
		l.add_theme_color_override("font_color", color)
	if ellipsis:
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.custom_minimum_size.x = 0
	return l


func _chip(label: String, icon: String) -> PressPanel:
	var p := _palette()
	var chip := PressPanel.new(_box(_alpha(p.foreground, 0.07), 10, 12, 7), _box(_alpha(p.foreground, 0.14), 10, 12, 7), p.accent)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(Icons.label(icon, 16, p.muted))
	row.add_child(_text(label, 12))
	chip.add_child(row)
	chip.accessibility_name = label
	return chip


func _message(text: String, is_error: bool) -> Control:
	var p := _palette()
	var tint := ThemeBuilder.palette.error if is_error else p.accent
	var holder := MarginContainer.new()
	_margins(holder, 32, 5, 32, 5)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(_alpha(tint, 0.14), 9, 14, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(Icons.label("info_outline" if is_error else "check_circle_outline", 17, tint))
	var label := _text(text, 12)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if is_error and not _busy:
		row.add_child(Icons.button("refresh", "Retry collection", func() -> void: _show(_view, false), 16))
	panel.add_child(row)
	holder.add_child(panel)
	holder.accessibility_name = text
	return holder


func _breadcrumbs() -> Control:
	var p := _palette()
	var holder := MarginContainer.new()
	_margins(holder, 32, 10, 32, 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	if not _trail.is_empty():
		var back := Icons.button("arrow_back", "Back to previous collection", _go_back, 19)
		back.disabled = _busy
		row.add_child(back)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_text(_view.title, 20, null, true))
	titles.add_child(_text("%d %s" % [_total, ProviderBrowse.count_noun(_view.kind)], 11, p.muted))
	row.add_child(titles)
	if _is_tracks() and not _items.is_empty() and _operations.has("provider.collection") and not ProviderBrowse.collection_source(_view.operation).is_empty():
		var add := Button.new()
		add.text = "Add collection to queue"
		add.accessibility_name = add.text
		add.disabled = _busy
		add.pressed.connect(_load_collection.bind("append"))
		row.add_child(add)
	var playable: bool = _view.params.get("playlist") != null or _view.params.get("album") != null or _view.params.get("genre") != null or _view.operation == "provider.related"
	if _is_tracks() and not _items.is_empty() and playable:
		var play := Button.new()
		play.text = "Play collection"
		play.accessibility_name = play.text
		play.disabled = _busy
		play.add_theme_stylebox_override("normal", _box(p.accent, 10, 14, 8))
		play.add_theme_stylebox_override("hover", _box(p.accent.lightened(0.15), 10, 14, 8))
		play.add_theme_color_override("font_color", p.on_accent())
		play.add_theme_color_override("font_hover_color", p.on_accent())
		play.pressed.connect(_load_collection.bind("play"))
		row.add_child(play)
	holder.add_child(row)
	return holder


func _go_back() -> void:
	if _busy or _trail.is_empty():
		return
	var previous: ProviderBrowse.View = _trail.pop_back()
	_show(previous, false)


func _subscription_toolbar() -> Control:
	var holder := MarginContainer.new()
	_margins(holder, 32, 0, 32, 14)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	for spec in [["Add newest from all shows", "append"], ["Play newest next", "next"]]:
		var b := Button.new()
		b.text = spec[0]
		b.accessibility_name = spec[0]
		b.disabled = _busy or _items.is_empty()
		b.pressed.connect(_subscription_action.bind(spec[1]))
		flow.add_child(b)
	holder.add_child(flow)
	return holder


func _filter_toolbar(sorts: Array[Dictionary]) -> Control:
	var holder := MarginContainer.new()
	_margins(holder, 32, 0, 32, 12)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 18)
	flow.add_theme_constant_override("v_separation", 8)
	if _is_genres() and _response.get("favoritable") == true:
		var pinned := Button.new()
		pinned.text = "Pinned only"
		pinned.toggle_mode = true
		pinned.button_pressed = _pinned_only
		pinned.accessibility_name = "Pinned only"
		pinned.toggled.connect(func(on: bool) -> void:
			_pinned_only = on
			_render_list())
		flow.add_child(pinned)
	if not sorts.is_empty():
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(240, 0)
		picker.accessibility_name = "Sort"
		picker.disabled = _busy
		var selected := 0
		for i in sorts.size():
			picker.add_item(Util.text(sorts[i].get("label")))
			if sorts[i].get("id") == _view.params.get("sort"):
				selected = i
		picker.select(selected)
		picker.item_selected.connect(func(index: int) -> void: _change_sort(Util.text(sorts[index].get("id"))))
		flow.add_child(picker)
	holder.add_child(flow)
	return holder


func _group_header(group: String) -> Control:
	var m := MarginContainer.new()
	_margins(m, 4, 14, 4, 3)
	var l := _text(group.to_upper(), 10, _palette().muted)
	l.add_theme_constant_override("outline_size", 0)
	m.add_child(l)
	return m


func _empty(filtered: bool) -> Control:
	var p := _palette()
	var texts := ProviderBrowse.empty_text(filtered, _filter, _pinned_only, _is_subscriptions())
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.custom_minimum_size = Vector2(0, 220)
	var icon := Icons.label("subscriptions" if _is_subscriptions() else "public" if _is_genres() else "library_music", 34, p.accent)
	box.add_child(icon)
	var title := _text(texts[0], 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body := _text(texts[1], 12, p.muted)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(body)
	return box


func _icon_tile(icon: String) -> Control:
	var p := _palette()
	var tile := PanelContainer.new()
	tile.custom_minimum_size = Vector2(44, 44)
	tile.add_theme_stylebox_override("panel", _box(_alpha(p.accent, 0.08), 10))
	tile.add_child(Icons.label(icon, 22, p.accent))
	return tile


func _row_panel() -> PressPanel:
	var p := _palette()
	var panel := PressPanel.new(_box(p.surface, 12, 16, 6), _box(p.surface.lerp(p.foreground, 0.06), 12, 16, 6), p.accent)
	return panel


func _collection_row(item: Dictionary) -> Control:
	var p := _palette()
	var name := Util.text(item.get("name"), "Untitled")
	var subtitle := ProviderBrowse.item_subtitle(item)
	var row := _row_panel()
	row.accessibility_name = name if subtitle.is_empty() else "%s, %s" % [name, subtitle]
	row.disabled = _busy
	row.pressed.connect(_open.bind(item))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 14)
	line.add_child(_icon_tile(ProviderBrowse.item_icon(_view.kind)))
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.alignment = BoxContainer.ALIGNMENT_CENTER
	texts.add_child(_text(name, 13, null, true))
	texts.add_child(_text(subtitle, 11, p.muted, true))
	line.add_child(texts)
	if item.get("restricted") == true:
		var lock := Icons.label("lock_outline", 16, p.muted)
		lock.tooltip_text = "Requires account access"
		lock.mouse_filter = Control.MOUSE_FILTER_PASS
		line.add_child(lock)
	var favoritable: bool = _response.get("favoritable") == true
	if _is_genres() and favoritable:
		var pinned: bool = item.get("favorite") == true
		var pin := Icons.button("push_pin", ("Unpin " if pinned else "Pin ") + name, _pin_genre.bind(item), 18)
		pin.add_theme_color_override("font_color", p.accent if pinned else p.muted)
		pin.disabled = _busy
		line.add_child(pin)
	if not _is_genres() and item.get("favoritable") == true:
		var fav: bool = item.get("favorite") == true
		var heart := Icons.button("favorite" if fav else "favorite_border", "Remove favorite" if fav else "Add favorite", _toggle_collection_favorite.bind(item), 18)
		heart.add_theme_color_override("font_color", p.accent if fav else p.muted)
		heart.disabled = _busy
		line.add_child(heart)
	if _view.kind == "albums" and _browse.get("album_favorite") == true and item.get("favoritable") != true:
		var album_heart := Icons.button("favorite_border", "Toggle album favorite", _toggle_album_favorite.bind(item), 18)
		album_heart.add_theme_color_override("font_color", p.muted)
		album_heart.disabled = _busy
		line.add_child(album_heart)
	if _is_subscriptions() or item.get("show") == true:
		line.add_child(_episode_menu(item))
	line.add_child(Icons.label("chevron_right", 17, p.muted))
	row.add_child(line)
	return row


func _toggle_collection_favorite(item: Dictionary) -> void:
	if await _action("provider.favorite", {"playlist": item.get("id")}) != null:
		await _show(_view, false)


func _toggle_album_favorite(item: Dictionary) -> void:
	if await _action("provider.favorite", {"playlist": item.get("id")}) != null:
		_notice = "Album favorite updated."
		_render()


func _menu_button(tooltip: String) -> MenuButton:
	var m := MenuButton.new()
	m.flat = true
	m.theme_type_variation = "IconButton"
	m.text = Icons.glyph("more_vert")
	m.add_theme_font_override("font", Icons.font())
	m.add_theme_font_size_override("font_size", 20)
	m.tooltip_text = tooltip
	m.accessibility_name = tooltip
	m.disabled = _busy
	m.custom_minimum_size = Vector2(36, 32)
	return m


func _episode_menu(item: Dictionary) -> MenuButton:
	var menu := _menu_button("Episode actions")
	var modes := ["append", "play", "next", "newest", "newest_next"]
	var labels := ["Add all episodes", "Play episodes", "Queue all episodes next", "Add newest episode", "Play newest episode next"]
	var popup := menu.get_popup()
	for i in modes.size():
		popup.add_item(labels[i], i)
	popup.id_pressed.connect(func(id: int) -> void: _subscription_action(modes[id], item))
	return menu


func _track_row(track: Dictionary, listening: Dictionary) -> Control:
	var p := _palette()
	var album := ProviderBrowse.album_id(track)
	var status := Util.object(listening.get(Util.text(track.get("path"))))
	var position := Util.number(status.get("position"))
	var duration := Util.number(track.get("duration_secs"))
	var title := Util.text(track.get("title"), Util.text(track.get("path")))
	var row := PressPanel.new(_box(p.surface, 10, 10, 6), _box(p.surface.lerp(p.foreground, 0.06) if not album.is_empty() else p.surface, 10, 10, 6), p.accent)
	row.accessibility_name = title
	if album.is_empty() or _busy:
		row.disabled = false
		row.focus_mode = Control.FOCUS_NONE
		row.mouse_default_cursor_shape = Control.CURSOR_ARROW
	else:
		row.pressed.connect(_track_action.bind("open", track))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	var play := Icons.button("play_arrow", "Play " + Util.text(track.get("title"), "track"), _track_action.bind("play", track), 24)
	play.add_theme_color_override("font_color", p.accent)
	play.disabled = _busy or track.get("unplayable") == true
	line.add_child(play)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_child(_text(title, 13, null, true))
	texts.add_child(_text(Util.text(track.get("artist"), Util.text(track.get("album"), "Unknown artist")), 11, p.muted, true))
	if not album.is_empty():
		texts.add_child(_text("Album - Open to browse tracks", 10, p.muted))
	if status.get("played") == true:
		var played := HBoxContainer.new()
		played.add_child(Icons.label("check_circle_outline", 13, p.accent))
		played.add_child(_text(" Played", 10, p.accent))
		texts.add_child(played)
	elif position > 0.0:
		texts.add_child(_text("Continue at " + ProviderBrowse.time(position), 10, p.accent))
		if duration > 0.0:
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.min_value = 0.0
			bar.max_value = 1.0
			bar.value = clampf(position / duration, 0.0, 1.0)
			bar.custom_minimum_size = Vector2(0, 2)
			bar.accessibility_name = "Listening progress"
			texts.add_child(bar)
	line.add_child(texts)
	line.add_child(_text("LIVE" if track.get("realtime") == true else Util.duration_or_unknown(duration), 11, p.muted))
	if album.is_empty():
		var bookmarked: bool = track.get("bookmark") == true
		var heart := Icons.button("favorite" if bookmarked else "favorite_border", "Remove track favorite" if bookmarked else "Favorite track", _track_action.bind("favorite", track), 18)
		heart.add_theme_color_override("font_color", p.accent if bookmarked else p.muted)
		heart.disabled = _busy
		line.add_child(heart)
	var menu := _menu_button("Track actions")
	var entries := ProviderBrowse.track_menu(track, _browse, _operations)
	var popup := menu.get_popup()
	for i in entries.size():
		popup.add_item(entries[i]["label"], i)
		popup.set_item_disabled(i, entries[i]["disabled"])
	popup.id_pressed.connect(func(id: int) -> void: _track_action(entries[id]["id"], track))
	line.add_child(menu)
	row.add_child(line)
	return row
