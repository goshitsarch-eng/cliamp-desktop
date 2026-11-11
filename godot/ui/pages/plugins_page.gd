class_name PluginsPage
extends Page
## Plugin commands and key actions, plus plugin management: installed list,
## source review with exact-content approval, enable/disable, private
## configuration and removal (app.dart _plugins, plugin_manager.dart).

var _muted: Array = []
var _built := false
var _busy := false
var _changed := false
var _plugins: Array[Dictionary] = []
var _commands: Array[String] = []
var _generation := 0
var _command_generation := 0

var _source: LineEdit
var _review_button: Button
var _status: Label
var _note: Label
var _restart_button: Button
var _progress: ProgressBar
var _installed: VBoxContainer
var _empty_installed: Label
var _bindings_box: VBoxContainer
var _commands_box: VBoxContainer
var _empty_commands: Label
var _run_button: Button
var _row_buttons: Array[Button] = []


func _ready() -> void:
	_build()


func _build() -> void:
	if _built:
		return
	_built = true
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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

	root.add_child(FormKit.heading("A little more possibility.", "Your existing Lua plugins, connected to the same audio engine.", _muted))
	_build_manager(root)
	_build_actions(root)

	Store.plugin_bindings_changed.connect(_render_bindings)
	Store.connection_changed.connect(func() -> void:
		_render_bindings()
		if Store.connected and visible:
			_load_commands())
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void:
		_render_installed()
		_muted = _muted.filter(func(n: Variant) -> bool: return is_instance_valid(n))
		FormKit.recolor(_muted))


func activate() -> void:
	_build()
	_render_bindings()
	_load_plugins()
	_load_commands()


func deactivate() -> void:
	_generation += 1
	_command_generation += 1


func refresh() -> void:
	_load_plugins()
	_load_commands()


func _hint(text: String) -> Label:
	var l := FormKit.muted(text, 12)
	_muted.append(l)
	return l


# Management

