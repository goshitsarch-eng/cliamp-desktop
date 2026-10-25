class_name OperationDialog
extends RefCounted
## Advanced engine-operation browser: pick an operation, edit its JSON
## parameters, run it. Returns {operation, params} or null when cancelled.


static func open(host: Node, operations: Array[Dictionary]) -> Variant:
	if operations.is_empty():
		return null
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 8)
	var picker := OptionButton.new()
	picker.accessibility_name = "Engine operation"
	for o in operations:
		picker.add_item(Util.text(o.get("name")))
	box.add_child(picker)
	var description := FormKit.muted("", 12)
	box.add_child(description)
	var params_label := Label.new()
	params_label.add_theme_font_size_override("font_size", 12)
	box.add_child(params_label)
	var label := Label.new()
	label.text = "Parameters (JSON object)"
	box.add_child(label)
	var edit := TextEdit.new()
	edit.text = "{}"
	edit.custom_minimum_size = Vector2(0, 110)
	edit.accessibility_name = "Parameters as a JSON object"
	box.add_child(edit)
	var error := FormKit.error_label()
	box.add_child(error)
	var show := func(i: int) -> void:
		var o := operations[i]
		description.text = Util.text(o.get("description"))
		var p: Array = o.get("parameters") if o.get("parameters") is Array else []
		params_label.text = "Parameters: %s" % ", ".join(p.map(func(x: Variant) -> String: return str(x)))
		FormKit.set_error(error, "")
	picker.item_selected.connect(show)
	show.call(0)
	var out := {}
	var accept := func() -> bool:
		var parsed: Variant = SchemaForm.parse_json(edit.text)
		if not (parsed is Dictionary):
			FormKit.set_error(error, "Enter a JSON object.")
			return false
		out["operation"] = picker.get_item_text(picker.selected)
		out["params"] = parsed
		return true
	var dialog := FormKit.make_dialog("Engine operations", box, "Run operation", "Cancel", Vector2i(560, 0))
	if not await FormKit.run(host, dialog, accept):
		return null
	return out
