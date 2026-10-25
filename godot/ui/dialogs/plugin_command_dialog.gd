class_name PluginCommandDialog
extends RefCounted
## Collects a plugin command: plugin name, command and a JSON array of string
## arguments. Returns {name, sub, args} or null when cancelled.


static func open(host: Node, command := "") -> Variant:
	var parts := PluginLogic.split_command(command)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 0)
	box.add_theme_constant_override("separation", 6)
	var name_edit := _field(box, "Plugin name", parts[0], "")
	var sub_edit := _field(box, "Command", parts[1], "")
	var args_edit := _field(box, "Arguments (JSON array of strings)", "[]", "[]")
	var error := FormKit.error_label()
	box.add_child(error)
	var out := {}
	var accept := func() -> bool:
		var name := name_edit.text.strip_edges()
		var sub := sub_edit.text.strip_edges()
		var parsed := PluginLogic.parse_args(args_edit.text)
		var message := ""
		if name.is_empty() or sub.is_empty():
			message = "Enter a plugin name and a command."
		elif parsed.has("error"):
			message = parsed["error"]
		FormKit.set_error(error, message)
		if not message.is_empty():
			return false
		out["name"] = name
		out["sub"] = sub
		out["args"] = parsed["args"]
		return true
	var dialog := FormKit.make_dialog("Run plugin command", box, "Run", "Cancel", Vector2i(500, 0))
	name_edit.call_deferred("grab_focus")
	if not await FormKit.run(host, dialog, accept):
		return null
	return out


static func _field(box: VBoxContainer, label_text: String, initial: String, hint: String) -> LineEdit:
	var l := Label.new()
	l.text = label_text
	box.add_child(l)
	var edit := LineEdit.new()
	edit.text = initial
	edit.placeholder_text = hint
	edit.accessibility_name = label_text
	box.add_child(edit)
	return edit