func _build_manager(root: VBoxContainer) -> void:
	var box := FormKit.card(root)
	box.add_child(FormKit.section_title("Manage plugins"))
	box.add_child(_hint("Plugins run Lua code with access to your music and files. Review the exact source, hash and permissions before trusting one."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_source = LineEdit.new()
	_source.placeholder_text = "owner/cliamp-plugin-name or HTTPS URL"
	_source.accessibility_name = "Plugin source"
	_source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source.text_submitted.connect(func(_t: String) -> void: _review(""))
	row.add_child(_source)
	_review_button = Button.new()
	_review_button.text = "Review source"
	_review_button.accessibility_name = "Review plugin source"
	_review_button.pressed.connect(func() -> void: _review(""))
	row.add_child(_review_button)
	box.add_child(row)
	_progress = ProgressBar.new()
	_progress.indeterminate = true
	_progress.show_percentage = false
	_progress.visible = false
	box.add_child(_progress)
	_status = FormKit.error_label()
	box.add_child(_status)
	_note = _hint("")
	_note.visible = false
	box.add_child(_note)
	_restart_button = Button.new()
	_restart_button.text = "Restart player"
	_restart_button.accessibility_name = "Restart player to reload plugins"
	_restart_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_restart_button.visible = false
	_restart_button.pressed.connect(_restart)
	box.add_child(_restart_button)
	box.add_child(HSeparator.new())
	_empty_installed = _hint("Add a plugin source above to review and install it.")
	box.add_child(_empty_installed)
	_installed = VBoxContainer.new()
	_installed.add_theme_constant_override("separation", 10)
	box.add_child(_installed)


func _set_busy(busy: bool, show_progress := true) -> void:
	_busy = busy
	_progress.visible = busy and show_progress
	_review_button.disabled = busy
	_source.editable = not busy
	for b in _row_buttons:
		if is_instance_valid(b):
			b.disabled = busy
	_restart_button.disabled = busy


func _show_error(message: String) -> void:
	FormKit.set_error(_status, message)


func _update_note() -> void:
	_note.visible = _changed
	_restart_button.visible = _changed and Backend.owns_daemon()
	if _changed:
		_note.text = "Changes saved. Restart the player to reload plugins." if Backend.owns_daemon() \
			else "Changes saved. Restart the connected player to reload plugins."


func _load_plugins() -> void:
	_generation += 1
	var generation := _generation
	_set_busy(true)
	var result := await Backend.plugin_action("list")
	if generation != _generation or not is_inside_tree():
		return
	if Backend.failed(result):
		_plugins = []
		_show_error(result["error"]["message"])
	else:
		_plugins = PluginLogic.parse_plugins(result)
		var warning := Util.text(result.get("warning"))
		_show_error(warning)
	_render_installed()
	_set_busy(false)
	_update_note()


func _render_installed() -> void:
	_row_buttons.clear()
	for child in _installed.get_children():
		_installed.remove_child(child)
		child.queue_free()
	_empty_installed.visible = _plugins.is_empty()
	for plugin in _plugins:
		_installed.add_child(_plugin_row(plugin))


func _plugin_row(plugin: Dictionary) -> Control:
	var palette := ThemeBuilder.palette
	var trusted := PluginLogic.is_trusted(plugin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon := Icons.label("verified_user" if trusted else "shield", 22, palette.accent if trusted else palette.muted)
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = plugin["name"] + ("" if plugin["enabled"] else " (disabled)")
	text.add_child(title)
	text.add_child(_hint(PluginLogic.subtitle(plugin)))
	if not str(plugin["description"]).is_empty():
		text.add_child(_hint(plugin["description"]))
	var permissions: Array = plugin["permissions"]
	if not permissions.is_empty():
		text.add_child(_hint("Permissions: " + ", ".join(permissions)))
	row.add_child(text)
	var buttons := HFlowContainer.new()
	buttons.alignment = FlowContainer.ALIGNMENT_END
	buttons.custom_minimum_size.x = 300
	for spec: Array in [
		["Review and trust", func() -> void: _review(plugin["id"])],
		["Disable" if plugin["enabled"] else "Enable", func() -> void: _toggle(plugin)],
		["Settings", func() -> void: _configure(plugin)],
		["Remove", func() -> void: _remove(plugin)],
	]:
		var b := Button.new()
		b.text = spec[0]
		b.accessibility_name = "%s: %s" % [spec[0], plugin["name"]]
		b.pressed.connect(spec[1])
		b.disabled = _busy
		buttons.add_child(b)
		_row_buttons.append(b)
	row.add_child(buttons)
	return row


## Prepares a review (from a source when `name` is empty, else of the installed
## plugin), shows it, and applies the approval it echoes back exactly.
func _review(name: String) -> void:
	if _busy:
		return
	var source := _source.text.strip_edges()
	if name.is_empty():
		var problem := PluginLogic.source_error(source)
		if not problem.is_empty():
			_show_error(problem)
			return
	_show_error("")
	_set_busy(true)
	var result := await Backend.plugin_action("prepare" if name.is_empty() else "review", {"source": source} if name.is_empty() else {"name": name})
	if not is_inside_tree():
		return
	if Backend.failed(result) or not PluginLogic.is_valid_review(result.get("review")):
		_set_busy(false)
		_show_error(result["error"]["message"] if Backend.failed(result) else "cliamp returned an invalid plugin review.")
		return
	var review: Dictionary = result["review"]
	_set_busy(false)
	var approved := await PluginReviewDialog.open(self, review)
	if not is_inside_tree():
		return
	if approved:
		var approval := PluginLogic.approval(review)
		_set_busy(true)
		var applied := await Backend.plugin_action(approval["action"], approval["values"])
		if not is_inside_tree():
			return
		if Backend.failed(applied):
			_set_busy(false)
			_show_error(applied["error"]["message"])
			return
		_changed = true
		if name.is_empty():
			_source.clear()
	await _load_plugins()


func _toggle(plugin: Dictionary) -> void:
	await _change("configure", {"name": plugin["id"], "values": {"enabled": str(not plugin["enabled"]).to_lower()}})


func _configure(plugin: Dictionary) -> void:
	var values: Variant = await PluginConfigDialog.open(self, plugin)
	if values == null or (values as Dictionary).is_empty():
		return
	await _change("configure", {"name": plugin["id"], "values": values})


func _remove(plugin: Dictionary) -> void:
	if await Dialogs.confirm(self, "Remove %s?" % plugin["name"], "The installed plugin files and its approval will be removed.", "Remove"):
		await _change("remove", {"name": plugin["id"]})


func _change(action: String, values: Dictionary) -> void:
	_show_error("")
	_set_busy(true)
	var result := await Backend.plugin_action(action, values)
	if not is_inside_tree():
		return
	if Backend.failed(result):
		_set_busy(false)
		_show_error(result["error"]["message"])
		return
	_changed = true
	await _load_plugins()


func _restart() -> void:
	if Store.is_playing() and not await Dialogs.confirm(self, "Restart the player?", "Playback will pause briefly while the player restarts and restores your queue.", "Restart"):
		return
	_show_error("")
	_set_busy(true)
	var result := await Backend.restart_owned_engine()
	if not is_inside_tree():
		return
	if Backend.failed(result):
		_set_busy(false)
		_show_error(result["error"]["message"])
		return
	_changed = false
	_set_busy(false)
	_update_note()
	await Store.start()
	if is_inside_tree() and visible:
		_load_commands()


# Commands and key actions

func _build_actions(root: VBoxContainer) -> void:
	_bindings_box = VBoxContainer.new()
	_bindings_box.add_theme_constant_override("separation", 6)
	root.add_child(_bindings_box)
	_commands_box = VBoxContainer.new()
	_commands_box.add_theme_constant_override("separation", 10)
	root.add_child(_commands_box)
	_empty_commands = _hint("")
	_empty_commands.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_empty_commands)
	_run_button = Button.new()
	_run_button.text = "Run plugin command"
	_run_button.accessibility_name = "Run plugin command"
	_run_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_run_button.pressed.connect(func() -> void: _command(""))
	root.add_child(_run_button)
	_render_commands()


func _render_bindings() -> void:
	if _bindings_box == null:
		return
	for child in _bindings_box.get_children():
		_bindings_box.remove_child(child)
		child.queue_free()
	if not Store.plugin_bindings.is_empty():
		_bindings_box.add_child(FormKit.section_title("Key actions"))
	for binding in Store.plugin_bindings:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var description := Util.text(binding.get("description"), "Keyboard action")
		button.text = "%s   %s · %s" % [description, Util.text(binding.get("plugin")), Util.text(binding.get("key"))]
		button.accessibility_name = "Run key action %s" % description
		button.accessibility_description = "%s, key %s" % [Util.text(binding.get("plugin")), Util.text(binding.get("key"))]
		var key := Util.text(binding.get("key"))
		button.pressed.connect(func() -> void: await Store.run("plugin.key", {"name": key}))
		_bindings_box.add_child(button)


func _load_commands() -> void:
	_command_generation += 1
	var generation := _command_generation
	if not Store.supports("plugin.commands"):
		_commands = []
		_render_commands()
		return
	var result: Variant = await Store.run("plugin.commands")
	if generation != _command_generation or not is_inside_tree():
		return
	_commands = []
	if result != null and (result as Dictionary).get("items") is Array:
		for item in result["items"]:
			_commands.append(str(item))
	_render_commands()


func _render_commands() -> void:
	for child in _commands_box.get_children():
		_commands_box.remove_child(child)
		child.queue_free()
	_run_button.visible = Store.supports("plugin.call")
	_empty_commands.visible = _commands.is_empty()
	_empty_commands.text = ("Your player, extended\nNo plugin commands are registered. Install or enable plugins above, then restart the engine." \
		if Store.supports("plugin.commands") else "Your player, extended\nPlugins are unavailable in the current engine.")
	for command in _commands:
		var button := Button.new()
		button.text = command
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.accessibility_name = "Run plugin command %s" % command
		button.pressed.connect(func() -> void: _command(command))
		_commands_box.add_child(button)


func _command(command: String) -> void:
	var request: Variant = await PluginCommandDialog.open(self, command)
	if request == null:
		return
	var result: Variant = await Store.run("plugin.call", {"name": request["name"], "sub": request["sub"], "args": request["args"]})
	if result != null:
		await Dialogs.message(self, "Plugin result", Util.text((result as Dictionary).get("output"), "Command completed."))
