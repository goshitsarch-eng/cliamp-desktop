extends Node
## Drives the playlist and provider dialogs against a real engine by pressing
## their buttons. Needs CLIAMP_BINARY and an isolated CLIAMP_CONFIG_DIR/HOME:
##   godot --headless --path godot res://tests/engine_dialogs.tscn

var _failures := 0
var _checks := 0


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("ok   ", what)
	else:
		_failures += 1
		printerr("FAIL ", what)


func _dialog() -> AcceptDialog:
	for i in 200:
		for c in get_tree().root.get_children():
			if c is AcceptDialog and c.visible:
				return c
		await get_tree().create_timer(0.05).timeout
	return null


func _find_all(node: Node, pred: Callable, out: Array) -> void:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_find_all(c, pred, out)


func _button_with(root: Node, text: String) -> Button:
	var found: Array = []
	_find_all(root, func(n: Node) -> bool: return n is Button and n.text.contains(text), found)
	return found[0] if not found.is_empty() else null


func _ready() -> void:
	await Store.start()
	ok(Store.connected, "connected")
	var wav := ProjectSettings.globalize_path("user://dialogs.wav")
	_write_wav(wav)
	await Store.run("sources.load", {"args": [wav], "name": "replace", "play": false, "if_revision": Store.state.get("playlist_revision", 0)})
	var q := await Backend.call_op("queue.list", {"limit": 10})
	var tracks := Util.objects(q.get("tracks"))
	ok(tracks.size() == 1, "one track loaded to save")

	# Save to a new playlist through the chooser and the name prompt.
	var result := [null]
	var run := func() -> void:
		result[0] = await SaveToPlaylistDialog.save(self, tracks)
	run.call()
	var d := await _dialog()
	ok(d != null, "chooser opens")
	var new_button := _button_with(d, "New playlist")
	ok(new_button != null, "chooser offers New playlist")
	new_button.pressed.emit()
	d = await _dialog()
	ok(d != null and _find_edit(d) != null, "name prompt opens")
	var edit := _find_edit(d)
	edit.text = "Dialog test"
	d.get_ok_button().pressed.emit()
	for i in 100:
		if result[0] != null:
			break
		await get_tree().create_timer(0.1).timeout
	ok(result[0] == true, "save flow reports success (%s)" % str(result[0]))
	var lists := await Backend.call_op("provider.playlists", {"provider": "local", "limit": 50})
	var names := Util.objects(lists.get("playlists")).map(func(p: Dictionary) -> String: return str(p.get("name")))
	ok(names.has("Dialog test"), "playlist exists (%s)" % str(names))
	var saved := await Backend.call_op("provider.tracks", {"provider": "local", "playlist": "Dialog test", "limit": 10})
	ok(Util.objects(saved.get("tracks")).size() == 1, "track was written to the playlist")

	# Playlist tools open and close without changing anything.
	var tools := [null]
	var run_tools := func() -> void:
		tools[0] = await PlaylistToolsDialog.open(self, "local", "Dialog test")
	run_tools.call()
	d = await _dialog()
	ok(d != null, "playlist tools open")
	d.get_ok_button().pressed.emit()
	for i in 50:
		if tools[0] != null:
			break
		await get_tree().create_timer(0.1).timeout
	ok(tools[0] == false, "closing unchanged tools reports no change")

	# Provider setup opens against the live schema and closes.
	var setup := [null]
	var run_setup := func() -> void:
		setup[0] = await ProviderSetupDialog.open(self)
	run_setup.call()
	d = await _dialog()
	ok(d != null, "provider setup opens")
	await get_tree().create_timer(1.0).timeout
	var any_buttons: Array = []
	_find_all(d, func(n: Node) -> bool: return n is Button and n.visible, any_buttons)
	ok(any_buttons.size() > 0, "provider setup shows its choices (%d buttons)" % any_buttons.size())
	d.canceled.emit()
	for i in 50:
		if setup[0] != null:
			break
		await get_tree().create_timer(0.1).timeout
	ok(setup[0] == false, "closing setup without saving does not restart")

	await Store.run("playlist.delete", {"provider": "local", "playlist": "Dialog test"})
	print("engine_dialogs: %d checks, %d failure(s)" % [_checks, _failures])
	await Backend.close()
	get_tree().quit(1 if _failures > 0 else 0)


func _find_edit(root: Node) -> LineEdit:
	var found: Array = []
	_find_all(root, func(n: Node) -> bool: return n is LineEdit, found)
	return found[0] if not found.is_empty() else null


func _write_wav(path: String) -> void:
	var rate := 44100
	var count := rate * 3
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(sin(TAU * 330.0 * i / rate) * 4000.0))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(rate)
	f.store_32(rate * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
