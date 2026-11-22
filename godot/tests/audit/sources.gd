extends AuditKit
## Real window, source dialog and engine. Use disposable music and profile directories.

func run() -> void:
	await set_size(1280, 800)
	var wav := OS.get_environment("SHOT_WAV")
	var root := ProjectSettings.globalize_path("user://source-fixtures")
	DirAccess.make_dir_recursive_absolute(root)
	var list := root.path_join("mix Café.m3u")
	var f := FileAccess.open(list, FileAccess.WRITE)
	f.store_line("#EXTM3U")
	f.store_line(wav)
	f.store_line(wav)
	f.close()
	await click_name("Add your first tracks")
	var d := await dialog_named("Add your music")
	check(d != null, "empty queue CTA opens Add music")
	if d == null:
		return
	var edit := by_name("File, folder, playlist, URL, or ssh:// path", d) as TextEdit
	await click(edit)
	await type_text("   ")
	await click(d.get_ok_button())
	d = await dialog_named("Add your music")
	check(by_text("Enter a file, folder, playlist, or URL.", d) != null, "spaces-only validation")
	await click(d.get_cancel_button())
	await load_source(list)
	check(await paths() == [wav, wav], "M3U loads both entries including duplicates")
	var before := await paths()
	await load_source(root.path_join("does not exist.wav"), true)
	check(await paths() == before, "failed replacement keeps previous tracks")
	await load_source(wav, true, false)
	check(await paths() == before, "cancelled replacement keeps tracks")
	await load_source(wav, true)
	check(await paths() == [wav] and Store.is_playing(), "confirmed replacement plays")
	await load_source(OS.get_environment("MUSIC"))
	check((await paths()).size() == 5, "folder append includes four audio tracks")
	await load_source(wav + "\n\n" + wav)
	check((await paths()).size() == 7, "multiline append drops blank lines")
	await load_source(root.path_join("x".repeat(300)) + ".wav")
	check((await paths()).size() == 7, "overlong missing path preserves queue")
	var broken := root.path_join("broken.wav")
	f = FileAccess.open(broken, FileAccess.WRITE)
	f.store_string("This is not a sound recording.")
	f.close()
	await load_source(broken, true)
	await wait(1)
	check(Store.connected, "corrupt WAV leaves engine responsive")
	await load_source(wav, true)
	check(Store.is_playing(), "playback recovers after corrupt input")
	await shot("source_recovery")


func load_source(source: String, replace := false, confirm := true) -> void:
	await click_name("Add music")
	var d := await dialog_named("Add your music")
	if d == null:
		check(false, "add dialog opens")
		return
	if replace:
		await click(by_name("Replace queue", d))
	var edit := by_name("File, folder, playlist, URL, or ssh:// path", d) as TextEdit
	await click(edit)
	edit.get_viewport().push_text_input(source)
	check(edit.text == source, "source text exact")
	await click(d.get_ok_button())
	if replace:
		var confirmation := await dialog_named("Replace the queue?")
		if confirmation != null:
			await click(confirmation.get_ok_button() if confirm else confirmation.get_cancel_button())
	await wait(0.6)


func dialog_named(title: String) -> ConfirmationDialog:
	for i in 40:
		for d in dialogs():
			if d.title == title:
				return d
		await frames(1)
	return null


func paths() -> Array:
	return Util.objects((await Backend.call_op("queue.list", {"limit": 100})).get("tracks")).map(
		func(track: Dictionary) -> String: return track.get("path", ""))
