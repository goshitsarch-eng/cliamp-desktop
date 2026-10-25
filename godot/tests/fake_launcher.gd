class_name FakeLauncher
extends RefCounted
## Scripted cliamp. `on_command` may take over a process (return true) or leave
## it to the default behavior, which matches an engine that is already running.

var commands: Array = []
var event_procs: Array = []
var spectrum_procs: Array = []
var daemons: Array = []
var on_command: Callable
var state_reads := 0


static func envelope(fields: Dictionary) -> Dictionary:
	var out := {"version": 2, "ok": true}
	out.merge(fields, true)
	return out


func make_backend(options := {}) -> Node:
	var backend: Node = load("res://autoload/backend.gd").new()
	backend.executable = options.get("executable", "/test/cliamp")
	backend.command_timeout = options.get("command_timeout", 1.0)
	backend.startup_timeout = options.get("startup_timeout", 1.0)
	backend.shutdown_timeout = options.get("shutdown_timeout", 0.05)
	backend.refresh_interval = 3600.0
	backend.reconnect_delay = 0.005
	var launcher := self
	backend.proc_factory = func() -> Object:
		var p := FakeProc.new()
		p.launcher = launcher
		return p
	return backend


func dispatch(proc: FakeProc) -> void:
	var args := proc.args
	commands.append(Array(args))
	if on_command.is_valid() and on_command.call(proc):
		return
	if args[0] == "--daemon":
		daemons.append(proc)
	elif args[0] == "visstream":
		spectrum_procs.append(proc)
	elif args.size() > 1 and args[1] == "events":
		event_procs.append(proc)
	elif args.size() > 1 and args[1] == "state":
		state_reads += 1
		proc.finish_json(envelope({"snapshot": {"state": "stopped", "revision": state_reads, "playlist_revision": 2, "index": -1}}))
	elif args.size() > 1 and args[1] == "capabilities":
		proc.finish_json(envelope({"result": [{"name": "play", "description": "Start playback"}]}))
	else:
		if args.has("desktop.quit"):
			for d: FakeProc in daemons:
				d.finish()
		proc.finish_json(envelope({"job": {"id": "job-1", "state": "succeeded", "result": {"ok": true, "items": ["done"]}, "snapshot": {"state": "playing", "revision": 9}}}))


func count_commands(arg: String) -> int:
	var n := 0
	for c: Array in commands:
		if c.has(arg):
			n += 1
	return n
