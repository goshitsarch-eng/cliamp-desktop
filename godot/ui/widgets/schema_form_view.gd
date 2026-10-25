class_name SchemaFormView
extends VBoxContainer
## Renders a SchemaForm as collapsible groups of labelled controls: text,
## number, bool, choice, list and secret fields. Edits go straight into the
## form; the owner reads form.changed() when saving.

signal edited(key: String)

## Group that starts open when there is no filter.
var default_open_group := "Playback"
var form: SchemaForm
var _filter := ""
var _toggled: Dictionary = {}
var _errors: Dictionary = {}
var _controls: Array[Control] = []
var _muted: Array = []
var _enabled := true


func _init() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: FormKit.recolor(_muted))


func bind(new_form: SchemaForm) -> void:
	form = new_form
	_toggled.clear()
	rebuild()


func set_filter(text: String) -> void:
	var cleaned := text.strip_edges().to_lower()
	if cleaned == _filter:
		return
	_filter = cleaned
	_toggled.clear()
	rebuild()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	for c in _controls:
		if is_instance_valid(c):
			_set_disabled(c, not enabled)


## Shows {key: message} under the fields; clears every other field's message.
func show_errors(errors: Dictionary) -> void:
	for key in _errors:
		FormKit.set_error(_errors[key], str(errors.get(key, "")))


## Number of fields currently shown (after filtering).
func visible_field_count() -> int:
	var n := 0
	if form != null:
		for g in form.groups(_filter):
			n += (g["fields"] as Array).size()
	return n


func rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_errors.clear()
	_controls.clear()
	_muted.clear()
	if form == null:
		return
	for group in form.groups(_filter):
		_add_group(group["name"], group["fields"])


func _add_group(group_name: String, group_fields: Array) -> void:
	var expanded: bool = _toggled.get(group_name, not _filter.is_empty() or group_name == default_open_group)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.visible = expanded
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.visible = expanded
	margin.add_child(body)

	var header := HBoxContainer.new()
	var chevron := Icons.label("expand_more" if expanded else "chevron_right", 20)
	header.add_child(chevron)
	var button := Button.new()
	button.text = group_name
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accessibility_name = "%s group" % group_name
	button.accessibility_description = "Show or hide the settings in this group."
	button.pressed.connect(func() -> void:
		var open := not margin.visible
		margin.visible = open
		_toggled[group_name] = open
		chevron.text = Icons.glyph("expand_more" if open else "chevron_right"))
	header.add_child(button)
	add_child(header)
	add_child(margin)
	_controls.append(button)
	for f: Dictionary in group_fields:
		body.add_child(_build_field(f))


func _build_field(f: Dictionary) -> Control:
	var key: String = f["key"]
	var kind := SchemaForm.kind_of(f)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var label_text: String = f["label"]
	var control: Control
	match kind:
		SchemaForm.KIND_BOOL:
			var check := CheckButton.new()
			check.text = label_text
			check.button_pressed = form.value(key) == "true"
			check.toggled.connect(func(on: bool) -> void: _commit(key, "true" if on else "false"))
			control = check
			box.add_child(check)
		SchemaForm.KIND_CHOICE:
			box.add_child(_title(label_text))
			control = _choice(f)
			box.add_child(control)
		SchemaForm.KIND_LIST:
			box.add_child(_title(label_text))
			control = _list_editor(f)
			box.add_child(control)
		SchemaForm.KIND_SECRET:
			box.add_child(_title(label_text))
			control = _secret(f)
			box.add_child(control)
		_:
			box.add_child(_title(label_text))
			var edit := LineEdit.new()
			edit.text = form.value(key)
			edit.accessibility_name = label_text
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			edit.text_changed.connect(func(t: String) -> void: _commit(key, t))
			control = edit
			box.add_child(edit)
	if kind != SchemaForm.KIND_LIST:
		control.set_meta("field_key", key)
	_controls.append(control)
	_set_disabled(control, not _enabled)
	var help_parts: Array[String] = []
	if not str(f["help"]).is_empty():
		help_parts.append(f["help"])
	var range_text := SchemaForm.range_text(f)
	if not range_text.is_empty():
		help_parts.append(range_text)
	if not help_parts.is_empty():
		var help := FormKit.muted("\n".join(help_parts), 12)
		_muted.append(help)
		box.add_child(help)
	var error := FormKit.error_label()
	_errors[key] = error
	box.add_child(error)
	return box


