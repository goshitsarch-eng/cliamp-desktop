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
