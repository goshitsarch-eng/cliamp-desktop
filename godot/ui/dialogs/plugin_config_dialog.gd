class_name PluginConfigDialog
extends RefCounted
## Private plugin configuration. Existing keys appear as hidden secret fields
## (values are never read back); changing one replaces it and an empty value
## clears it. New settings can be added by name. Returns {key: value} for the
## changed entries, or null when cancelled. Values are never logged or toasted.


static func open(host: Node, plugin: Dictionary) -> Variant:
	var form := SchemaForm.new()
	for key: String in plugin.get("config_keys", []):
		form.add_field(SchemaForm.normalize_field({"key": key, "label": key, "group": "Settings", "type": "secret"}))

	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	box.add_theme_constant_override("separation", 10)
	var intro := FormKit.muted("Use the setting names documented by this plugin. Existing values stay hidden. An empty new value clears that setting.", 12)
	box.add_child(intro)

	var view := SchemaFormView.new()
	view.default_open_group = "Settings"
	view.bind(form)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 120)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(view)
	var hint := FormKit.muted("This plugin has no stored settings yet.", 12)
	hint.visible = form.fields.is_empty()
	scroll.visible = not form.fields.is_empty()
	box.add_child(hint)
	box.add_child(scroll)

	box.add_child(HSeparator.new())
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Setting name"
	name_edit.accessibility_name = "New setting name"
	box.add_child(name_edit)
	var value_edit := LineEdit.new()
	value_edit.secret = true
	value_edit.placeholder_text = "New value or environment reference"
	value_edit.accessibility_name = "New setting value"
	box.add_child(value_edit)
	var add_error := FormKit.error_label()
	box.add_child(add_error)
	var add := Button.new()
	add.text = "Add setting"
	add.accessibility_name = "Add setting"
	add.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(add)

	var dialog := FormKit.make_dialog("%s settings" % plugin.get("name", "Plugin"), box, "Save settings", "Cancel", Vector2i(560, 0))
	dialog.get_ok_button().disabled = true
	view.edited.connect(func(_k: String) -> void: dialog.get_ok_button().disabled = not form.is_dirty())
	add.pressed.connect(func() -> void:
		var key := name_edit.text
		var error := PluginLogic.config_key_error(key)
		if error.is_empty() and form.has_field(key):
			error = "That setting is already listed above."
		if error.is_empty() and (value_edit.text.contains("\n") or value_edit.text.contains("\r")):
			error = "Use a single-line value."
		FormKit.set_error(add_error, error)
		if not error.is_empty():
			return
		form.add_field(SchemaForm.normalize_field({"key": key, "label": key, "group": "Settings", "type": "secret"}))
		form.set_value(key, value_edit.text)
		name_edit.text = ""
		value_edit.text = ""
		view.rebuild()
		hint.hide()
		scroll.show()
		dialog.get_ok_button().disabled = false)

	if not await FormKit.run(host, dialog):
		return null
	var values := form.changed()
	for key in values:
		if not form.validate(key).is_empty():
			return null
	return values
