class_name Proc
extends RefCounted
## One child process with line-based stdout. Reader threads hand data to the
## main thread with call_deferred, so signals always fire on the main thread.
## Tests replace this class with a fake that has the same signals and methods.

signal stdout_line(line: String)
signal exited(code: int)

var pid := -1
var stderr_text := ""
var running := false

var _stdio: FileAccess
var _stderr: FileAccess
var _out_thread: Thread
var _err_thread: Thread
var _mutex := Mutex.new()
var _proc_mutex := Mutex.new()
var _killed := false
var _eof_count := 0


## Returns false when the executable could not be started.
func start(executable: String, arguments: PackedStringArray) -> bool:
	var info := OS.execute_with_pipe(executable, escape_arguments(arguments))
	if info.is_empty():
		return false
	pid = info["pid"]
	_stdio = info["stdio"]
	_stderr = info["stderr"]
	running = true
	_out_thread = Thread.new()
	_err_thread = Thread.new()
	_out_thread.start(_read_stdout)
	_err_thread.start(_read_stderr)
	return true


## Godot wraps each argument in quotes on Windows without escaping inside it, so
## quotes and backslashes are escaped here for the CommandLineToArgvW rules that
## Go programs use to split the command line.
static func escape_arguments(arguments: PackedStringArray, windows := OS.get_name() == "Windows") -> PackedStringArray:
	if not windows:
		return arguments
	var out := PackedStringArray()
	for arg in arguments:
		out.append(windows_escape(arg))
	return out


static func _windows_quotes_arg(arg: String) -> bool:
	if arg.is_empty():
		return true
	for c in arg:
		if c == " " or c == "\t" or c == "\n" or c == "\u000b" or c == "\"":
			return true
	return false


static func windows_escape(arg: String) -> String:
	var out := ""
	var slashes := 0
	for c in arg:
		if c == "\\":
			slashes += 1
			continue
		if c == "\"":
			out += "\\".repeat(slashes * 2 + 1) + "\""
		else:
			out += "\\".repeat(slashes) + c
		slashes = 0
	# Trailing backslashes precede a closing quote only when Godot quotes arg.
	if _windows_quotes_arg(arg):
		return out + "\\".repeat(slashes * 2)
	return out + "\\".repeat(slashes)


## Sends one newline-terminated line. cliamp's JSON subcommands stop reading at
## the first newline, because a pipe's stdin cannot be closed on its own.
func write_line(text: String) -> void:
	if _stdio != null and _stdio.is_open():
		_stdio.store_string(text + "\n")
		_stdio.flush()


func kill() -> void:
	_proc_mutex.lock()
	if running and not _killed and pid > 0:
		_killed = true
		OS.kill(pid)
	_proc_mutex.unlock()


func _is_running() -> bool:
	_proc_mutex.lock()
	var alive := not _killed and pid > 0 and OS.is_process_running(pid)
	_proc_mutex.unlock()
	return alive


func _exit_code() -> int:
	_proc_mutex.lock()
	var code := -1 if _killed or pid <= 0 else OS.get_process_exit_code(pid)
	_proc_mutex.unlock()
	return code


func _read_stdout() -> void:
	while true:
		var line := _stdio.get_line()
		if line.length() > 0:
			stdout_line.emit.call_deferred(line.strip_edges(false, true))
		elif _stdio.get_error() != OK or not _is_running():
			break
	_thread_done()


func _read_stderr() -> void:
	while true:
		var chunk := _stderr.get_line()
		if chunk.length() > 0:
			_mutex.lock()
			stderr_text = (stderr_text + chunk + "\n").right(4096)
			_mutex.unlock()
		elif _stderr.get_error() != OK or not _is_running():
			break
	_thread_done()


func _thread_done() -> void:
	_mutex.lock()
	_eof_count += 1
	var both_done := _eof_count >= 2
	_mutex.unlock()
	if not both_done:
		return
	while _is_running():
		OS.delay_msec(10)
	var code := _exit_code()
	if OS.get_name() == "Windows":
		_proc_mutex.lock()
		if not _killed and pid > 0:
			OS.kill(pid)
		_proc_mutex.unlock()
	_finish.call_deferred(code)


func _finish(code: int) -> void:
	_out_thread.wait_to_finish()
	_err_thread.wait_to_finish()
	_stdio = null
	_stderr = null
	running = false
	exited.emit(code)
