extends Node
## Drives the native-window dialogs by pressing their buttons.
##   godot --headless --path godot res://tests/dialogs_test.tscn

var _failures := 0
var _checks := 0


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("FAIL ", what)


func _ready() -> void:
	await get_tree().process_frame
	await _prompt()
	await _confirm()
	await _custom_content()
	await _seek()
	await _plugin_command()
	print("dialogs_test: %d checks, %d failure(s)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _dialog() -> ConfirmationDialog:
	for i in 100:
		for c in get_tree().root.get_children():
			if c is ConfirmationDialog and c.visible:
				return c
		await get_tree().process_frame
	return null


func _find(node: Node, type: String) -> Node:
	if node.get_class() == type:
		return node
	for c in node.get_children():
		var r := _find(c, type)
		if r != null:
			return r
	return null


func _prompt() -> void:
	var result := [null, false]
	var run := func() -> void:
		result[0] = await Dialogs.prompt(self, "Name", "Playlist name", "", "", false, "Create")
		result[1] = true
	run.call()
	var d := await _dialog()
	ok(d != null, "prompt opens a dialog")
	var edit := _find(d, "LineEdit") as LineEdit
	ok(edit != null, "prompt has a text field")
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(not result[1], "empty submit keeps asking")
	d = await _dialog()
	ok(d != null, "prompt reopens after an empty submit")
	edit = _find(d, "LineEdit") as LineEdit
	ok(edit != null and is_instance_valid(edit), "reopened content is still alive")
	edit.text = "  Road trip  "
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(result[1] and result[0] == "Road trip", "value is trimmed and returned (%s)" % str(result[0]))

	result[0] = null
	result[1] = false
	run.call()
	d = await _dialog()
	d.get_cancel_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(result[1] and result[0] == null, "cancel returns null")

	var validated := [null, false]
	var run_valid := func() -> void:
		validated[0] = await Dialogs.prompt(self, "Save", "Playlist name", "", "", false, "Save", LibraryLogic.playlist_name_error)
		validated[1] = true
	run_valid.call()
	d = await _dialog()
	edit = _find(d, "LineEdit") as LineEdit
	edit.text = "bad/name"
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(not validated[1], "validator rejects path separator in playlist name")
	d = await _dialog()
	edit = _find(d, "LineEdit") as LineEdit
	edit.text = "Good playlist"
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(validated[1] and validated[0] == "Good playlist", "validator accepts valid playlist name")


func _confirm() -> void:
	var result := [null]
	var run := func() -> void:
		result[0] = await Dialogs.confirm(self, "Replace?", "Really?", "Replace")
	run.call()
	var d := await _dialog()
	ok(d != null and d.get_ok_button().text == "Replace", "confirm shows its action")
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(result[0] == true, "confirm accepted")
	result[0] = null
	run.call()
	d = await _dialog()
	d.get_cancel_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(result[0] == false, "confirm cancelled")


func _custom_content() -> void:
	var result := [null]
	var label := Label.new()
	label.text = "content"
	var run := func() -> void:
		result[0] = await Dialogs.open(self, "Custom", label, ["Done"])
	run.call()
	var d := await _dialog()
	ok(d != null and not d.get_cancel_button().visible, "single-button dialog hides cancel")
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(result[0] == "Done", "open returns the pressed button")
	ok(not is_instance_valid(label) or label.is_queued_for_deletion(), "content is freed with the dialog")


func _seek() -> void:
	var result := [null, false]
	var run := func() -> void:
		result[0] = await SeekDialog.open(self, 10.0, 100.0)
		result[1] = true
	run.call()
	var d := await _dialog()
	ok(d != null, "seek dialog opens")
	var edit := _find(d, "LineEdit") as LineEdit
	ok(edit != null and edit.text == "0:10", "seek starts at the current position (%s)" % (edit.text if edit else ""))
	edit.text = "nonsense"
	edit.text_changed.emit(edit.text)
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(not result[1], "invalid time keeps the dialog going")
	d = await _dialog()
	edit = _find(d, "LineEdit") as LineEdit
	ok(edit != null and edit.text == "nonsense", "invalid input is kept for editing")
	edit.text = "2:00"
	edit.text_changed.emit(edit.text)
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(not result[1], "a time beyond the track is refused")
	d = await _dialog()
	edit = _find(d, "LineEdit") as LineEdit
	edit.text = "1:05"
	edit.text_changed.emit(edit.text)
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(result[1] and is_equal_approx(result[0], 65.0), "valid time returns seconds (%s)" % str(result[0]))


func _edits(d: Node) -> Array:
	var out: Array = []
	var walk := func(n: Node, self_ref: Callable) -> void:
		if n is LineEdit:
			out.append(n)
		for c in n.get_children():
			self_ref.call(c, self_ref)
	walk.call(d, walk)
	return out


func _plugin_command() -> void:
	var result := [null, false]
	var run := func() -> void:
		result[0] = await PluginCommandDialog.open(self, "")
		result[1] = true
	run.call()
	var d := await _dialog()
	ok(d != null, "plugin command dialog opens")
	var edits := _edits(d)
	ok(edits.size() == 3, "name, command and arguments fields (%d)" % edits.size())
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(not result[1] and d.visible, "empty plugin name and command are refused, dialog stays open")
	edits[0].text = "now-playing"
	edits[1].text = "toggle"
	edits[2].text = "not json"
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	ok(not result[1], "malformed arguments are refused")
	edits[2].text = '["a", "b"]'
	d.get_ok_button().pressed.emit()
	await get_tree().create_timer(0.3).timeout
	var value: Variant = result[0]
	ok(result[1] and value is Dictionary and value.get("name") == "now-playing" and value.get("sub") == "toggle" and value.get("args") == ["a", "b"], "valid command is returned (%s)" % str(value))

	result[0] = null
	result[1] = false
	run.call()
	d = await _dialog()
	d.canceled.emit()
	await get_tree().create_timer(0.3).timeout
	ok(result[1] and result[0] == null, "cancel returns null")
