class_name ProviderSetupDialog
extends RefCounted
## "Connect your music": a conditional form built from the engine's setup schema.
## Credentials stay in the form's fields and go to the engine over stdin only
## (Backend.save_provider). Values are never logged, toasted or kept after a save.

signal finished(restarted: bool)

var _dialog: AcceptDialog
var _body: VBoxContainer
var _schema: Dictionary = {}
var _providers: Array[Dictionary] = []
var _values: Dictionary = {}
var _provider := ""
var _edits: Dictionary = {}
var _field_errors: Dictionary = {}
var _error := ""
var _loading := true
var _saving := false
var _saved := false
var _save_failed := false
var _generation := 0
var _closed := false


## Resolves true when the owned engine was restarted; the caller then calls
## Store.start().
static func open(host: Node) -> bool:
	var flow := ProviderSetupDialog.new()
	return await flow._run(host)


func _run(host: Node) -> bool:
	_dialog = AcceptDialog.new()
	_dialog.exclusive = true
	_dialog.min_size = Vector2i(Vector2(560, 0) * Prefs.ui_scale)
	_dialog.get_ok_button().hide()
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(540, 0)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560, 440) * Prefs.ui_scale
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)
	_dialog.add_child(scroll)
	_dialog.close_requested.connect(_close.bind(false))
	_dialog.canceled.connect(_close.bind(false))
	Util.host(host).add_child(_dialog)
	_render()
	_dialog.popup_centered()
	_load_schema()
	var restarted: bool = await finished
	return restarted


func _close(restarted: bool) -> void:
	if _closed or (_saving and not restarted):
		return
	_closed = true
	_values.clear()
	_detach_edits()
	for edit: LineEdit in _edits.values():
		edit.free()
	_edits.clear()
	_dialog.queue_free()
	finished.emit(restarted)


func _load_schema() -> void:
	_generation += 1
	var generation := _generation
	_loading = true
	_error = ""
	_render()
	var result := await Backend.setup_schema(_provider, _values)
	if _closed or generation != _generation:
		return
	if Backend.failed(result):
		_loading = false
		_error = result["error"]["message"]
		_render()
		return
	_schema = result
	var providers := Util.objects(result.get("providers"))
	if not providers.is_empty():
		_providers = providers
	ProviderSetupForm.merge_defaults(_values, result.get("values"))
	for field in Util.objects(result.get("fields")):
		var key := Util.text(field.get("key"))
		if not _edits.has(key):
			var edit := LineEdit.new()
			edit.text = str(_values.get(key, Util.text(field.get("value"))))
			_edits[key] = edit
	_loading = false
	_render()


func _read_fields() -> void:
	for field in Util.objects(_schema.get("fields")):
		var key := Util.text(field.get("key"))
		var edit: LineEdit = _edits.get(key)
		_values[key] = edit.text if edit != null else ""


func _choose_provider(provider: String) -> void:
	for edit: LineEdit in _edits.values():
		if edit.get_parent() != null:
			edit.get_parent().remove_child(edit)
		edit.free()
	_edits.clear()
	_field_errors.clear()
	_provider = provider
	_values = {}
	_schema = {}
	_load_schema()


func _save(verify_connection := true) -> void:
	_read_fields()
	var missing := ProviderSetupForm.missing_required(Util.objects(_schema.get("fields")), _values)
	_field_errors.clear()
	for key in missing:
		_field_errors[key] = "This field is required."
	if not missing.is_empty():
		_render()
		return
	_saving = true
	_error = ""
	_render()
	var result := await Backend.save_provider(_provider, _values, verify_connection)
	if _closed:
		return
	_saving = false
	if Backend.failed(result):
		_save_failed = true
		_error = result["error"]["message"]
		_render()
		return
	_saved = true
	# The credentials are saved; keep no copy of them.
	_values.clear()
	for edit: LineEdit in _edits.values():
		edit.text = ""
	_render()


func _restart() -> void:
	_saving = true
	_error = ""
	_render()
	var result := await Backend.restart_owned_engine()
	if _closed:
		return
	_saving = false
	if Backend.failed(result):
		_error = result["error"]["message"]
		_render()
		return
	_close(true)


func _picker_changed(index: int, options: Array, key: String) -> void:
	_read_fields()
	_values[key] = str(options[index].get("value"))
	_load_schema()


func _detach_edits() -> void:
	for edit: LineEdit in _edits.values():
		if edit.get_parent() != null:
			edit.get_parent().remove_child(edit)


func _render() -> void:
	if _closed:
		return
	_detach_edits()
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_dialog.title = "Your provider is configured" if _saved else "Connect your music"
	if _saved:
		_render_saved()
	else:
		_render_form()
	if not _error.is_empty():
		_body.add_child(_spacer(14))
		_body.add_child(_label(_error, 12, ThemeBuilder.palette.error))
	if _saving:
		_body.add_child(_spacer(14))
		_body.add_child(_progress())
	_body.add_child(_spacer(14))
	_body.add_child(_buttons())


