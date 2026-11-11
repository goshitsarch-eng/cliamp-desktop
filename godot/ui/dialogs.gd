class_name Dialogs
extends RefCounted
## Native-window dialogs (embed_subwindows is off). Each returns after the user
## chooses; `await` them. Pass any node in the scene tree as `host`.

## Resolves with the dialog's result. Used to await a dialog without polling.
class Result extends RefCounted:
	signal finished(value: Variant)


## Generic modal dialog around `content`. Resolves to the pressed button's text,
## or null when closed or cancelled. `buttons` are shown in order; the first one
## is the default and also confirms with Enter. The content is freed with the
## dialog unless `keep_content` is set, for callers that reopen it.
static func open(host: Node, title: String, content: Control, buttons: Array[String] = ["Close"], min_size := Vector2i(480, 0), keep_content := false) -> Variant:
	var dialog := ConfirmationDialog.new()
	dialog.title = Util.single_line(title)
	dialog.exclusive = true
	dialog.content_scale_factor = Prefs.ui_scale
	dialog.min_size = Vector2i(Vector2(min_size) * Prefs.ui_scale)
	dialog.get_ok_button().text = buttons[0]
	var cancel := dialog.get_cancel_button()
	if buttons.size() < 2:
		cancel.hide()
	else:
		cancel.text = buttons[buttons.size() - 1]
	dialog.add_child(content)
	_bound_wrapping_labels(content, float(min_size.x) - 40.0)
	var result := Result.new()
	var done := [false]
	var finish := func(value: Variant) -> void:
		if done[0]:
			return
		done[0] = true
		result.finished.emit(value)
	dialog.confirmed.connect(finish.bind(buttons[0]))
	dialog.canceled.connect(finish.bind(null))
	dialog.close_requested.connect(finish.bind(null))
	for i in range(1, buttons.size() - 1):
		dialog.add_button(buttons[i], false, buttons[i])
	dialog.custom_action.connect(func(action: StringName) -> void:
		finish.call(String(action))
		dialog.hide())
	Util.host(host).add_child(dialog)
	dialog.popup_centered()
	var value: Variant = await result.finished
	if keep_content:
		dialog.remove_child(content)
	dialog.queue_free()
	return value


## A wrapping Label with no minimum width reports the height of one word per line
## the first time the dialog is sized, which makes the window absurdly tall.
static func _bound_wrapping_labels(node: Node, width: float) -> void:
	if node is Label and (node as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
		var label := node as Label
		if label.custom_minimum_size.x <= 0.0:
			label.custom_minimum_size.x = maxf(width, 160.0)
	for child in node.get_children():
		_bound_wrapping_labels(child, width)


static func confirm(host: Node, title: String, message: String, action := "OK") -> bool:
	var label := Label.new()
	label.text = message
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	var chosen: Variant = await open(host, title, label, [action, "Cancel"])
	return chosen == action


static func message(host: Node, title: String, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	await open(host, title, label, ["Close"])


## Asks for one non-empty text value. Returns the trimmed text, or null.
static func prompt(host: Node, title: String, label_text: String, initial := "", hint := "", multiline := false, action := "Save", validator := Callable()) -> Variant:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(440, 0)
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var edit: Control
	if multiline:
		var t := TextEdit.new()
		t.custom_minimum_size = Vector2(0, 110)
		t.placeholder_text = hint
		t.text = initial
		edit = t
	else:
		var l := LineEdit.new()
		l.placeholder_text = hint
		l.text = initial
		edit = l
	edit.accessibility_name = label_text
	box.add_child(edit)
	var error := Label.new()
	error.add_theme_color_override("font_color", ThemeBuilder.palette.error)
	box.add_child(error)
	edit.call_deferred("grab_focus")
	while true:
		var chosen: Variant = await open(host, title, box, [action, "Cancel"], Vector2i(480, 0), true)
		if chosen == null:
			box.queue_free()
			return null
		var value: String = edit.text.strip_edges()
		var problem := "Enter a value to continue." if value.is_empty() else ""
		if problem.is_empty() and validator.is_valid():
			problem = validator.call(value)
		if problem.is_empty():
			box.queue_free()
			return value
		error.text = problem
	return null


## Native file picker. Returns the chosen paths, empty when cancelled.
## mode: DisplayServer.FILE_DIALOG_MODE_OPEN_FILES or ..._OPEN_DIR.
static func pick_paths(mode: int, title: String, filters := PackedStringArray()) -> PackedStringArray:
	var result := Result.new()
	DisplayServer.file_dialog_show(title, "", "", false, mode, filters,
		func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
			result.finished.emit(paths if ok else PackedStringArray()))
	return await result.finished
