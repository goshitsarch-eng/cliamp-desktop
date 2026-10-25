extends Node
## Port of desktop/test/backend_test.dart for the GDScript backend. Run:
##   godot --headless --path godot res://tests/backend_test.tscn
## Exits non-zero when any check fails.

var _failures := 0
var _checks := 0
var _current := ""


func _ready() -> void:
	for t: String in ["attach_existing", "own_daemon", "daemon_quit_unsupported", "daemon_quit_stalled", "daemon_quit_queued",
			"permission_error", "startup_failure_diagnostic", "startup_deadline", "capabilities_and_result",
			"polls_jobs_once", "conflict_not_retried", "hostile_path_single_argument", "overflow_resync",
			"auth_events", "spectrum_doubles", "command_timeout", "unsupported_version", "close_idempotent",
			"setup_via_stdin_only", "frame_without_jobs", "restart_refused_when_not_owned"]:
		_current = t
		await call(t)
	print("backend_test: %d checks, %d failure(s)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL [%s] %s" % [_current, what])


func eventually(cond: Callable, what: String) -> void:
	var end := Time.get_ticks_msec() + 2000
	while not cond.call():
		if Time.get_ticks_msec() > end:
			ok(false, "timed out: " + what)
			return
		await get_tree().create_timer(0.005).timeout
	ok(true, what)


func backend_for(launcher: FakeLauncher, options := {}) -> Node:
	var b := launcher.make_backend(options)
	add_child(b)
	return b


func not_running_when_no_daemon(launcher: FakeLauncher) -> Callable:
	return func(p: FakeProc) -> bool:
		if p.args.size() > 1 and p.args[1] == "state" and launcher.daemons.is_empty():
			p.fail("cliamp is not running (no socket at /tmp/x)")
			return true
		return false


func attach_existing() -> void:
	var l := FakeLauncher.new()
	var b := backend_for(l)
	var done := [0]
	var connect_once := func() -> void:
		await b.connect_engine()
		done[0] += 1
	connect_once.call()
	connect_once.call()
	await eventually(func() -> bool: return done[0] == 2, "both connects finished")
	await eventually(func() -> bool: return not l.event_procs.is_empty(), "event stream opened")
	ok(l.state_reads == 1, "one state read for concurrent connects")
	ok(l.daemons.is_empty(), "no daemon started")
	var snap: Dictionary = await b.snapshot()
	ok(snap.get("index") == -1, "snapshot decoded")
	await b.close()
	ok(l.count_commands("desktop.quit") == 0, "attached engine is not quit")
	ok(l.event_procs.all(func(p: FakeProc) -> bool: return p.killed), "event client killed")
	ok(l.spectrum_procs.all(func(p: FakeProc) -> bool: return p.killed), "spectrum client killed")
	b.queue_free()


func own_daemon() -> void:
	var l := FakeLauncher.new()
	l.on_command = not_running_when_no_daemon(l)
	var b := backend_for(l)
	var r: Dictionary = await b.connect_engine()
	ok(not Backend.failed(r), "connected")
	ok(l.daemons.size() == 1, "one daemon")
	var daemon_args: Array = l.commands.filter(func(c: Array) -> bool: return c.has("--daemon"))[0]
	ok(daemon_args == ["--daemon", "--no-startup-channels"], "daemon arguments")
	ok(not l.daemons[0].killed, "daemon alive")
	await b.close()
	await b.close()
	ok(not l.daemons[0].killed, "daemon stopped by quit, not killed")
	ok(l.count_commands("desktop.quit") == 1, "quit submitted once")
	b.queue_free()


