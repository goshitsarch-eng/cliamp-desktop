extends AuditKit
## Every page at several window sizes: screenshot plus layout lint.

const SIZES := [Vector2i(960, 600), Vector2i(1280, 800), Vector2i(2200, 700), Vector2i(960, 1300), Vector2i(1920, 1080)]


func run() -> void:
	var wav := OS.get_environment("SHOT_WAV")
	if not wav.is_empty():
		await Store.run("sources.load", {"args": [wav], "name": "replace", "play": false, "if_revision": Store.state.get("playlist_revision", 0)})
		await wait(1.0)
	for size: Vector2i in SIZES:
		await set_size(size.x, size.y)
		for page: Dictionary in Pages.LIST:
			Store.navigate(page["id"])
			await wait(1.2)
			var tag := "%s@%dx%d" % [page["id"], size.x, size.y]
			lint(tag)
			await shot(tag)
	# Exercise the native window manager in addition to the requested client sizes.
	var win := get_window()
	var normal_size := win.size
	win.mode = Window.MODE_MAXIMIZED
	await wait(0.5)
	print("maximize ", win.mode, " ", win.size)
	await shot("maximized")
	win.mode = Window.MODE_WINDOWED
	await wait(0.5)
	print("restore ", win.mode, " ", win.size, " previous ", normal_size)
	win.size = Vector2i(20, 20)
	await wait(0.4)
	check(win.size.x >= win.min_size.x and win.size.y >= win.min_size.y, "minimum enforced")