func _title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _choice(f: Dictionary) -> OptionButton:
	var key: String = f["key"]
	var current := form.value(key)
	var values: Array[String] = []
	for o: String in f["options"]:
		values.append(o)
	if not values.has(current):
		values.append(current)
	var option := OptionButton.new()
	option.accessibility_name = f["label"]
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in values.size():
		option.add_item("Default" if values[i].is_empty() else values[i])
		if values[i] == current:
			option.select(i)
	option.item_selected.connect(func(i: int) -> void: _commit(key, values[i]))
	return option


func _secret(f: Dictionary) -> Control:
	var key: String = f["key"]
	var row := HBoxContainer.new()
	var edit := LineEdit.new()
	edit.secret = true
	edit.placeholder_text = "Hidden. Type a new value to replace it."
	edit.accessibility_name = f["label"]
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_changed.connect(func(t: String) -> void: _commit(key, t))
	row.add_child(edit)
	var clear := Button.new()
	clear.text = "Clear"
	clear.tooltip_text = "Remove the stored value when saved"
	clear.accessibility_name = "Clear %s" % f["label"]
	clear.pressed.connect(func() -> void:
		edit.text = ""
		_commit(key, "")
		edit.placeholder_text = "Will be cleared when saved.")
	row.add_child(clear)
	row.set_meta("inner", [edit, clear])
	return row


func _list_editor(f: Dictionary) -> Control:
	var key: String = f["key"]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var parsed: Variant = SchemaForm.parse_json(form.value(key))
	var items: Array = []
	if parsed is Array:
		for item in parsed:
			items.append(str(item))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	box.add_child(rows)
	var sync := func() -> void:
		var out: Array[String] = []
		for row in rows.get_children():
			var text: String = (row.get_child(0) as LineEdit).text
			if not text.strip_edges().is_empty():
				out.append(text)
		_commit(key, JSON.stringify(out))
	var add_row := func(text: String) -> void:
		var row := HBoxContainer.new()
		var edit := LineEdit.new()
		edit.text = text
		edit.accessibility_name = "%s item" % f["label"]
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		edit.text_changed.connect(func(_t: String) -> void: sync.call())
		row.add_child(edit)
		var on_remove := func() -> void:
			rows.remove_child(row)
			row.queue_free()
			sync.call()
		row.add_child(Icons.button("close", "Remove item", on_remove, 16))
		rows.add_child(row)
	for item: String in items:
		add_row.call(item)
	var add := Button.new()
	add.text = "Add item"
	add.accessibility_name = "Add item to %s" % f["label"]
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func() -> void:
		add_row.call("")
		(rows.get_child(rows.get_child_count() - 1).get_child(0) as Control).grab_focus())
	box.add_child(add)
	box.set_meta("field_key", key)
	box.set_meta("inner", [add])
	return box


func _commit(key: String, value: String) -> void:
	form.set_value(key, value)
	var message := form.validate(key) if form.is_changed(key) else ""
	if _errors.has(key):
		FormKit.set_error(_errors[key], message)
	edited.emit(key)


## Disables or enables a field control, including the inner controls of
## composite ones (secret rows, list editors).
static func _set_disabled(c: Control, disabled: bool) -> void:
	if c is BaseButton:
		(c as BaseButton).disabled = disabled
	elif c is LineEdit:
		(c as LineEdit).editable = not disabled
	if c.has_meta("inner"):
		for inner: Control in c.get_meta("inner"):
			_set_disabled(inner, disabled)
	if c is VBoxContainer:
		for row in c.get_children():
			if row is VBoxContainer:
				for r in row.get_children():
					for part in r.get_children():
						_set_disabled(part, disabled)
