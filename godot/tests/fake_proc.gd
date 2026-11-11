class_name FakeProc
extends RefCounted
## Stands in for Proc in backend tests. The launcher decides how each command
## behaves; output and exit are delivered deferred, like the real reader threads.

signal stdout_line(line: String)
signal exited(code: int)

var stderr_text := ""
var running := false
var killed := false
var executable := ""
var args := PackedStringArray()
var input_lines: Array[String] = []
var launcher_ref: WeakRef


func start(exe: String, arguments: PackedStringArray) -> bool:
	executable = exe
	args = arguments
	running = true
	var l: FakeLauncher = launcher_ref.get_ref() if launcher_ref != null else null
	if l != null:
		l.dispatch(self)
	return true


func write_line(text: String) -> void:
	input_lines.append(text)


func kill() -> void:
	if running:
		killed = true
		finish("", "", -1)


## Emits `output` (one line), then exits with `code`.
func finish(output := "", error := "", code := 0) -> void:
	if not running:
		return
	running = false
	stderr_text = error
	if not output.is_empty():
		stdout_line.emit.call_deferred(output)
	exited.emit.call_deferred(code)


func finish_json(value: Dictionary) -> void:
	finish(JSON.stringify(value))


func fail(message: String, code := 1) -> void:
	finish("", message, code)


## A line on a long-running stream (events, spectrum).
func line(value: Dictionary) -> void:
	stdout_line.emit.call_deferred(JSON.stringify(value))


func has_arg(arg: String) -> bool:
	return args.has(arg)
