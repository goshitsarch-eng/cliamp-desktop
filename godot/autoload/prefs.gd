extends Node
## Window state and UI scale, persisted to user://window.ini. Saved on exit and
## periodically so the state survives a crash.

const PATH := "user://window.ini"
const MIN_SIZE := Vector2i(960, 600)
const SAVE_INTERVAL := 30.0

var ui_scale := 1.0
## Async callbacks the shell registers; awaited in order before the engine closes.
var before_close: Array[Callable] = []


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_restore()
	var timer := Timer.new()
	timer.wait_time = SAVE_INTERVAL
	timer.timeout.connect(save)
	add_child(timer)
	timer.start()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
		for hook in before_close:
			await hook.call()
		await Backend.close()
		get_tree().quit()


func set_ui_scale(value: float) -> void:
	ui_scale = clampf(value, 0.75, 2.0)
	_apply_scale()
	save()


func save() -> void:
	var win := get_window()
	var cfg := ConfigFile.new()
	cfg.set_value("window", "mode", win.mode)
	cfg.set_value("window", "screen", win.current_screen)
	if win.mode == Window.MODE_WINDOWED:
		cfg.set_value("window", "position", win.position)
		cfg.set_value("window", "size", win.size)
	cfg.set_value("ui", "scale", ui_scale)
	cfg.save(PATH)


func _restore() -> void:
	var cfg := ConfigFile.new()
	var win := get_window()
	if cfg.load(PATH) == OK:
		ui_scale = clampf(cfg.get_value("ui", "scale", 1.0), 0.75, 2.0)
		var screen: int = cfg.get_value("window", "screen", 0)
		win.current_screen = clampi(screen, 0, DisplayServer.get_screen_count() - 1)
		if cfg.has_section_key("window", "size"):
			win.size = cfg.get_value("window", "size")
		if cfg.has_section_key("window", "position"):
			win.position = _on_screen(cfg.get_value("window", "position"), win.size)
		win.mode = cfg.get_value("window", "mode", Window.MODE_WINDOWED)
	_apply_scale()


func _apply_scale() -> void:
	var win := get_window()
	win.content_scale_factor = ui_scale
	win.min_size = Vector2i(Vector2(MIN_SIZE) * ui_scale)


## Keeps a restored window inside a connected screen.
func _on_screen(pos: Vector2i, size: Vector2i) -> Vector2i:
	for i in DisplayServer.get_screen_count():
		var rect := Rect2i(DisplayServer.screen_get_position(i), DisplayServer.screen_get_size(i))
		if rect.intersects(Rect2i(pos, size)):
			return pos
	return DisplayServer.screen_get_position(0) + Vector2i(64, 64)
