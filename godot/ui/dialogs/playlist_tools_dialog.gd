class_name PlaylistToolsDialog
extends VBoxContainer
## Saved-playlist edits that keep the playlist document intact: add files,
## directory sources, sort, move, undo. Talks to the engine directly and shows
## failures inline, like the Flutter dialog.

const SORTS: Array[Array] = [
	["track", "Track number"], ["title", "Title"], ["artist", "Artist"],
	["album", "Album"], ["artist+album", "Artist + album"], ["path", "Path"],
]
const PAGE := 200

var provider := ""
var playlist := ""

var _capabilities: Dictionary = {}
var _directories: Array[Dictionary] = []
var _tracks: Array[Dictionary] = []
var _error := ""
var _busy := true
var _changed := false
var _sort := "title"
var _page_offset := 0
var _total := 0
var _closed := false
var _generation := 0

var _progress := ProgressBar.new()
var _error_label := Label.new()
var _body := VBoxContainer.new()


## Returns true when the playlist was changed.
static func open(host: Node, provider_key: String, playlist_id: String) -> bool:
	var content := PlaylistToolsDialog.new()
	content.provider = provider_key
	content.playlist = playlist_id
	await Dialogs.open(host, "Manage " + Util.single_line(playlist_id), content, ["Done"], Vector2i(720, 540))
	return content._changed


func _init() -> void:
	custom_minimum_size = Vector2(700, 500)
	_progress.custom_minimum_size = Vector2(0, 3)
	_progress.show_percentage = false
	_progress.indeterminate = true
	add_child(_progress)
	_error_label.add_theme_color_override("font_color", ThemeBuilder.palette.error)
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_error_label)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_body)


func _ready() -> void:
	tree_exiting.connect(func() -> void: _closed = true)
	_refresh()


func _target() -> Dictionary:
	return {"provider": provider, "playlist": playlist}


func _set_busy(busy: bool) -> void:
	_busy = busy
	_progress.visible = busy
	var w := get_window()
	if w is AcceptDialog:
		(w as AcceptDialog).get_ok_button().disabled = busy


## Runs an engine call; on failure shows the message inline and returns null.
func _call(operation: String, params: Dictionary) -> Variant:
	var result := await Backend.call_op(operation, params)
	if _closed:
		return null
	if Backend.failed(result):
		_error = result["error"]["message"]
		return null
	if result.get("ok") == false:
		_error = Util.text(result.get("error"), "The operation could not be completed.")
		return null
	return result


func _refresh() -> void:
	_generation += 1
	var generation := _generation
	_set_busy(true)
	var caps: Variant = await _call("playlist.capabilities", _target())
	if _closed or generation != _generation:
		return
	if caps != null:
		var dirs: Variant = {}
		if caps.get("directories") == true:
			dirs = await _call("playlist.dirs.list", _target())
			if _closed or generation != _generation:
				return
		if dirs != null:
			_capabilities = caps
			_directories = Util.objects(dirs.get("directories"))
			_error = ""
			_render()
			var page: Variant = {}
			if caps.get("replace") == true:
				var params := _target()
				params["offset"] = _page_offset
				params["limit"] = PAGE
				page = await _call("provider.tracks", params)
				if _closed or generation != _generation:
					return
			if page != null:
				_tracks = Util.objects(page.get("tracks"))
				_total = int(Util.number(page.get("total"), _tracks.size()))
				if _total == 0:
					_page_offset = 0
				elif _page_offset >= _total:
					_page_offset = maxi(0, ((_total - 1) / PAGE) * PAGE)
					var clamped := _target()
					clamped["offset"] = _page_offset
					clamped["limit"] = PAGE
					var refetched: Variant = await _call("provider.tracks", clamped)
					if _closed or generation != _generation:
						return
					if refetched != null:
						_tracks = Util.objects(refetched.get("tracks"))
						_total = int(Util.number(refetched.get("total"), _tracks.size()))
	_set_busy(false)
	_render()


