extends Node
## Controls cliamp through its portable CLI V2 client. Attaches to an existing
## player, or owns a headless child when there is none to attach to. Commands
## are argument arrays, so paths and provider input never pass through a shell.
## Submitted operations are never replayed automatically.
##
## Failures are returned, not thrown: a failed call returns {"error": {...}},
## see fail() and failed().

signal event_received(envelope: Dictionary)
signal spectrum_received(bands: PackedFloat32Array)
signal jobs_changed(jobs: Array)
## Emitted when the connection is lost. A runtime.state event follows a reconnect.
signal connection_lost(error: Dictionary)

const PROTOCOL_CODES := [
	"invalid_version", "invalid_request", "invalid_params", "unknown_operation",
	"not_found", "conflict", "unavailable", "canceled", "internal_error",
]
const EVENT_NAMES: PackedStringArray = [
	"runtime.state", "runtime.playback", "runtime.playlist", "runtime.settings",
	"runtime.job", "provider.auth",
]

var command_timeout := 15.0
var operation_timeout := 300.0
var startup_timeout := 15.0
var shutdown_timeout := 3.0
var refresh_interval := 1.0
var reconnect_delay := 1.0
## Replaced in tests by a factory that returns a fake with Proc's interface.
var proc_factory: Callable = func() -> Object: return Proc.new()

var executable := ""
var connected := false

var _closed := false
var _closing := false
var _generation := 0
var _connecting := false
var _refreshing := false
var _daemon: Object
var _daemon_exit := -1
var _daemon_log := ""
var _children: Array = []
var _event_proc: Object
var _spectrum_proc: Object
var _jobs: Dictionary = {}
var _job_updated: Dictionary = {}
var _auth_cancellable: Dictionary = {}
var _refresh_timer: Timer
var _reconnect_pending := false


static func fail(code: String, message: String) -> Dictionary:
	return {"error": {"code": code, "message": message}}


static func failed(result: Dictionary) -> bool:
	return result.has("error")


func _ready() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = refresh_interval
	_refresh_timer.timeout.connect(_refresh)
	add_child(_refresh_timer)


## Looks for the sidecar in the order CLIAMP_BINARY, macOS Resources, next to
## the app (when distinct from the GUI executable on case-insensitive volumes),
## then PATH.
func resolve_executable() -> String:
	if not executable.is_empty():
		return executable
	var configured := OS.get_environment("CLIAMP_BINARY")
	if not configured.is_empty():
		executable = configured
		return executable
	executable = pick_sidecar_path(OS.get_executable_path(), OS.get_name(), func(p: String) -> bool: return FileAccess.file_exists(p))
	return executable


static func pick_sidecar_path(exe_path: String, os_name: String, exists_fn: Callable) -> String:
	var file := "cliamp.exe" if os_name == "Windows" else "cliamp"
	var dir := exe_path.get_base_dir()
	if os_name == "macOS":
		var bundled := dir.get_base_dir().path_join("Resources").path_join(file)
		if exists_fn.call(bundled):
			return bundled
	var beside := dir.path_join(file)
	if beside.to_lower() != exe_path.to_lower() and exists_fn.call(beside):
		return beside
	return file


func connect_engine() -> Dictionary:
	if _closed:
		return fail("closed", "The player connection is closed.")
	if connected:
		return {}
	if _connecting:
		while _connecting:
			await get_tree().create_timer(0.05).timeout
		return {} if connected else fail("not_running", "cliamp is not running.")
	_connecting = true
	var result := await _connect()
	_connecting = false
	return result


