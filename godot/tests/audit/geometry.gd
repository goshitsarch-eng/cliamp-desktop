extends AuditKit

func run() -> void:
	var win := get_window()
	check(win.min_size == Prefs.MIN_SIZE and Prefs.ui_scale == 1.0, "ill-typed saved values fall back safely")
	await set_size(1180, 770)
	Prefs.save()
	var before := ConfigFile.new()
	check(before.load(Prefs.PATH) == OK, "windowed preferences are readable")
	var normal: Variant = before.get_value("window", "size")
	var position: Variant = before.get_value("window", "position")
	check(normal == win.size and position == win.position, "saved normal rectangle matches the visible window")
	win.mode = Window.MODE_MAXIMIZED
	for i in 80:
		if win.mode == Window.MODE_MAXIMIZED:
			break
		await wait(0.1)
	check(win.mode == Window.MODE_MAXIMIZED, "window manager entered maximized mode")
	print("geometry before ", normal, " at ", position, " live mode ", win.mode, " size ", win.size, " at ", win.position)
	Prefs.save()
	var cfg := ConfigFile.new()
	cfg.load(Prefs.PATH)
	check(cfg.get_value("window", "size") == normal, "maximized save retains normal size")
	check(cfg.get_value("window", "position") == position, "maximized save retains normal position")
	win.mode = Window.MODE_WINDOWED
	await wait(0.4)
