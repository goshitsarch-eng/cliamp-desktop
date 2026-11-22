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
	dialog.dialog_hide_on_ok = false
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
		finish.call(String(action)))
	Util.host(host).add_child(dialog)
	dialog.popup_centered()
	var value: Variant = await result.finished
	# A caller can open another modal immediately. Let the native window finish
	# processing confirmation and restore focus before that next popup.
	await dialog.get_tree().process_frame
	if dialog.visible:
		dialog.hide()
	await dialog.get_tree().process_frame
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


static func _message_content(host: Node, text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420
	label.size.x = 420
	var max_height := clampf(host.get_window().size.y / Prefs.ui_scale - 140.0, 120.0, 460.0)
	if label.get_minimum_size().y <= max_height:
		return label
	label.free()
	var view := TextEdit.new()
	view.editable = false
	view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	view.text = text
	view.accessibility_name = "Message"
	view.custom_minimum_size = Vector2(420, max_height)
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return view


static func confirm(host: Node, title: String, message: String, action := "OK") -> bool:
	var chosen: Variant = await open(host, title, _message_content(host, message), [action, "Cancel"])
	return chosen == action


static func message(host: Node, title: String, text: String) -> void:
	await open(host, title, _message_content(host, text), ["Close"])


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
static func pick_paths(host: Node, mode: int, title: String, filters := PackedStringArray()) -> PackedStringArray:
	var picker := FileDialog.new()
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_DIR if mode == DisplayServer.FILE_DIALOG_MODE_OPEN_DIR else FileDialog.FILE_MODE_OPEN_FILES
	picker.title = title
	picker.filters = filters
	picker.use_native_dialog = true
	if picker.file_mode == FileDialog.FILE_MODE_OPEN_FILES:
		_enable_typed_file(picker)
	var result := Result.new()
	picker.files_selected.connect(func(paths: PackedStringArray) -> void: result.finished.emit(paths))
	picker.file_selected.connect(func(path: String) -> void: result.finished.emit(PackedStringArray([path])))
	picker.dir_selected.connect(func(path: String) -> void: result.finished.emit(PackedStringArray([path])))
	picker.canceled.connect(func() -> void: result.finished.emit(PackedStringArray()))
	host.get_window().add_child(picker)
	picker.popup_centered()
	var paths: PackedStringArray = await result.finished
	await picker.get_tree().process_frame
	picker.queue_free()
	return paths


## Godot's fallback multi-file dialog normally submits only the selected rows.
## A user editing its filename field takes precedence over the old selection.
static func _enable_typed_file(picker: FileDialog) -> void:
	var edit := picker.get_line_edit()
	var entered := [""]
	edit.text_changed.connect(func(value: String) -> void:
		entered[0] = value
		picker.deselect_all()
		var path := value if value.is_absolute_path() else picker.current_dir.path_join(value)
		picker.get_ok_button().disabled = not FileAccess.file_exists(path))
	var submit := func() -> void:
		if not picker.visible or edit.text.is_empty() or edit.text != entered[0]:
			return
		var path := edit.text if edit.text.is_absolute_path() else picker.current_dir.path_join(edit.text)
		if FileAccess.file_exists(path):
			picker.hide()
			picker.files_selected.emit(PackedStringArray([path]))
	edit.text_submitted.connect(func(_value: String) -> void: submit.call())
	picker.confirmed.connect(submit)