func _connect() -> Dictionary:
	var current := await _read_snapshot()
	if failed(current) and current["error"]["code"] != "not_running":
		return current
	if failed(current):
		if _daemon == null or _daemon_exit != -1:
			_interrupt_active_jobs()
			_daemon_log = ""
			_daemon_exit = -1
			var daemon: Object = _spawn(PackedStringArray(["--daemon", "--no-startup-channels"]))
			if daemon == null:
				return fail("executable_unavailable", "Could not start cliamp (%s). Build the desktop bundle or set CLIAMP_BINARY to your cliamp executable." % resolve_executable())
			_daemon = daemon
			daemon.stdout_line.connect(func(line: String) -> void: _daemon_log = (_daemon_log + line + "\n").right(4096))
			daemon.exited.connect(func(code: int) -> void:
				if _daemon == daemon:
					_daemon_log = (_daemon_log + str(daemon.stderr_text)).right(4096)
					_daemon_exit = code)
		var deadline := Time.get_ticks_msec() + int(startup_timeout * 1000.0)
		while failed(current):
			if _closed:
				return fail("closed", "The player connection is closed.")
			var remaining := (deadline - Time.get_ticks_msec()) / 1000.0
			if remaining <= 0.0:
				if _daemon != null:
					_daemon.kill()
				return fail("startup_timeout", "cliamp did not become ready within %d seconds. %s" % [int(startup_timeout), _daemon_log.strip_edges()])
			current = await _read_snapshot(remaining)
			if not failed(current):
				break
			if current["error"]["code"] != "not_running":
				return current
			if _daemon_exit != -1:
				return fail("startup_failed", "cliamp exited before it was ready (exit %d). %s" % [_daemon_exit, _daemon_log.strip_edges()])
			await get_tree().create_timer(0.1).timeout
	if _closed:
		return fail("closed", "The player connection is closed.")
	connected = true
	_reconnect_pending = false
	_publish_snapshot(current["snapshot"])
	_start_streams()
	_refresh_timer.wait_time = refresh_interval
	_refresh_timer.start()
	return {}


func _publish_snapshot(snapshot: Dictionary) -> void:
	if not _closed:
		event_received.emit({"event": "runtime.state", "data": snapshot})


func _refresh() -> void:
	if _closed or not connected or _refreshing:
		return
	_refreshing = true
	var snap := await _read_snapshot()
	if failed(snap):
		_refreshing = false
		_schedule_reconnect(snap["error"])
		return
	_publish_snapshot(snap["snapshot"])
	for job: BackendJob in current_jobs():
		if _closed or not connected:
			break
		if not job.is_active() or Time.get_unix_time_from_system() - _job_updated.get(job.id, job.created_at) < 2.0:
			continue
		var response := await _command(["remote", "job", job.id])
		if not failed(response):
			if response.get("job") is Dictionary:
				_record_job(response["job"])
		elif response["error"]["code"] == "not_found":
			job.state = "interrupted"
			job.cancellable = false
			_publish_jobs()
		else:
			_refreshing = false
			_schedule_reconnect(response["error"])
			return
	_refreshing = false


func _stop_streams() -> void:
	_generation += 1
	for p: Object in [_event_proc, _spectrum_proc]:
		if p != null:
			p.kill()
	_event_proc = null
	_spectrum_proc = null
	if _refresh_timer != null:
		_refresh_timer.stop()


func _start_streams() -> void:
	_stop_streams()
	_watch_stream(false, _generation)
	_watch_stream(true, _generation)


func _watch_stream(bands: bool, generation: int) -> void:
	var args := PackedStringArray(["visstream", "--fps", "30"]) if bands else PackedStringArray(["remote", "events"] + Array(EVENT_NAMES))
	var proc: Object = _spawn(args)
	if proc == null:
		_schedule_reconnect(fail("executable_unavailable", "Could not start cliamp.")["error"])
		return
	if bands:
		_spectrum_proc = proc
	else:
		_event_proc = proc
	proc.stdout_line.connect(func(line: String) -> void:
		if _closed or generation != _generation:
			return
		var envelope := _decode_object(line)
		if envelope.is_empty():
			return
		if bands:
			_on_spectrum_line(envelope)
		else:
			_on_event_line(envelope))
	proc.exited.connect(func(_code: int) -> void:
		if not _closed and generation == _generation:
			_schedule_reconnect(fail("disconnected", "The player %s connection closed. %s" % ["spectrum" if bands else "event", str(proc.stderr_text).strip_edges()])["error"]))


