extends Node
## Builds the settings and plugin pages and the form widget without an engine,
## to catch script and layout errors. Exits non-zero on failure.
## Run: godot --headless --path godot res://tests/ui_smoke.tscn

var _failures := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failures += 1
		printerr("FAIL: ", what)


func _ready() -> void:
	var form := SchemaForm.new()
	form.load_fields([
		{"key": "volume", "label": "Volume", "group": "Playback", "type": "number", "value": "-5", "min": -90, "max": 6},
		{"key": "repeat", "label": "Repeat", "group": "Playback", "type": "string", "value": "off", "options": ["off", "all"]},
		{"key": "mono", "label": "Mono", "group": "Playback", "type": "bool", "value": "false"},
		{"key": "plugins.disabled", "label": "Disabled", "group": "Plugins", "type": "list", "value": "[\"a\"]"},
		{"key": "token", "label": "Token", "group": "Plugins", "type": "secret"},
		{"key": "theme", "label": "Theme", "group": "Appearance", "type": "string", "value": "nord"},
	])
	var view := SchemaFormView.new()
	add_child(view)
	view.bind(form)
	_check(view.visible_field_count() == 6, "all fields shown")
	view.set_filter("theme")
	_check(view.visible_field_count() == 1, "filter narrows fields")
	view.set_filter("")
	view.set_enabled(false)
	view.show_errors({"volume": "bad"})
	view.edited.connect(func(_k: String) -> void: pass)
	form.set_value("volume", "99")
	view.show_errors(form.validate_changed())

	var settings := SettingsPage.new()
	var plugins := PluginsPage.new()
	add_child(settings)
	add_child(plugins)
	settings.activate()
	plugins.activate()
	for i in 30:
		await get_tree().process_frame
	settings.deactivate()
	plugins.deactivate()
	_check(settings.get_child_count() > 0, "settings built")
	_check(plugins.get_child_count() > 0, "plugins built")
	print("ui_smoke: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
