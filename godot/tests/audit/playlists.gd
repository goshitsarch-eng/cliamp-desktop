extends AuditKit
## Playlist create / rename / delete / load / favorites / history through the UI.


func _dialog_edit(d: Window) -> LineEdit:
	var found := find_all(func(c: Control) -> bool: return c is LineEdit, d)
	return found[0] if not found.is_empty() else null


func _names() -> Array:
	var r := await Backend.call_op("provider.playlists", {"provider": "local", "limit": 100})
	return Util.objects(r.get("playlists")).map(func(p: Dictionary) -> String: return str(p.get("name")))


func _create(name: String) -> void:
	await click_name("New playlist")
	await wait(0.5)
	var ds := dialogs()
	if ds.is_empty():
		note("create dialog did not open for '%s'" % name)
		return
	var d: Window = ds.back()
	var edit := _dialog_edit(d)
	edit.text = name
	(d as AcceptDialog).get_ok_button().pressed.emit()
	await wait(0.8)
	var still := dialogs()
	print("create '%s': dialog still open=%s" % [name.left(30), not still.is_empty()])
	if not still.is_empty():
		var msgs := find_all(func(c: Control) -> bool: return c is Label and (c as Label).text.length() > 0, still.back())
		print("   dialog labels: ", msgs.map(func(l: Label) -> String: return l.text))
		await shot_dialogs("create_err_" + str(name.length()))
		await close_dialogs()


func run() -> void:
	await set_size(1280, 800)
	var paths: Array = []
	var dir := OS.get_environment("MUSIC")
	for f in DirAccess.get_files_at(dir):
		paths.append(dir.path_join(f))
	paths.sort()
	await Store.run("sources.load", {"args": paths, "name": "replace", "play": false, "if_revision": Store.state.get("playlist_revision", 0)})
	await click_name("Playlists")
	await wait(1.2)
	await shot("playlists_initial")
	lint("playlists-initial")
	for name in ["   ", "Road trip", "Road trip", "a/b", "x*y?", "Café ☕ 日本語", "L".repeat(240), "..", "con"]:
		await _create(name)
	print("playlists after creates: ", (await _names()).map(func(n: String) -> String: return n.left(24)))
	await wait(0.8)
	await shot("playlists_after_create")
	lint("playlists-after-create")

	# Open a playlist, add tracks, rename, delete
	await Store.run("sources.load", {"args": paths, "name": "replace", "play": false, "if_revision": Store.state.get("playlist_revision", 0)})
	var tracks := Util.objects((await Backend.call_op("queue.list", {"limit": 10})).get("tracks"))
	await Backend.call_op("playlist.add_many", {"provider": "local", "playlist": "Road trip", "tracks": tracks})
	await click_name("Refresh")
	await wait(1.0)
	var menus := all_named("Playlist actions for Road trip")
	check(menus.size() == 1, "card menu for Road trip")
	if menus.size() == 1:
		await menu_pick(menus[0], "Rename…", "rename")
		await wait(0.5)
		var ds := dialogs()
		check(not ds.is_empty(), "rename dialog opens")
		if not ds.is_empty():
			var edit := _dialog_edit(ds.back())
			print("rename prefilled: ", edit.text)
			edit.text = "Road trip 2"
			(ds.back() as AcceptDialog).get_ok_button().pressed.emit()
			await wait(0.8)
		print("after rename: ", (await _names()).map(func(n: String) -> String: return n.left(24)))
	# open the playlist card
	var cards := find_all(func(c: Control) -> bool: return c is CollectionCard and c.is_visible_in_tree())
	print("cards: ", cards.size())
	for c: Control in cards:
		if (c as CollectionCard).accessibility_name.contains("Road trip 2"):
			await click(c)
			await wait(1.2)
			await shot("playlist_opened")
			lint("playlist-opened")
			break
	await shot("playlist_state_after_open")
	await click_name("Back to browse")
	await wait(0.8)
	var m2 := all_named("Playlist actions for Road trip 2")
	if m2.size() == 1:
		await menu_pick(m2[0], "Delete…", "delete")
		await wait(0.5)
		await shot_dialogs("delete_confirm")
		var ds2 := dialogs()
		if not ds2.is_empty():
			(ds2.back() as AcceptDialog).get_ok_button().pressed.emit()
			await wait(0.8)
		print("after delete: ", (await _names()).map(func(n: String) -> String: return n.left(24)))
	await shot("playlists_final")

	# Favorites page
	await click_name("Favorites")
	await wait(1.0)
	await shot("favorites_empty")
	await Backend.call_op("playlist.bookmark", {"provider": "local", "track": tracks[0]})
	await click_name("Refresh")
	await wait(1.0)
	await shot("favorites_one")
	lint("favorites-one")
	# history page
	await Store.run("queue.play", {"index": 0, "if_revision": Store.state.get("playlist_revision", 0)})
	await wait(1.5)
	await click_name("History")
	await wait(1.2)
	await shot("history_one")
	lint("history-one")