func _on_spectrum_line(envelope: Dictionary) -> void:
	var values = envelope.get("bands")
	if values is Array:
		var out := PackedFloat32Array()
		for v in values:
			if not (v is float or v is int):
				return
			out.append(v)
		spectrum_received.emit(out)


func _on_event_line(envelope: Dictionary) -> void:
	var name := str(envelope.get("event", ""))
	if name == "system.overflow":
		_schedule_reconnect(fail("resync_required", "The player event stream overflowed; refreshing state.")["error"])
		return
	var data = envelope.get("data")
	if name == "runtime.job" and data is Dictionary:
		var job = data.get("job", data)
		if job is Dictionary and _jobs.has(job.get("id")):
			_record_job(job)
	elif name == "provider.auth" and data is Dictionary and data.get("auth") is Dictionary:
		var auth: Dictionary = data["auth"]
		if auth.get("provider") is String and auth.get("cancellable") is bool:
			_auth_cancellable[auth["provider"]] = auth["cancellable"]
			for job: BackendJob in _jobs.values():
				if job.is_active() and job.provider == auth["provider"]:
					job.cancellable = auth["cancellable"]
			_publish_jobs()
	event_received.emit(envelope)


func _schedule_reconnect(error: Dictionary) -> void:
	if _closed or _reconnect_pending:
		return
	_reconnect_pending = true
	connected = false
	_stop_streams()
	connection_lost.emit(error)
	await get_tree().create_timer(reconnect_delay).timeout
	if _closed:
		return
	_reconnect_pending = false
	# connect reads authoritative state before it opens new subscriptions.
	var result := await connect_engine()
	if failed(result):
		_schedule_reconnect(result["error"])


## Starts a child cliamp process, or returns null when it cannot start.
func _spawn(arguments: PackedStringArray) -> Object:
	var proc: Object = proc_factory.call()
	if not proc.start(resolve_executable(), arguments):
		return null
	_children.append(proc)
	proc.exited.connect(func(_c: int) -> void: _children.erase(proc))
	return proc


## Runs one command and returns the decoded JSON response.
## `input` is one JSON line written to stdin. `private_errors` hides output that
## could echo provider credentials or plugin content.
func _command(arguments: Array, timeout := -1.0, input := "", require_v2 := true, private_errors := false, allow_closed := false) -> Dictionary:
	if _closed and not allow_closed:
		return fail("closed", "The player connection is closed.")
	if timeout < 0.0:
		timeout = command_timeout
	var proc: Object = _spawn(PackedStringArray(arguments))
	if proc == null:
		return fail("executable_unavailable", "Could not start cliamp (%s). Build the desktop bundle or set CLIAMP_BINARY to your cliamp executable." % resolve_executable())
	var state := {"out": PackedStringArray(), "done": false, "code": 0}
	proc.stdout_line.connect(func(line: String) -> void: state["out"].append(line))
	proc.exited.connect(func(code: int) -> void:
		state["code"] = code
		state["done"] = true)
	if not input.is_empty():
		proc.write_line(input)
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while not state["done"]:
		if Time.get_ticks_msec() > deadline:
			proc.kill()
			if private_errors:
				return fail("timeout", "The operation timed out. Check the saved settings before trying again.")
			return fail("timeout", "The cliamp command timed out. An accepted operation may still finish in the player; refresh its state before trying again.")
		await get_tree().create_timer(0.02).timeout
	var stdout := "\n".join(state["out"]).strip_edges()
	var stderr := str(proc.stderr_text).strip_edges()
	if state["code"] != 0:
		if private_errors:
			return fail("setup_failed", "The operation could not complete. Check the required fields and try again.")
		var detail := stderr if not stderr.is_empty() else stdout
		var not_running := detail.contains("cliamp is not running") or detail.contains("no socket at")
		return fail("not_running" if not_running else _protocol_code(detail), detail if not detail.is_empty() else "cliamp exited with status %d." % state["code"])
	var response := _decode_object(stdout)
	if response.is_empty():
		return fail("invalid_response", "cliamp returned malformed JSON.")
	if require_v2 and response.get("version") != 2:
		return fail("invalid_version", "cliamp returned an unsupported IPC version.")
	if response.get("ok") != true:
		if private_errors:
			return fail("setup_failed", "The operation could not complete. Check the required fields and try again.")
		return _protocol_error(response.get("error"), "Operation failed.")
	return response