func _daemon_shutdown(quit_proc_setup: Callable) -> void:
	var l := FakeLauncher.new()
	var quit_holder := [null]
	var base := not_running_when_no_daemon(l)
	l.on_command = func(p: FakeProc) -> bool:
		if base.call(p):
			return true
		if p.args.has("desktop.quit"):
			quit_holder[0] = p
			quit_proc_setup.call(p)
			return true
		return false
	var b := backend_for(l)
	await b.connect_engine()
	b.close()
	var during: Dictionary = await b.call_op("play")
	ok(during.get("error", {}).get("code") == "closed", "calls during close are refused")
	await eventually(func() -> bool: return l.daemons[0].killed, "daemon terminated by fallback")
	ok(l.count_commands("desktop.quit") == 1, "quit submitted once")
	b.queue_free()


func daemon_quit_unsupported() -> void:
	await _daemon_shutdown(func(p: FakeProc) -> void: p.fail("unknown operation: desktop.quit"))


func daemon_quit_stalled() -> void:
	await _daemon_shutdown(func(_p: FakeProc) -> void: pass)


func daemon_quit_queued() -> void:
	await _daemon_shutdown(func(p: FakeProc) -> void: p.finish_json(FakeLauncher.envelope({"job": {"id": "quit-job", "state": "queued"}})))


func permission_error() -> void:
	var l := FakeLauncher.new()
	l.on_command = func(p: FakeProc) -> bool:
		p.fail("connect: permission denied")
		return true
	var b := backend_for(l)
	var r: Dictionary = await b.connect_engine()
	ok(Backend.failed(r) and str(r["error"]["message"]).contains("permission denied"), "permission error surfaced")
	ok(l.daemons.is_empty(), "no second daemon")
	ok(l.commands.size() == 1, "one command")
	b.queue_free()


func startup_failure_diagnostic() -> void:
	var l := FakeLauncher.new()
	l.on_command = func(p: FakeProc) -> bool:
		if p.args[0] == "--daemon":
			p.fail("audio device could not open", 2)
		else:
			p.fail("cliamp is not running (no socket at /tmp/x)")
		return true
	var b := backend_for(l)
	var r: Dictionary = await b.connect_engine()
	ok(r.get("error", {}).get("code") == "startup_failed", "startup_failed code")
	ok(str(r.get("error", {}).get("message")).contains("audio device"), "daemon diagnostic kept (got %s)" % str(r))
	b.queue_free()


func startup_deadline() -> void:
	var l := FakeLauncher.new()
	l.on_command = func(p: FakeProc) -> bool:
		if p.args[0] == "--daemon":
			l.daemons.append(p)
		else:
			p.fail("cliamp is not running (no socket at /tmp/x)")
		return true
	var b := backend_for(l, {"startup_timeout": 0.05})
	var r: Dictionary = await b.connect_engine()
	ok(r.get("error", {}).get("code") == "startup_timeout", "startup_timeout code")
	ok(l.daemons[0].killed, "unready daemon terminated")
	b.queue_free()


func capabilities_and_result() -> void:
	var l := FakeLauncher.new()
	var b := backend_for(l)
	var received: Array = []
	b.event_received.connect(func(e: Dictionary) -> void: received.append(e))
	var caps: Dictionary = await b.capabilities()
	ok(caps["operations"][0]["name"] == "play", "capabilities unwrapped")
	var r: Dictionary = await b.call_op("play")
	ok(r == {"ok": true, "items": ["done"]}, "terminal result")
	await eventually(func() -> bool: return received.any(func(e: Dictionary) -> bool: return e.get("data", {}).get("revision") == 9), "job snapshot published")
	await b.close()
	b.queue_free()


func polls_jobs_once() -> void:
	var l := FakeLauncher.new()
	var polls := [0]
	l.on_command = func(p: FakeProc) -> bool:
		if p.args.size() < 2:
			return false
		if p.args[1] == "call" or p.args[1] == "job":
			if p.args[1] == "job":
				polls[0] += 1
			var state := "succeeded" if polls[0] == 2 else ("running" if polls[0] == 1 else "queued")
			var job := {"id": "slow-job", "state": state}
			if polls[0] == 2:
				job["result"] = {"ok": true, "total": 3}
			p.finish_json(FakeLauncher.envelope({"job": job}))
			return true
		return false
	var b := backend_for(l)
	var r: Dictionary = await b.call_op("provider.tracks", {"provider": "local"})
	ok(r.get("ok") == true and r.get("total") == 3, "result after polling (got %s)" % str(r))
	ok(polls[0] == 2, "two polls")
	ok(l.count_commands("call") == 1, "mutation submitted once")
	await b.close()
	b.queue_free()