func _write(operation: String, params := {}) -> void:
	_set_busy(true)
	_error = ""
	_render()
	var merged := _target()
	merged.merge(params, true)
	var result: Variant = await _call(operation, merged)
	if _closed:
		return
	if result != null:
		_changed = true
		await _refresh()
	else:
		_set_busy(false)
		_render()


func _render() -> void:
	_error_label.text = _error
	_error_label.visible = not _error.is_empty()
	UiKit.clear(_body)
	var muted := ThemeBuilder.palette.muted
	if _capabilities.get("import") == true and _capabilities.get("can_add") != false:
		var add_files := UiKit.text_button("audio_file", "Add files", _add_files, "Add files")
		add_files.disabled = _busy
		add_files.size_flags_horizontal = Control.SIZE_SHRINK_END
		_body.add_child(add_files)
	if _capabilities.get("directories") == true:
		_render_directories()
		_body.add_child(HSeparator.new())
	if _capabilities.get("replace") == true:
		_render_tracks(muted)
	else:
		var none := UiKit.label("This provider does not support playlist sorting.", 13, muted)
		none.size_flags_vertical = Control.SIZE_EXPAND_FILL
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_body.add_child(none)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	if _capabilities.get("undo") == true:
		var undo := UiKit.text_button("undo", "Undo last playlist edit", _write.bind("playlist.undo"), "Undo last playlist edit")
		undo.disabled = _busy
		bar.add_child(undo)
	var refresh := UiKit.text_button("", "Refresh", _refresh, "Refresh")
	refresh.disabled = _busy
	bar.add_child(refresh)
	_body.add_child(bar)


func _render_directories() -> void:
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Directory sources"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var add := UiKit.text_button("create_new_folder", "Add folder", _add_directory, "Add folder")
	add.disabled = _busy
	head.add_child(add)
	_body.add_child(head)
	if _directories.is_empty():
		_body.add_child(UiKit.label("No directory sources. Added folders rescan on load.", 12, ThemeBuilder.palette.muted))
		return
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 110)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for source in _directories:
		var row := HBoxContainer.new()
		row.add_child(Icons.label("folder", 18))
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var path := UiKit.label(Util.text(source.get("path")), 13)
		path.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		path.clip_text = true
		text.add_child(path)
		text.add_child(UiKit.label("Include subfolders", 11, ThemeBuilder.palette.muted))
		row.add_child(text)
		var toggle := CheckButton.new()
		toggle.set_pressed_no_signal(source.get("recursive") == true)
		toggle.disabled = _busy
		toggle.accessibility_name = "Include subfolders of " + Util.text(source.get("path"))
		toggle.toggled.connect(func(on: bool) -> void:
			_write("playlist.dirs.recursive", {"path": source.get("path"), "name": "on" if on else "off"}))
		row.add_child(toggle)
		var remove := Icons.button("remove_circle_outline", "Remove directory source", func() -> void: _remove_directory(source), 18)
		remove.disabled = _busy
		row.add_child(remove)
		list.add_child(row)
	_body.add_child(scroll)