## JSON text for the engine. Godot parses every number as a float, so a value
## such as a playlist revision would be written as 7.0, which Go refuses for an
## integer field. Whole floats are written as integers; Go accepts those for
## float fields too.
static func encode_json(value: Variant) -> String:
	return JSON.stringify(_whole_numbers(value))


static func _whole_numbers(value: Variant) -> Variant:
	if value is float:
		var f: float = value
		if is_finite(f) and f == floorf(f) and absf(f) < 9.0e15:
			return int(f)
		return f
	if value is Dictionary:
		var out := {}
		for key in value:
			out[key] = _whole_numbers(value[key])
		return out
	if value is Array:
		var out := []
		for item in value:
			out.append(_whole_numbers(item))
		return out
	return value


static func _protocol_code(detail: String) -> String:
	var re := RegEx.create_from_string("\\((" + "|".join(PROTOCOL_CODES) + ")\\)")
	var m := re.search(detail)
	return m.get_string(1) if m != null else "command_failed"


static func _protocol_error(error: Variant, fallback: String) -> Dictionary:
	if error is Dictionary:
		var detail = error.get("detail")
		var message := str(error.get("message", fallback))
		if detail is String and not detail.is_empty():
			message += ": " + detail
		return fail(str(error.get("code", "operation_failed")), message)
	return fail("operation_failed", error if error is String else fallback)


static func _decode_object(source: String) -> Dictionary:
	var parsed = JSON.parse_string(source)
	return parsed if parsed is Dictionary else {}


func _read_snapshot(timeout := -1.0) -> Dictionary:
	var response := await _command(["remote", "state"], timeout)
	if failed(response):
		return response
	if not (response.get("snapshot") is Dictionary):
		return fail("invalid_response", "cliamp returned no runtime snapshot.")
	return response


func snapshot() -> Dictionary:
	var c := await connect_engine()
	if failed(c):
		return c
	var response := await _read_snapshot()
	return response if failed(response) else response["snapshot"]


func capabilities() -> Dictionary:
	var c := await connect_engine()
	if failed(c):
		return c
	var response := await _command(["remote", "capabilities"])
	if failed(response):
		return response
	var result = response.get("result")
	if result is Array:
		return {"operations": result}
	if result is Dictionary:
		return result
	return fail("invalid_response", "cliamp returned no capabilities.")


func read_frame(width: int, height: int) -> Dictionary:
	var c := await connect_engine()
	if failed(c):
		return c
	var response := await _command(["remote", "frame", "--width", str(width), "--height", str(height)])
	if failed(response):
		return response
	if not (response.get("result") is Dictionary):
		return fail("invalid_response", "cliamp returned no visualizer frame.")
	return response["result"]


