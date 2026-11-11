class_name SettingsPage
extends Page
## Playback controls, audio output, interface scale, connected providers and
## the searchable engine preferences (app.dart _settings, preferences.dart).

## Emitted by "Connect service". When nothing is connected, the page opens the
## Providers page instead.
signal connect_service_requested

const SPEEDS: Array[float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
const SETUP_TEXT := "Choose Connect service to configure an account, then follow its sign-in instructions. You can also use cliamp setup from a terminal.\n\nAccounts and preferences are shared with the terminal player.\n\nFFmpeg and yt-dlp extend supported streaming formats. Your existing installations are reused."

var _form := SchemaForm.new()
var _view: SchemaFormView
var _muted: Array = []

var _mono: CheckButton
var _speed: OptionButton
var _device_label: Label
var _device_list: VBoxContainer
var _device_error: Label
var _devices: Array[Dictionary] = []
var _scale: HSlider
var _scale_label: Label
var _scale_timer: Timer
var _providers_flow: HFlowContainer
var _operations_button: Button

var _pref_status: Label
var _pref_note: Label
var _pref_progress: ProgressBar
var _save_button: Button
var _restart_button: Button
var _discard_button: Button

var _generation := 0
var _device_generation := 0
var _busy := false
var _saved := false
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 36)
	scroll.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 24)
	margin.add_child(root)

	root.add_child(FormKit.heading("Make yourself at home.", "Playback preferences and your connected music services.", _muted))
	_build_playback(root)
	_build_appearance(root)
	_build_providers(root)
	_build_preferences(root)
	_build_advanced(root)
	var mod := "Cmd" if OS.get_name() == "macOS" else "Ctrl"
	var footer := FormKit.muted("Cliamp Desktop  ·  Built for listening.\n%s+O  Add music     %s+F  Search" % [mod, mod], 11)
	_muted.append(footer)
	root.add_child(footer)

	_scale_timer = Timer.new()
	_scale_timer.one_shot = true
	_scale_timer.wait_time = 0.4
	_scale_timer.timeout.connect(func() -> void: Prefs.set_ui_scale(_scale.value))
	add_child(_scale_timer)

	Store.state_changed.connect(func(_s: Dictionary) -> void: _sync_playback())
	Store.connection_changed.connect(_on_connection_changed)
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void:
		FormKit.recolor(_muted)
		_render_providers()
		_render_devices())
	_sync_playback()


func activate() -> void:
	_build()
	_sync_playback()
	_render_providers()
	_load_devices()
	if not _form.is_dirty() and not _busy:
		_load_preferences()


func deactivate() -> void:
	_generation += 1
	_device_generation += 1


func refresh() -> void:
	_load_devices()
	if not _form.is_dirty() and not _busy:
		_load_preferences()


func handles_escape() -> bool:
	return _form.is_dirty()


# Playback

func _build_playback(root: VBoxContainer) -> void:
	var box := FormKit.card(root)
	_mono = CheckButton.new()
	_mono.text = "Mono audio"
	_mono.accessibility_name = "Mono audio"
	_mono.accessibility_description = "Combine both channels for a single output."
	_mono.toggled.connect(func(on: bool) -> void: await Store.run("mono", {"name": "on" if on else "off"}))
	box.add_child(_mono)
	box.add_child(_hint("Combine both channels for a single output."))
	box.add_child(HSeparator.new())

	var speed_row := HBoxContainer.new()
	var speed_text := VBoxContainer.new()
	speed_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var speed_title := Label.new()
	speed_title.text = "Playback speed"
	speed_text.add_child(speed_title)
	speed_text.add_child(_hint("Adjust the pace of music, podcasts, and audiobooks."))
	speed_row.add_child(speed_text)
	_speed = OptionButton.new()
	_speed.accessibility_name = "Playback speed"
	for s in SPEEDS:
		_speed.add_item("%s×" % str(s))
	_speed.item_selected.connect(func(i: int) -> void: await Store.run("speed", {"value": SPEEDS[i]}))
	speed_row.add_child(_speed)
	box.add_child(speed_row)
	box.add_child(HSeparator.new())

	var device_row := HBoxContainer.new()
	var device_text := VBoxContainer.new()
	device_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var device_title := Label.new()
	device_title.text = "Audio output"
	device_text.add_child(device_title)
	_device_label = _hint("System default")
	device_text.add_child(_device_label)
	device_row.add_child(device_text)
	device_row.add_child(Icons.button("refresh", "Refresh audio devices", _load_devices))
	box.add_child(device_row)
	_device_error = FormKit.muted("", 12)
	_device_error.visible = false
	_muted.append(_device_error)
	box.add_child(_device_error)
	_device_list = VBoxContainer.new()
	box.add_child(_device_list)


func _hint(text: String) -> Label:
	var l := FormKit.muted(text, 12)
	_muted.append(l)
	return l