func conflict_not_retried() -> void:
	var l := FakeLauncher.new()
	l.on_command = func(p: FakeProc) -> bool:
		if p.args.size() > 1 and p.args[1] == "call":
			p.finish_json(FakeLauncher.envelope({"job": {"id": "conflicted", "state": "failed", "error": {"code": "conflict", "message": "operation cannot be performed in the current state", "detail": "playlist revision changed"}}}))
			return true
		return false
	var b := backend_for(l)
	var r: Dictionary = await b.call_op("queue.remove", {"index": 0, "if_revision": 1})
	ok(r.get("error", {}).get("code") == "conflict", "conflict code")
	ok(str(r.get("error", {}).get("message")).contains("playlist revision changed"), "detail in message")
	ok(l.count_commands("call") == 1, "never retried")
	await b.close()
	b.queue_free()


func hostile_path_single_argument() -> void:
	var l := FakeLauncher.new()
	var b := backend_for(l, {"executable": "/opt/Player App/cliamp"})
	var path := "/music/a \"quoted\" song; $(touch nope).flac"
	await b.call_op("queue", {"path": path})
	var call: Array = l.commands.filter(func(c: Array) -> bool: return c.has("call"))[0]
	ok(call.size() == 5, "five arguments")
	ok(JSON.parse_string(call[3]) == {"path": path}, "params are one JSON argument")
	await b.close()
	b.queue_free()


func overflow_resync() -> void:
	var l := FakeLauncher.new()
	var b := backend_for(l)
	var received: Array = []
	var errors: Array = []
	b.event_received.connect(func(e: Dictionary) -> void: received.append(e))
	b.connection_lost.connect(func(e: Dictionary) -> void: errors.append(e))
	await b.connect_engine()
	await eventually(func() -> bool: return not l.event_procs.is_empty(), "event stream")
	l.event_procs[0].line({"event": "system.overflow", "data": {"resync_required": true}})
	await eventually(func() -> bool: return l.event_procs.size() == 2, "replacement stream")
	ok(errors.size() == 1, "connection loss reported")
	ok(l.event_procs[0].killed, "old stream killed")
	ok(received.back()["event"] == "runtime.state" and received.back()["data"]["revision"] == 2, "state read before reopening")
	var last_state := -1
	var last_events := -1
	for i in l.commands.size():
		if l.commands[i].has("state"):
			last_state = i
		if l.commands[i].has("events"):
			last_events = i
	ok(last_state < last_events, "resync before new subscription")
	await b.close()
	b.queue_free()


func auth_events() -> void:
	var l := FakeLauncher.new()
	var b := backend_for(l)
	var received: Array = []
	b.event_received.connect(func(e: Dictionary) -> void: received.append(e))
	await b.connect_engine()
	await eventually(func() -> bool: return not l.event_procs.is_empty(), "event stream")
	ok(l.commands.any(func(c: Array) -> bool: return c.has("events") and c.has("provider.auth")), "subscribed to provider.auth")
	var update := {"event": "provider.auth", "data": {"ok": true, "auth": {"provider": "spotify", "state": "authenticating", "url": "https://accounts.spotify.com/authorize?state=test"}}}
	l.event_procs[0].line(update)
	await eventually(func() -> bool: return received.any(func(e: Dictionary) -> bool: return e == update), "update forwarded")
	await b.close()
	b.queue_free()