## Submits an operation and waits for its job to finish.
func call_op(operation: String, params := {}, track_job := true) -> Dictionary:
	var c := await connect_engine()
	if failed(c):
		return c
	var deadline := Time.get_ticks_msec() + int(operation_timeout * 1000.0)
	var encoded := encode_json(params)
	var temp_path := ""
	var call_args := ["remote", "call", "--params", encoded, operation]
	if encoded.length() > 8192:
		var temp := FileAccess.create_temp(FileAccess.WRITE, "cliamp-params", "json", true)
		if temp != null:
			temp_path = temp.get_path_absolute()
			temp.store_string(encoded)
			temp.flush()
			temp.close()
			call_args = ["remote", "call", "--params-file", temp_path, operation]
	var response := await _command(call_args)
	if not temp_path.is_empty():
		DirAccess.remove_absolute(temp_path)
	while true:
		if failed(response):
			return response
		var job = response.get("job")
		if not (job is Dictionary) or not (job.get("id") is String):
			return fail("invalid_response", "cliamp returned no operation job.")
		var state := str(job.get("state"))
		if track_job:
			_record_job(job, operation, str(params.get("provider", "")) if operation == "provider.auth" else "")
		if state == "succeeded" or state == "failed" or state == "canceled":
			if job.get("snapshot") is Dictionary:
				_publish_snapshot(job["snapshot"])
			if state != "succeeded":
				return _protocol_error(job.get("error"), "Operation %s." % state)
			var result = job.get("result")
			if result == null:
				return {}
			if not (result is Dictionary):
				return fail("invalid_response", "cliamp returned an invalid job result.")
			if result.get("ok") == false:
				return _protocol_error(result.get("error"), "Operation failed.")
			return result
		if state != "queued" and state != "running":
			return fail("invalid_response", "cliamp returned an unknown job state.")
		var remaining := (deadline - Time.get_ticks_msec()) / 1000.0
		if remaining <= 0.0:
			return fail("timeout", "%s is still running (job %s). Refresh its state before trying again." % [operation, job["id"]])
		await get_tree().create_timer(0.1).timeout
		if _closed:
			return fail("closed", "The player connection is closed.")
		response = await _command(["remote", "job", job["id"]], minf(remaining, command_timeout))
	return {}


# Provider setup, preferences and plugins take one JSON line on stdin.

func setup_schema(provider: String, values := {}) -> Dictionary:
	return await _setup("schema", provider, values)


func save_provider(provider: String, values: Dictionary, verify_connection := true) -> Dictionary:
	return await _setup("apply", provider, values, verify_connection)


func _setup(command: String, provider: String, values: Dictionary, verify_connection := true) -> Dictionary:
	var args := ["setup", command]
	if not provider.is_empty():
		args.append_array(["--provider", provider])
	if command == "apply" and not verify_connection:
		args.append("--save-without-check")
	return await _command(args, operation_timeout if command == "apply" else command_timeout, encode_json(values), false, true)


func preferences_schema() -> Dictionary:
	return await _management(["preferences", "schema"])


func save_preferences(values: Dictionary) -> Dictionary:
	var result := await _management(["preferences", "apply"], values)
	# An attached terminal saves its theme on exit. Apply a changed theme to that
	# shared renderer so its exit cannot overwrite this edit.
	if not failed(result) and values.has("theme"):
		var applied := await call_op("desktop.theme", {"name": values["theme"]})
		if failed(applied):
			return fail("theme_sync_failed", "Preferences were saved, but the running player could not apply the theme. Keep the player open and retry, or restart it and reapply the theme.")
	return result


func plugin_action(action: String, values := {}) -> Dictionary:
	if not action in ["list", "prepare", "review", "apply", "trust", "remove", "configure"]:
		return fail("invalid_request", "Unknown plugin management action.")
	return await _management(["plugins", "desktop", action], values, action == "prepare")


func _management(arguments: Array, values = null, slow := false) -> Dictionary:
	var input := "" if values == null else encode_json(values)
	var result := await _command(arguments, operation_timeout if slow else command_timeout, input, false, true)
	if failed(result) and not result["error"]["code"] in ["closed", "executable_unavailable"]:
		return fail("management_failed", "The settings or plugin operation could not complete. Check the requested changes and try again.")
	return result


# Jobs

func current_jobs() -> Array:
	var values := _jobs.values()
	values.sort_custom(func(a: BackendJob, b: BackendJob) -> bool: return a.created_at > b.created_at)
	return values


func _publish_jobs() -> void:
	if not _closed:
		jobs_changed.emit(current_jobs())


func _interrupt_active_jobs() -> void:
	for job: BackendJob in _jobs.values():
		if job.is_active():
			job.state = "interrupted"
			job.cancellable = false
	_publish_jobs()