func _sync_playback() -> void:
	_mono.set_pressed_no_signal(Store.state.get("mono") == true)
	var current := Util.number(Store.state.get("speed"), 1.0)
	var best := 0
	for i in SPEEDS.size():
		if absf(SPEEDS[i] - current) < absf(SPEEDS[best] - current):
			best = i
	_speed.select(best)
	var enabled := Store.connected
	_mono.disabled = not enabled
	_speed.disabled = not enabled
	_device_label.text = Util.text(Store.state.get("device"), "System default")


func _on_connection_changed() -> void:
	_sync_playback()
	_render_providers()
	_operations_button.disabled = Store.operations.is_empty()
	_operations_button.text = "Browse %d engine operations" % Store.operations.size()
	if Store.connected and visible:
		_load_devices()


func _load_devices() -> void:
	_device_generation += 1
	var generation := _device_generation
	if not Store.connected:
		return
	var data := await Backend.call_op("device", {"name": "list"})
	if generation != _device_generation or not is_inside_tree():
		return
	if Backend.failed(data):
		_devices = []
		_render_devices()
		FormKit.set_error(_device_error, data["error"]["message"])
		return
	FormKit.set_error(_device_error, "")
	_devices = Util.objects(data.get("devices"))
	_render_devices()


func _render_devices() -> void:
	if _device_list == null:
		return
	for child in _device_list.get_children():
		_device_list.remove_child(child)
		child.queue_free()
	for device in _devices:
		_device_list.add_child(_device_row(device))


func _device_row(device: Dictionary) -> Control:
	var active: bool = device.get("active") == true
	var name := Util.text(device.get("name"))
	var row := HBoxContainer.new()
	var palette := ThemeBuilder.palette
	row.add_child(Icons.label("radio_button_checked" if active else "radio_button_off", 18, palette.accent if active else palette.muted))
	var button := Button.new()
	button.text = name
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.clip_text = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.accessibility_name = "Use %s for audio output" % name
	button.pressed.connect(_use_device.bind(name))
	row.add_child(button)
	return row


func _use_device(name: String) -> void:
	await Store.run("device", {"name": name})
	if is_inside_tree():
		_load_devices()


# Appearance

