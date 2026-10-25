extends Node
## Builds the lyrics, visualizer and equalizer pages without an engine and runs
## their lifecycle. Run: godot --headless --path godot res://tests/pages_smoke.tscn

func _ready() -> void:
	var failures := 0
	for id in ["lyrics", "visualizer", "equalizer"]:
		var script: Script = load(Pages.LIST[Pages.index_of(id)]["script"])
		var page: Page = script.new()
		add_child(page)
		page.size = Vector2(900, 600)
		page.activate()
		await get_tree().process_frame
		Store.accept_state({"track": {"title": "T", "path": "p"}, "eq_bands": [1, 2, 3], "lyrics_offset_ms": 250, "state": "playing"})
		await get_tree().process_frame
		page.deactivate()
		if page.has_method("restore_appearance"):
			await page.restore_appearance()
		page.queue_free()
	var view := AnsiView.new()
	add_child(view)
	view.size = Vector2(640, 400)
	view.set_frame("\u001b[31m#\u001b[0mab\n█")
	await get_tree().process_frame
	if view.grid_size().x < 10:
		failures += 1
	print("pages_smoke: %d failure(s)" % failures)
	get_tree().quit(failures)