func _render_tracks(muted: Color) -> void:
	var head := HBoxContainer.new()
	var count := Label.new()
	count.text = Util.count_of(_total, "track")
	count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(count)
	var sort := OptionButton.new()
	sort.accessibility_name = "Sort by"
	for i in SORTS.size():
		sort.add_item(SORTS[i][1], i)
		if SORTS[i][0] == _sort:
			sort.select(i)
	sort.disabled = _busy
	sort.item_selected.connect(func(index: int) -> void: _sort = SORTS[index][0])
	head.add_child(sort)
	var go := UiKit.text_button("sort", "Sort and save", _sort_tracks, "Sort and save")
	go.disabled = _busy or _tracks.is_empty()
	head.add_child(go)
	_body.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for index in _tracks.size():
		var track := _tracks[index]
		var sourced: bool = track.get("dir_sourced") == true
		var row := HBoxContainer.new()
		if sourced:
			var folder := Icons.label("folder", 18)
			folder.tooltip_text = "Supplied by a directory source"
			folder.mouse_filter = Control.MOUSE_FILTER_STOP
			folder.custom_minimum_size = Vector2(36, 0)
			row.add_child(folder)
		else:
			var number := UiKit.label(str(_page_offset + index + 1), 12, muted)
			number.custom_minimum_size = Vector2(36, 0)
			row.add_child(number)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		var title := UiKit.label(Util.text(track.get("title"), Util.text(track.get("path"))), 13)
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.clip_text = true
		text.add_child(title)
		text.add_child(UiKit.label(Util.text(track.get("artist")), 11, muted))
		row.add_child(text)
		if not sourced:
			var up := Icons.button("arrow_upward", "Move track up", _move_track.bind(index, -1), 16)
			up.disabled = _busy or not _can_move(index, -1)
			row.add_child(up)
			var down := Icons.button("arrow_downward", "Move track down", _move_track.bind(index, 1), 16)
			down.disabled = _busy or not _can_move(index, 1)
			row.add_child(down)
		list.add_child(row)
	_body.add_child(scroll)
	var pager := HBoxContainer.new()
	pager.alignment = BoxContainer.ALIGNMENT_END
	var first := 0 if _total == 0 else _page_offset + 1
	pager.add_child(UiKit.label("%d–%d of %d" % [first, _page_offset + _tracks.size(), _total], 12, muted))
	var prev := Icons.button("chevron_left", "Previous page", _change_page.bind(-1))
	prev.disabled = _busy or _page_offset == 0
	pager.add_child(prev)
	var next := Icons.button("chevron_right", "Next page", _change_page.bind(1))
	next.disabled = _busy or _page_offset + _tracks.size() >= _total
	pager.add_child(next)
	_body.add_child(pager)


func _add_directory() -> void:
	var paths := await Dialogs.pick_paths(DisplayServer.FILE_DIALOG_MODE_OPEN_DIR, "Add directory source")
	if not _closed and is_inside_tree():
		get_window().grab_focus()
	if _closed or paths.is_empty():
		return
	await _write("playlist.dirs.add", {"path": paths[0]})


func _add_files() -> void:
	var paths := await Dialogs.pick_paths(DisplayServer.FILE_DIALOG_MODE_OPEN_FILES, "Add to playlist", PackedStringArray(AddSourceDialog.AUDIO_FILTERS))
	if not _closed and is_inside_tree():
		get_window().grab_focus()
	if _closed or paths.is_empty():
		return
	await _write("playlist.import", {"args": Array(paths)})


func _remove_directory(source: Dictionary) -> void:
	var path := Util.text(source.get("path"))
	var ok := await Dialogs.confirm(self, "Remove directory source?",
		"%s\n\nThe files stay on disk. They will no longer be supplied by this playlist source." % path, "Remove source")
	if ok and not _closed:
		await _write("playlist.dirs.remove", {"path": path})


func _sort_tracks() -> void:
	_page_offset = 0
	await _write("playlist.sort", {"sort": _sort})


func _can_move(from: int, step: int) -> bool:
	var to := from + step
	while to >= 0 and to < _tracks.size() and _tracks[to].get("dir_sourced") == true:
		to += step
	var target := _page_offset + to
	return target >= 0 and target < _total


func _move_track(from: int, step: int) -> void:
	var to := from + step
	while to >= 0 and to < _tracks.size() and _tracks[to].get("dir_sourced") == true:
		to += step
	var target := _page_offset + to
	if target < 0 or target >= _total:
		return
	await _write("playlist.move", {"index": _page_offset + from, "to": target, "track": _tracks[from]})


func _change_page(direction: int) -> void:
	var max_offset := maxi(0, ((_total - 1) / PAGE) * PAGE) if _total > 0 else 0
	_page_offset = clampi(_page_offset + PAGE * direction, 0, max_offset)
	_refresh()
