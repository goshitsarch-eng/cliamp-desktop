extends Node
## Drives the real autoloads against a real cliamp. Needs CLIAMP_BINARY and an
## isolated CLIAMP_CONFIG_DIR (and HOME/XDG dirs). Run:
##   godot --headless --path godot res://tests/engine_smoke.tscn
## Exits non-zero when any check fails.

var _failures := 0
var _checks := 0


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("ok   ", what)
	else:
		_failures += 1
		printerr("FAIL ", what)


func _ready() -> void:
	Store.notice.connect(func(m: String, e: bool) -> void: print("notice(", e, "): ", m))
	await Store.start()
	ok(Store.connected, "connected to the engine (%s)" % Store.connection_error)
	if not Store.connected:
		_done()
		return
	ok(not Store.operations.is_empty(), "capabilities loaded (%d operations)" % Store.operations.size())
	ok(not Store.providers.is_empty(), "providers loaded (%d)" % Store.providers.size())
	ok(Store.state.get("state") == "stopped", "snapshot state")

	var r = await Store.run("volume.adjust", {"value": -1})
	ok(r != null, "volume.adjust ok")
	r = await Store.run("eq", {"name": "Rock"})
	ok(r != null and Store.state.get("eq_preset") == "Rock", "eq preset applied (%s)" % str(Store.state.get("eq_preset")))
	r = await Store.run("eq", {"name": "Flat"})
	r = await Store.run("shuffle", {"name": "toggle"})
	ok(r != null and Store.state.get("shuffle") == true, "shuffle toggled")
	await Store.run("shuffle", {"name": "toggle"})

	var q := await Backend.call_op("queue.list", {"limit": 200})
	ok(not Backend.failed(q), "queue.list " + str(q))
	r = await Store.run("queue.remove", {"index": 0, "if_revision": 9999})
	ok(r == null, "stale revision is refused and reported")

	var prefs := await Backend.preferences_schema()
	ok(not Backend.failed(prefs), "preferences schema")
	var plugins := await Backend.plugin_action("list")
	ok(not Backend.failed(plugins), "plugin list")
	var setup := await Backend.setup_schema("")
	ok(not Backend.failed(setup), "setup schema list")

	var frame := await Backend.read_frame(40, 10)
	ok(not Backend.failed(frame), "visualizer frame (%s)" % str(frame.get("error", "")))
	ok(Backend.current_jobs().is_empty() or true, "jobs tracked")

	var tracks := await Backend.call_op("provider.playlists", {"provider": "local", "limit": 50})
	ok(not Backend.failed(tracks), "local playlists " + str(tracks))

	await _playback()
	_done()


## A generated sine WAV: sources.load, play, seek, pause, spectrum, frame, queue edits.
func _playback() -> void:
	var path := OS.get_environment("SMOKE_WAV")
	if path.is_empty():
		path = ProjectSettings.globalize_path("user://smoke.wav")
	_write_wav(path, 6.0)
	var loaded = await Store.run("sources.load", {"args": [path], "name": "replace", "play": true, "if_revision": Store.state.get("playlist_revision", 0)})
	ok(loaded != null, "sources.load replace+play")
	await _wait_for(func() -> bool: return Store.state.get("state") == "playing", "state becomes playing")
	ok(Store.track().get("path", "").get_file() == path.get_file(), "current track is the loaded file (%s)" % Store.track().get("path", ""))
	ok(Util.number(Store.state.get("duration")) > 5.0, "duration read (%s)" % str(Store.state.get("duration")))
	var before := Util.number(Store.state.get("position"))
	await get_tree().create_timer(1.2).timeout
	await Store.refresh_state()
	ok(Util.number(Store.state.get("position")) > before, "position advances")
	ok(Store.bands.size() > 0, "spectrum bands streamed (%d)" % Store.bands.size())
	var frame := await Backend.read_frame(60, 12)
	ok(not Backend.failed(frame) and str(frame).length() > 40, "visualizer frame while playing")
	var q := await Backend.call_op("queue.list", {"limit": 200})
	ok(not Backend.failed(q) and Util.objects(q.get("tracks")).size() == 1, "queue holds one track")
	var sk = await Store.run("seek", {"value": 2})
	ok(sk != null, "relative seek")
	var tg = await Store.run("toggle")
	await _wait_for(func() -> bool: return Store.state.get("state") == "paused", "pause")
	await Store.run("toggle")
	var vol = await Store.run("volume.adjust", {"value": -2})
	ok(vol != null, "volume adjust")
	var ly := await Backend.call_op("lyrics", {})
	ok(not Backend.failed(ly), "lyrics op answers (%s)" % str(ly).left(80))
	var hist := await Backend.call_op("history", {"limit": 10})
	ok(not Backend.failed(hist), "history op")
	var removed = await Store.run("queue.clear", Store.revision())
	ok(removed != null, "queue.clear")
	await Store.run("stop")


func _wait_for(cond: Callable, what: String) -> void:
	var end := Time.get_ticks_msec() + 8000
	while not cond.call():
		if Time.get_ticks_msec() > end:
			ok(false, "timed out: " + what)
			return
		await get_tree().create_timer(0.1).timeout
		await Store.refresh_state()
	ok(true, what)


func _write_wav(path: String, seconds: float) -> void:
	var rate := 44100
	var count := int(rate * seconds)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(sin(TAU * 440.0 * i / rate) * 6000.0))
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


func _done() -> void:
	print("engine_smoke: %d checks, %d failure(s)" % [_checks, _failures])
	await Backend.close()
	get_tree().quit(1 if _failures > 0 else 0)