func _record_job(raw: Dictionary, operation := "", provider := "") -> void:
	var id = raw.get("id")
	if not (id is String):
		return
	var previous: BackendJob = _jobs.get(id)
	var name := operation
	if name.is_empty():
		name = str(raw.get("operation", previous.operation if previous != null else "operation"))
	# These are continuous UI reads, not user-started background work.
	if name == "desktop.vis.frame" or name == "provider.auth.status":
		return
	var state := str(raw.get("state", "running"))
	var active := state == "queued" or state == "running"
	if previous != null and not previous.is_active() and active:
		return
	var job := BackendJob.new()
	job.id = id
	job.state = state
	job.provider = provider if not provider.is_empty() else (previous.provider if previous != null else "")
	job.operation = name if RegEx.create_from_string("^[a-zA-Z0-9_.-]+$").search(name) != null else "operation"
	var now := Time.get_unix_time_from_system()
	job.created_at = BackendJob.parse_time(raw.get("created_at"), previous.created_at if previous != null else now)
	job.finished_at = 0.0 if active else BackendJob.parse_time(raw.get("finished_at"), now)
	job.cancellable = active and _auth_cancellable.get(job.provider, true)
	_jobs[id] = job
	_job_updated[id] = now
	var finished: Array = current_jobs().filter(func(j: BackendJob) -> bool: return not j.is_active())
	for old: BackendJob in finished.slice(30):
		_jobs.erase(old.id)
		_job_updated.erase(old.id)
	_publish_jobs()


func cancel_job(job_id: String) -> Dictionary:
	var job: BackendJob = _jobs.get(job_id)
	if job == null or not job.is_active():
		return {}
	if not job.cancellable:
		return fail("unavailable", "This provider cannot stop its sign-in flow. Finish or close the provider sign-in window.")
	if job.cancellation_requested:
		return {}
	job.cancellation_requested = true
	_publish_jobs()
	var c := await connect_engine()
	var response := c if failed(c) else await _command(["remote", "cancel", job_id])
	job.cancellation_requested = false
	if not failed(response) and response.get("job") is Dictionary:
		_record_job(response["job"])
	_publish_jobs()
	return response


# Lifecycle

func owns_daemon() -> bool:
	return not _closed and _daemon != null and _daemon_exit == -1 and _daemon in _children


func restart_owned_engine() -> Dictionary:
	if _closed:
		return fail("closed", "The player connection is closed.")
	if not owns_daemon():
		return fail("not_owned", "This player was started elsewhere. Restart it there to load the new provider settings.")
	var preserved := await _capture_runtime_state() if connected else {}
	connected = false
	_reconnect_pending = false
	_stop_streams()
	var stopped := await _stop_owned_daemon()
	if failed(stopped):
		return stopped
	_connecting = true
	var result := await _connect()
	_connecting = false
	if not failed(result) and not preserved.is_empty():
		await _restore_runtime_state(preserved)
	return result


func _capture_runtime_state() -> Dictionary:
	for attempt in 2:
		var snap := await _read_snapshot()
		if failed(snap):
			return {}
		var state: Dictionary = snap["snapshot"]
		var rev: Variant = state.get("playlist_revision")
		var queue := await _read_all_tracks("queue.list")
		var playnext := await _read_all_tracks("playnext.list")
		if queue.is_empty() and playnext.is_empty():
			return {"snapshot": state, "queue": queue, "playnext": playnext}
		var verify := await _read_snapshot()
		if failed(verify) or verify["snapshot"].get("playlist_revision") == rev:
			return {"snapshot": verify["snapshot"] if not failed(verify) else state, "queue": queue, "playnext": playnext}
	return {}


