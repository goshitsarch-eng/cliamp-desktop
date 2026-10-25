extends AuditKit
## Opens every dialog in isolation: reports window size, screenshots, lints and
## then dismisses it with Escape-equivalent close.

var _log: Array[String] = []


func _probe(name: String, opener: Callable, win_wait := 0.8) -> void:
	opener.call()
	await wait(win_wait)
	var ds := dialogs()
	if ds.is_empty():
		note("dialog '%s' did not open" % name)
		return
	for d: Window in ds:
		var screen := DisplayServer.screen_get_size()
		print("dialog %s: window %s content_min %s screen %s" % [name, d.size, d.get_contents_minimum_size(), screen])
		if d.size.y > 900 or d.size.x > 1200:
			note("dialog '%s' is oversized: %s" % [name, d.size])
		lint("dialog-" + name, d)
	await shot_dialogs(name)
	# Escape closes a dialog.
	await close_dialogs()
	if not dialogs().is_empty():
		note("dialog '%s' still open after close request" % name)


func run() -> void:
	await set_size(1280, 800)
	var paths: Array = []
	var dir := OS.get_environment("MUSIC")
	for f in DirAccess.get_files_at(dir):
		paths.append(dir.path_join(f))
	paths.sort()
	await Store.run("sources.load", {"args": paths, "name": "replace", "play": true, "if_revision": Store.state.get("playlist_revision", 0)})
	await wait(1.5)
	var tracks := Util.objects((await Backend.call_op("queue.list", {"limit": 10})).get("tracks"))
	var long_text := "A very long message. ".repeat(40) + "\nSecond line with unicode: Ünïcödé 日本語 – “quotes”"
	await _probe("save_to_playlist", func() -> void: SaveToPlaylistDialog.save(main, [tracks[0]]), 2.5)
	await _probe("add_source", func() -> void: AddSourceDialog.run(main))
	await _probe("track_details", func() -> void: TrackDetailsDialog.open(main, tracks[3]))
	await _probe("seek", func() -> void: SeekDialog.open(main, 3.0, 12.0))
	await _probe("jobs", func() -> void: JobsPanel.open(main))
	await _probe("provider_setup", func() -> void: ProviderSetupDialog.open(main))
	await _probe("provider_signin_local", func() -> void: ProviderSignInDialog.open(main, "spotify", "Spotify"))
	await _probe("plugin_command", func() -> void: PluginCommandDialog.open(main, ""))
	await _probe("confirm_long", func() -> void: Dialogs.confirm(main, "Confirm", long_text, "Do it"))
	await _probe("message_empty", func() -> void: Dialogs.message(main, "", ""))
	await _probe("prompt", func() -> void: Dialogs.prompt(main, "Name it", "Playlist name", "", "My playlist"))
	await _probe("prompt_multiline", func() -> void: Dialogs.prompt(main, "Notes", "Text", "line1\nline2", "", true))
	await _probe("adjust_volume", func() -> void: ShellActions.adjust_volume(main))
	await _probe("playlist_tools", func() -> void:
		await Store.run("playlist.create", {"provider": "local", "name": "AuditList"})
		PlaylistToolsDialog.open(main, "local", "AuditList"))
	var review := {"token": "t", "source": "owner/plugin", "digest": "abc123", "permissions": ["fs", "net"], "code": "plugin.register({name='x'})\n".repeat(80), "name": "x"}
	await _probe("plugin_review", func() -> void: PluginReviewDialog.open(main, review))
	await _probe("plugin_config", func() -> void: PluginConfigDialog.open(main, {"name": "demo", "config": {}}))
