extends Node
## Windowed only (not headless): opens the real shell against a real cliamp and
## saves a PNG of every page to the folder in SHOT_DIR.

func _ready() -> void:
	var dir := OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(dir)
	var main: Control = load("res://ui/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(4.0).timeout
	var wav := OS.get_environment("SHOT_WAV")
	if not wav.is_empty():
		await Store.run("sources.load", {"args": [wav], "name": "replace", "play": true, "if_revision": Store.state.get("playlist_revision", 0)})
		await get_tree().create_timer(1.5).timeout
	var only := OS.get_environment("SHOT_PAGES")
	for page: Dictionary in Pages.LIST:
		if not only.is_empty() and not only.split(",").has(page["id"]):
			continue
		Store.navigate(page["id"])
		await get_tree().create_timer(2.0).timeout
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png(dir.path_join(page["id"] + ".png"))
	await Backend.close()
	get_tree().quit()