func _build_appearance(root: VBoxContainer) -> void:
	var box := FormKit.card(root)
	box.add_child(FormKit.section_title("Appearance"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var title := Label.new()
	title.text = "Interface scale"
	row.add_child(title)
	_scale = HSlider.new()
	_scale.min_value = 0.75
	_scale.max_value = 2.0
	_scale.step = 0.05
	_scale.value = Prefs.ui_scale
	_scale.custom_minimum_size.x = 220
	_scale.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scale.accessibility_name = "Interface scale"
	_scale.accessibility_description = "Scale the whole interface from 75 to 200 percent."
	_scale_label = Label.new()
	_scale_label.text = _percent(_scale.value)
	_scale_label.custom_minimum_size.x = 52
	_scale.value_changed.connect(func(v: float) -> void:
		_scale_label.text = _percent(v)
		_scale_timer.start())
	row.add_child(_scale)
	row.add_child(_scale_label)
	row.add_child(Icons.button("restart_alt", "Reset interface scale to 100%", func() -> void: _scale.value = 1.0))
	box.add_child(row)
	box.add_child(_hint("Applies a moment after you stop moving the slider and is remembered for this app."))


static func _percent(scale: float) -> String:
	return "%d%%" % roundi(scale * 100.0)


# Providers

func _build_providers(root: VBoxContainer) -> void:
	var box := FormKit.card(root)
	box.add_child(FormKit.section_title("Connected providers"))
	_providers_flow = HFlowContainer.new()
	box.add_child(_providers_flow)
	box.add_child(_hint("The desktop app shares Cliamp’s provider accounts, music library, plugins, and preferences. Connect a service here, or use cliamp setup from a terminal."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var connect_button := Button.new()
	connect_button.text = "Connect service"
	connect_button.accessibility_name = "Connect service"
	connect_button.pressed.connect(func() -> void:
		if connect_service_requested.get_connections().is_empty():
			Store.navigate("providers")
		else:
			connect_service_requested.emit())
	row.add_child(connect_button)
	var info := Button.new()
	info.text = "Setup instructions"
	info.accessibility_name = "Setup instructions"
	info.pressed.connect(func() -> void: await Dialogs.message(self, "Provider setup", SETUP_TEXT))
	row.add_child(info)
	box.add_child(row)


func _render_providers() -> void:
	for child in _providers_flow.get_children():
		_providers_flow.remove_child(child)
		child.queue_free()
	for p in Store.providers:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.add_child(Icons.label("check_circle_outline", 15, ThemeBuilder.palette.accent))
		var l := Label.new()
		l.text = Util.text(p.get("name"))
		l.add_theme_font_size_override("font_size", 12)
		chip.add_child(l)
		var holder := MarginContainer.new()
		holder.add_theme_constant_override("margin_right", 14)
		holder.add_child(chip)
		_providers_flow.add_child(holder)


# Preferences

func _build_preferences(root: VBoxContainer) -> void:
	var box := FormKit.card(root)
	box.add_child(FormKit.section_title("Preferences"))
	box.add_child(_hint("Engine preferences shared with the terminal player. Only changed values are written; the rest of your configuration is left untouched."))
	var search := LineEdit.new()
	search.placeholder_text = "Find a preference"
	search.clear_button_enabled = true
	search.accessibility_name = "Find a preference"
	search.text_changed.connect(func(t: String) -> void: _view.set_filter(t))
	box.add_child(search)
	_pref_status = FormKit.error_label()
	box.add_child(_pref_status)
	_pref_note = _hint("")
	_pref_note.visible = false
	box.add_child(_pref_note)
	_pref_progress = ProgressBar.new()
	_pref_progress.indeterminate = true
	_pref_progress.show_percentage = false
	_pref_progress.visible = false
	box.add_child(_pref_progress)
	_view = SchemaFormView.new()
	_view.bind(_form)
	_view.edited.connect(func(_k: String) -> void: _update_pref_buttons())
	box.add_child(_view)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_END
	_discard_button = Button.new()
	_discard_button.text = "Discard changes"
	_discard_button.accessibility_name = "Discard preference changes"
	_discard_button.pressed.connect(_load_preferences)
	row.add_child(_discard_button)
	_restart_button = Button.new()
	_restart_button.text = "Restart player"
	_restart_button.accessibility_name = "Restart player"
	_restart_button.pressed.connect(_restart)
	row.add_child(_restart_button)
	_save_button = Button.new()
	_save_button.text = "Save changes"
	_save_button.accessibility_name = "Save preference changes"
	_save_button.pressed.connect(_save)
	row.add_child(_save_button)
	box.add_child(row)
	_update_pref_buttons()


func _set_busy(busy: bool) -> void:
	_busy = busy
	_pref_progress.visible = busy
	_view.set_enabled(not busy)
	_update_pref_buttons()


func _update_pref_buttons() -> void:
	var dirty := _form.is_dirty()
	_save_button.disabled = _busy or not dirty
	_discard_button.disabled = _busy or not dirty
	_restart_button.visible = _saved and Backend.owns_daemon()
	_restart_button.disabled = _busy or dirty
	_pref_note.visible = _saved
	if _saved:
		_pref_note.text = "Saved. Restart the player to apply startup preferences." if Backend.owns_daemon() \
			else "Saved. Restart the player instance you connected to for startup preferences to take effect."


func _load_preferences() -> void:
	_generation += 1
	var generation := _generation
	_set_busy(true)
	FormKit.set_error(_pref_status, "")
	var schema := await Backend.preferences_schema()
	if generation != _generation or not is_inside_tree():
		return
	if Backend.failed(schema):
		FormKit.set_error(_pref_status, schema["error"]["message"])
		_set_busy(false)
		return
	_form.load_fields(schema.get("fields"))
	_view.bind(_form)
	_set_busy(false)


func _save() -> void:
	var errors := _form.validate_changed()
	if not errors.is_empty():
		_view.show_errors(errors)
		var first_key: String = str(errors.keys()[0])
		var first_label := Util.text(_form.field(first_key).get("label"), first_key)
		FormKit.set_error(_pref_status, "Fix highlighted preferences (%s: %s)." % [first_label, str(errors[first_key])])
		return
	_view.show_errors({})
	FormKit.set_error(_pref_status, "")
	var changed := _form.changed()
	_set_busy(true)
	var result := await Backend.save_preferences(changed)
	if not is_inside_tree():
		return
	if Backend.failed(result):
		FormKit.set_error(_pref_status, result["error"]["message"])
		_set_busy(false)
		return
	_form.mark_saved(changed)
	_saved = _saved or result.get("restart_required") == true
	_set_busy(false)
	Store.notify("Preferences saved.")
	# A saved theme is applied by Backend; pick up the new engine state.
	Store.refresh_state()


func _restart() -> void:
	if Store.is_playing() and not await Dialogs.confirm(self, "Restart the player?", "Playback will pause briefly while the player restarts and restores your queue.", "Restart"):
		return
	_set_busy(true)
	FormKit.set_error(_pref_status, "")
	var result := await Backend.restart_owned_engine()
	if not is_inside_tree():
		return
	if Backend.failed(result):
		FormKit.set_error(_pref_status, result["error"]["message"])
		_set_busy(false)
		return
	_saved = false
	_set_busy(false)
	await Store.start()
	if is_inside_tree() and visible:
		_load_preferences()


# Advanced

func _build_advanced(root: VBoxContainer) -> void:
	var box := FormKit.card(root)
	box.add_child(FormKit.section_title("Advanced controls"))
	box.add_child(_hint("Access additional commands supported by your running player."))
	_operations_button = Button.new()
	_operations_button.text = "Browse %d engine operations" % Store.operations.size()
	_operations_button.disabled = Store.operations.is_empty()
	_operations_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_operations_button.accessibility_name = "Browse engine operations"
	_operations_button.pressed.connect(_operations)
	box.add_child(_operations_button)


func _operations() -> void:
	var request: Variant = await OperationDialog.open(self, Store.operations)
	if request == null:
		return
	var result: Variant = await Store.run(str(request["operation"]), request["params"])
	if result != null:
		await Dialogs.message(self, "Operation result", JSON.stringify(result, "  "))
