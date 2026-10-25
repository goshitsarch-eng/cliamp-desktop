extends AuditKit
## Providers page (provider browser), equalizer keyboard, lyrics controls.


func run() -> void:
	await set_size(1280, 800)
	var paths: Array = []
	var dir := OS.get_environment("MUSIC")
	for f in DirAccess.get_files_at(dir):
		paths.append(dir.path_join(f))
	paths.sort()
	await Store.run("sources.load", {"args": paths, "name": "replace", "play": false, "if_revision": Store.state.get("playlist_revision", 0)})
	var tracks := Util.objects((await Backend.call_op("queue.list", {"limit": 10})).get("tracks"))
	await Backend.call_op("playlist.create", {"provider": "local", "playlist": "Mix"})
	await Backend.call_op("playlist.add_many", {"provider": "local", "playlist": "Mix", "tracks": tracks})
	Store.navigate("providers")
	await wait(1.5)
	await shot("providers_root")
	lint("providers-root")
	var rows := find_all(func(c: Control) -> bool: return c is PressPanel and c.is_visible_in_tree())
	print("press panels: ", rows.size(), " ", rows.map(func(r: Control) -> String: return r.accessibility_name))
	for r: Control in rows:
		if r.accessibility_name.contains("Mix"):
			await click(r)
			await wait(1.5)
			await shot("providers_mix_open")
			lint("providers-mix-open")
			break
	var texts := find_all(func(c: Control) -> bool: return c is Label and c.is_visible_in_tree() and c.get_window() == get_tree().root).map(func(l: Label) -> String: return l.text.left(40))
	print("labels now: ", texts.slice(0, 40))
	# browser search
	var edits := find_all(func(c: Control) -> bool: return c is LineEdit and c.is_visible_in_tree() and c.get_window() == get_tree().root)
	for e: LineEdit in edits:
		print("edit: ", e.accessibility_name, " / ", e.placeholder_text)
	if edits.size() > 1:
		var e: LineEdit = edits[edits.size() - 1]
		for q in ["alpha", "zzzz-no-match", "日本語", "x".repeat(300)]:
			e.text = q
			e.text_changed.emit(q)
			e.text_submitted.emit(q)
			await wait(1.0)
			print("search '%s' ok" % q.left(20))
		await shot("providers_search")
	# back / breadcrumb
	var backs := find_all(func(c: Control) -> bool: return c is Button and c.is_visible_in_tree() and (c.accessibility_name.to_lower().contains("back") or c.accessibility_name.to_lower().contains("up")))
	print("back buttons: ", backs.map(func(b: Control) -> String: return b.accessibility_name))

	# EQ keyboard: arrow keys on a band slider
	Store.navigate("equalizer")
	await wait(1.0)
	var band := by_name("1k Hz band") as VSlider
	band.grab_focus()
	await key(KEY_UP)
	await key(KEY_UP)
	await key(KEY_UP)
	await wait(0.8)
	print("EQ band after 3x Up: slider=", band.value, " state=", Store.state.get("eq_bands"), " preset=", Store.state.get("eq_preset"))
	await key(KEY_END)
	await wait(0.6)
	print("EQ band after End: slider=", band.value, " state=", Store.state.get("eq_bands"))
	await key(KEY_HOME)
	await wait(0.6)
	print("EQ band after Home: slider=", band.value)
	await shot("eq_extremes")
	await click_name("Reset equalizer to Flat")
	await wait(0.8)
	print("EQ after reset: ", Store.state.get("eq_bands"), (by_name("Equalizer preset") as OptionButton).text)
	# preset selection
	var opt := by_name("Equalizer preset") as OptionButton
	opt.select(1)
	opt.item_selected.emit(1)
	await wait(0.8)
	print("EQ preset Rock -> ", Store.state.get("eq_preset"), Store.state.get("eq_bands"))
	await shot("eq_rock")

	# Lyrics page with a playing track
	await Store.run("queue.play", {"index": 0, "if_revision": Store.state.get("playlist_revision", 0)})
	Store.navigate("lyrics")
	await wait(2.5)
	await shot("lyrics_playing")
	lint("lyrics-playing")