func _read_all_tracks(operation: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var offset := 0
	while true:
		var page := await call_op(operation, {"offset": offset, "limit": 200}, false)
		if failed(page):
			break
		var rows := Util.objects(page.get("tracks"))
		if rows.is_empty():
			break
		out.append_array(rows)
		offset += rows.size()
		var total: Variant = page.get("total")
		if total is int or total is float:
			if offset >= int(total):
				break
		elif rows.size() < 200:
			break
	return out


func _restore_runtime_state(preserved: Dictionary) -> void:
	var state: Dictionary = Util.object(preserved.get("snapshot"))
	var queue: Array = preserved.get("queue", [])
	var playnext: Array = preserved.get("playnext", [])
	var cur := await _read_snapshot()
	if failed(cur):
		return
	var cur_snap: Dictionary = cur["snapshot"]
	var repeat_mode := Util.text(state.get("repeat")).to_lower()
	if not repeat_mode.is_empty() and repeat_mode != Util.text(cur_snap.get("repeat")).to_lower():
		await call_op("repeat", {"name": repeat_mode}, false)
	if state.get("shuffle") is bool and state.get("shuffle") != cur_snap.get("shuffle"):
		await call_op("shuffle", {"name": "on" if state["shuffle"] else "off"}, false)
	if not queue.is_empty():
		var idx := clampi(int(Util.number(state.get("index"), 0)), 0, queue.size() - 1)
		cur = await _read_snapshot()
		if failed(cur):
			return
		var rev: Variant = cur["snapshot"].get("playlist_revision", 0)
		var first := queue.slice(0, 1000)
		var replaced := await call_op("tracks.replace", {
			"tracks": first,
			"play": false,
			"index": mini(idx, first.size() - 1),
			"if_revision": rev,
		}, false)
		if failed(replaced):
			return
		var offset := 1000
		while offset < queue.size():
			cur = await _read_snapshot()
			if failed(cur):
				return
			var appended := await call_op("tracks.append", {
				"tracks": queue.slice(offset, offset + 1000),
				"play": false,
				"if_revision": cur["snapshot"].get("playlist_revision", 0),
			}, false)
			if failed(appended):
				return
			offset += 1000
		for entry in playnext:
			if entry is Dictionary and (entry.get("index") is int or entry.get("index") is float):
				var q_idx := int(entry["index"])
				if q_idx >= 0 and q_idx < queue.size():
					cur = await _read_snapshot()
					if failed(cur):
						break
					await call_op("queue.enqueue", {"index": q_idx, "if_revision": cur["snapshot"].get("playlist_revision", 0)}, false)
		var prev_state := Util.text(state.get("state"), "stopped")
		if prev_state == "playing" or prev_state == "paused":
			cur = await _read_snapshot()
			if not failed(cur):
				var played := await call_op("queue.play", {"index": idx, "if_revision": cur["snapshot"].get("playlist_revision", 0)}, false)
				if not failed(played):
					if prev_state == "paused":
						await call_op("pause", {}, false)
					var pos := Util.number(state.get("position"))
					if pos > 0.5 and state.get("seekable") == true:
						await call_op("seek.absolute", {"value": pos}, false)
	var final_snap := await _read_snapshot()
	if not failed(final_snap):
		_publish_snapshot(final_snap["snapshot"])


func _stop_owned_daemon() -> Dictionary:
	var daemon := _daemon
	if daemon == null or _daemon_exit != -1 or not daemon in _children:
		return {}
	# Submit only: polling the quit job races with the socket shutting down.
	# Wait on our own process handle for the normal exit save.
	await _command(["remote", "call", "desktop.quit"], shutdown_timeout, "", true, false, true)
	if await _wait_exit(daemon, shutdown_timeout):
		_daemon = null
		_daemon_exit = -1
		return {}
	daemon.kill()
	if await _wait_exit(daemon, shutdown_timeout):
		_daemon = null
		_daemon_exit = -1
		return {}
	return fail("shutdown_failed", "The owned player could not be stopped. Close it before restarting.")


func _wait_exit(proc: Object, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while proc in _children:
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().create_timer(0.02).timeout
	return true


## Stops only children this adapter started. An already running cliamp is never
## owned or terminated here. Safe to call more than once; every call returns
## after the first one finishes.
func close() -> void:
	if _closing:
		while _closing:
			await get_tree().create_timer(0.01).timeout
		return
	if _closed:
		return
	_closing = true
	_closed = true
	connected = false
	_refresh_timer.stop()
	_stop_streams()
	# The IPC quit lets the engine run its exit save, which a plain kill skips on Windows.
	await _stop_owned_daemon()
	for child: Object in _children.duplicate():
		child.kill()
	_closing = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for child: Object in _children:
			child.kill()
