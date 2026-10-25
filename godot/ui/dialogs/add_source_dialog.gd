class_name AddSourceDialog
extends RefCounted
## "Add your music": files, folders, or typed sources, added to or replacing the
## queue. After a successful load the shell navigates to the queue.


## Returns true when sources were loaded.
static func run(host: Node) -> bool:
	if not Store.connected:
		return false
	var picked := await _ask(host)
	var paths: PackedStringArray = picked["paths"]
	if paths.is_empty():
		return false
	var mode: String = picked["mode"]
	if mode == "replace" and Util.number(Store.state.get("total")) > 0:
		var ok := await Dialogs.confirm(host, "Replace the queue?",
			"The selected sources will replace the current queue after they load successfully.", "Replace")
		if not ok:
			return false
	if Store.supports("sources.load"):
		var params := {
			"args": Array(paths),
			"name": mode,
			"play": mode == "replace",
			"if_revision": Store.state.get("playlist_revision", 0),
		}
		if await Store.run("sources.load", params) == null:
			return false
	else:
		for path in paths:
			if await Store.run("url.load", {"path": path}) == null:
				return false
	Store.navigate("queue")
	return true


## Shows the dialog until the user has chosen sources or cancelled.
static func _ask(host: Node) -> Dictionary:
	var mode := "append"
	var typed := [""]
	var error_text := ""
	var none := {"paths": PackedStringArray(), "mode": mode}
	while true:
		var action := [""]
		var content := _build(mode, typed[0], error_text, action)
		var chosen: Variant = await Dialogs.open(host, "Add your music", content["box"], ["Continue", "Cancel"], Vector2i(500, 0))
		mode = content["mode"][0]
		typed[0] = content["edit"].text if is_instance_valid(content["edit"]) else typed[0]
		if action[0] == "files" or action[0] == "folders":
			var found := await Dialogs.pick_paths(
				DisplayServer.FILE_DIALOG_MODE_OPEN_FILES if action[0] == "files" else DisplayServer.FILE_DIALOG_MODE_OPEN_DIR,
				"Choose files" if action[0] == "files" else "Choose folders")
			if not found.is_empty():
				return {"paths": found, "mode": mode}
			error_text = ""
			continue
		if chosen == null:
			return none
		var lines := PackedStringArray()
		for line in typed[0].split("\n"):
			if not line.strip_edges().is_empty():
				lines.append(line.strip_edges())
		if lines.is_empty():
			error_text = "Enter a file, folder, playlist, or URL."
			continue
		return {"paths": lines, "mode": mode}
	return none


static func _build(mode: String, text: String, error_text: String, action: Array) -> Dictionary:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 14)
	var mode_ref := [mode]
	var modes := HBoxContainer.new()
	var group := ButtonGroup.new()
	for entry: Array in [["append", "Add to queue", "playlist_add"], ["replace", "Replace queue", "queue_music"]]:
		var b := Button.new()
		b.text = "  " + entry[1]
		b.toggle_mode = true
		b.button_group = group
		b.button_pressed = entry[0] == mode
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.accessibility_name = entry[1]
		b.pressed.connect(func() -> void: mode_ref[0] = entry[0])
		modes.add_child(b)
	box.add_child(modes)
	var pickers := HBoxContainer.new()
	pickers.add_theme_constant_override("separation", 12)
	for entry: Array in [["files", "Choose files", "audio_file"], ["folders", "Choose folders", "folder_open"]]:
		var b := Icons.button(entry[2], entry[1], Callable(), 18)
		b.text = ""
		b.flat = false
		b.pressed.connect(func() -> void:
			action[0] = entry[0]
			DialogUtil.accept(box))
		pickers.add_child(_labeled(b, entry[2], entry[1]))
	box.add_child(pickers)
	var label := Label.new()
	label.text = "File, folder, playlist, URL, or ssh:// path"
	box.add_child(label)
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, 110)
	edit.placeholder_text = "One source per line"
	edit.text = text
	edit.accessibility_name = "File, folder, playlist, URL, or ssh:// path"
	box.add_child(edit)
	var error := DialogUtil.error_label()
	error.text = error_text
	box.add_child(error)
	DialogUtil.focus(edit)
	return {"box": box, "edit": edit, "mode": mode_ref}


## A flat-less button with an icon and a text label inside it.
static func _labeled(button: Button, icon_name: String, text: String) -> Button:
	button.custom_minimum_size = Vector2(0, 40)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_child(Icons.label(icon_name, 18))
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	button.add_child(row)
	button.custom_minimum_size = Vector2(170, 40)
	return button