func _render_saved() -> void:
	_body.add_child(Icons.label("check_circle_outline", 36, ThemeBuilder.palette.accent))
	_body.add_child(_spacer(14))
	_body.add_child(_label("Your account settings have been saved in Cliamp's credential store."))
	_body.add_child(_spacer(10))
	if Backend.owns_daemon():
		_body.add_child(_label("Restart the player to load the provider. This stops current playback."))
	else:
		_body.add_child(_label("This app is connected to an existing Cliamp player. Restart that player, then reconnect this app to load the provider."))


func _render_form() -> void:
	_body.add_child(_label("Choose a service and enter its connection details. Your existing library and player preferences are preserved.", 12, ThemeBuilder.palette.muted))
	_body.add_child(_spacer(14))
	_body.add_child(_label("Music service"))
	var chooser := OptionButton.new()
	chooser.accessibility_name = "Music service"
	chooser.disabled = _saving
	chooser.add_item("Choose a service", 0)
	chooser.set_item_disabled(0, true)
	var selected := 0
	for i in _providers.size():
		chooser.add_item(Util.text(_providers[i].get("name")), i + 1)
		if Util.text(_providers[i].get("key")) == _provider:
			selected = i + 1
	chooser.select(selected)
	chooser.item_selected.connect(func(index: int) -> void:
		if index > 0:
			_choose_provider(Util.text(_providers[index - 1].get("key"))))
	_body.add_child(chooser)
	if _loading:
		_body.add_child(_spacer(14))
		_body.add_child(_progress())
	if _loading or _provider.is_empty():
		return
	var intro := ProviderSetupForm.intro_text(_schema.get("intro"))
	if not intro.is_empty():
		_body.add_child(_spacer(14))
		_body.add_child(_label(intro, 12, ThemeBuilder.palette.muted))
	var picker := Util.object(_schema.get("picker"))
	var options: Array = Util.objects(picker.get("options"))
	if not options.is_empty():
		var picker_key := Util.text(picker.get("key"))
		_body.add_child(_spacer(14))
		_body.add_child(_label(Util.text(picker.get("label"), "Connection type")))
		var pick := OptionButton.new()
		pick.accessibility_name = Util.text(picker.get("label"), "Connection type")
		pick.disabled = _saving
		for option in options:
			pick.add_item(Util.text(option.get("label")))
		pick.select(ProviderSetupForm.option_index(options, str(_values.get(picker_key, ""))))
		pick.item_selected.connect(_picker_changed.bind(options, picker_key))
		_body.add_child(pick)
	for field in Util.objects(_schema.get("fields")):
		var key := Util.text(field.get("key"))
		var edit: LineEdit = _edits.get(key)
		if edit == null:
			continue
		edit.secret = field.get("secret") == true
		edit.editable = not _saving
		edit.accessibility_name = ProviderSetupForm.field_label(field)
		edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_body.add_child(_spacer(14))
		_body.add_child(_label(ProviderSetupForm.field_label(field)))
		_body.add_child(edit)
		var help := Util.text(field.get("help"))
		if not help.is_empty():
			_body.add_child(_label(help, 11, ThemeBuilder.palette.muted))
		if _field_errors.has(key):
			_body.add_child(_label(_field_errors[key], 11, ThemeBuilder.palette.error))
	_body.add_child(_spacer(14))
	_body.add_child(_label("Saving replaces this provider's connection details and credentials. Existing secrets are never shown here; enter the credentials you want to use.", 11, ThemeBuilder.palette.muted))


func _buttons() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	var cancel := _button("Later" if _saved else "Cancel", _close.bind(false))
	cancel.disabled = _saving
	row.add_child(cancel)
	if _saved and Backend.owns_daemon():
		var restart := _button("Restart player", _restart)
		restart.disabled = _saving
		row.add_child(restart)
	if not _saved and _save_failed:
		var anyway := _button("Save without connection check", _save.bind(false))
		anyway.disabled = _loading or _saving
		row.add_child(anyway)
	if not _saved:
		var save := _button("Saving..." if _saving else "Save provider", _save.bind(true))
		save.disabled = _provider.is_empty() or _loading or _saving
		row.add_child(save)
	return row


func _label(text: String, size := 14, color: Variant = null) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	if color is Color:
		l.add_theme_color_override("font_color", color)
	return l


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _progress() -> ProgressBar:
	var bar := ProgressBar.new()
	bar.indeterminate = true
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 4)
	return bar


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.accessibility_name = text
	b.pressed.connect(callback)
	return b