func spectrum_doubles() -> void:
	var l := FakeLauncher.new()
	var b := backend_for(l)
	var got: Array = []
	b.spectrum_received.connect(func(v: PackedFloat32Array) -> void: got.append(v))
	await b.connect_engine()
	await eventually(func() -> bool: return not l.spectrum_procs.is_empty(), "spectrum stream")
	l.spectrum_procs[0].line({"ok": true, "bands": [0, 0.2, 1]})
	await eventually(func() -> bool: return not got.is_empty(), "frame received")
	ok(got[0] == PackedFloat32Array([0.0, 0.2, 1.0]), "bands as floats")
	await b.close()
	b.queue_free()


func command_timeout() -> void:
	var l := FakeLauncher.new()
	var hung := [null]
	l.on_command = func(p: FakeProc) -> bool:
		if p.args.size() > 1 and p.args[1] == "capabilities":
			hung[0] = p
			return true
		return false
	var b := backend_for(l, {"command_timeout": 0.05})
	var r: Dictionary = await b.capabilities()
	ok(r.get("error", {}).get("code") == "timeout", "timeout code")
	ok(hung[0].killed, "hung client killed")
	await b.close()
	b.queue_free()


func unsupported_version() -> void:
	var l := FakeLauncher.new()
	l.on_command = func(p: FakeProc) -> bool:
		p.finish_json({"version": 1, "ok": true})
		return true
	var b := backend_for(l)
	var r: Dictionary = await b.connect_engine()
	ok(r.get("error", {}).get("code") == "invalid_version", "invalid_version code")
	ok(l.daemons.is_empty(), "no daemon")
	b.queue_free()


func close_idempotent() -> void:
	var l := FakeLauncher.new()
	var b := backend_for(l)
	await b.close()
	await b.close()
	var r: Dictionary = await b.call_op("play")
	ok(r.get("error", {}).get("code") == "closed", "closed error")
	ok(l.commands.is_empty(), "no process started after close")
	b.queue_free()


func setup_via_stdin_only() -> void:
	var l := FakeLauncher.new()
	var seen := [null]
	l.on_command = func(p: FakeProc) -> bool:
		if p.args.size() > 1 and p.args[0] == "setup":
			seen[0] = p
			p.finish_json({"ok": true, "provider": "qobuz"})
			return true
		return false
	var b := backend_for(l)
	var r: Dictionary = await b.save_provider("qobuz", {"client_secret": "private-secret"}, false)
	ok(not Backend.failed(r), "apply succeeded")
	var proc: FakeProc = seen[0]
	ok(not " ".join(proc.args).contains("private-secret"), "secret not in arguments")
	ok(proc.input_lines.size() == 1 and proc.input_lines[0].contains("private-secret"), "secret on stdin")
	ok(proc.args.has("--save-without-check"), "save-without-check flag")
	await b.close()
	b.queue_free()


func frame_without_jobs() -> void:
	var l := FakeLauncher.new()
	l.on_command = func(p: FakeProc) -> bool:
		if p.args.size() > 1 and p.args[1] == "frame":
			p.finish_json(FakeLauncher.envelope({"result": {"text": "frame", "width": 3, "height": 1}}))
			return true
		return false
	var b := backend_for(l)
	var jobs: Array = []
	b.jobs_changed.connect(func(j: Array) -> void: jobs.append(j))
	var frame: Dictionary = await b.read_frame(3, 1)
	ok(frame.get("text") == "frame", "frame decoded")
	ok(jobs.is_empty() and b.current_jobs().is_empty(), "no job created")
	await b.close()
	b.queue_free()


func restart_refused_when_not_owned() -> void:
	var l := FakeLauncher.new()
	var b := backend_for(l)
	await b.connect_engine()
	var r: Dictionary = await b.restart_owned_engine()
	ok(r.get("error", {}).get("code") == "not_owned", "not_owned error")
	await b.close()
	b.queue_free()
