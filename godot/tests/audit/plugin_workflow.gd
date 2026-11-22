extends AuditKit
## Test with a local, disposable plugin. The fixture registers audit-fixture.echo.

func run() -> void:
	var url := OS.get_environment("PLUGIN_URL")
	await click_name("Plugins")
	await wait(0.6)
	await enter("Plugin source", url)
	await click_name("Review plugin source")
	var d := await modal()
	if d == null:
		return
	check(d.get_ok_button().disabled, "review requires explicit approval")
	await click(d.get_cancel_button())
	check((await installed()).is_empty(), "declined source is absent")
	await wait(0.4)
	await click_name("Review plugin source")
	d = await modal()
	if d == null:
		return
	await click_name("Approve exact source, hash and permissions")
	await shot_dialogs("review_approved")
	await click(d.get_ok_button())
	await wait(0.7)
	var items := await installed()
	check(items.size() == 1, "approved plugin installed")
	if items.is_empty():
		return
	var name: String = items[0]["name"]
	for action in ["Disable", "Enable"]:
		await click_name(action + ": " + name)
		await wait(0.4)
		check((await installed())[0]["enabled"] == (action == "Enable"), action + " stored")
	await click_name("Review and trust: " + name)
	d = await modal()
	if d == null:
		return
	await click_name("Approve exact source, hash and permissions")
	await click(d.get_ok_button())
	await wait(0.4)
	await click_name("Settings: " + name)
	d = await modal()
	if d == null:
		return
	await click_name("Add setting")
	await enter("New setting name", "test_value")
	await enter("New setting value", "Café")
	await click_name("Add setting")
	await click(d.get_ok_button())
	await wait(0.4)
	check("test_value" in (await installed())[0].get("config_keys", []), "private configuration stored")
	await click_name("Restart player to reload plugins")
	await wait(3)
	var command := find_all(func(c: Control) -> bool: return c is Button and c.accessibility_name.begins_with("Run plugin command "))
	check(not command.is_empty(), "reloaded plugin command is listed")
	if not command.is_empty():
		await click(command[0])
		d = await modal()
		await enter("Arguments (JSON array of strings)", "not JSON")
		await click(d.get_ok_button())
		check(d.visible, "invalid command arguments rejected")
		await enter("Arguments (JSON array of strings)", '["Café"]')
		await click(d.get_ok_button())
		d = await modal()
		if d != null:
			check(by_text("Café", d) != null, "plugin returned exact Unicode argument")
			await click(d.get_ok_button())
	var bindings := find_all(func(c: Control) -> bool: return c is Button and c.accessibility_name.begins_with("Run key action "))
	check(not bindings.is_empty(), "plugin binding visible")
	if not bindings.is_empty():
		await click(bindings[0])
	for approve in [false, true]:
		await click_name("Remove: " + name)
		d = await modal()
		if d == null:
			return
		await click(d.get_ok_button() if approve else d.get_cancel_button())
		await wait(0.5)
		check((await installed()).is_empty() == approve, "remove confirmation " + str(approve))

func modal() -> ConfirmationDialog:
	for i in 100:
		if not dialogs().is_empty():
			return dialogs().back()
		await wait(0.05)
	check(false, "expected modal window")
	return null

func enter(name: String, value: String) -> void:
	var field := await wait_named(name) as LineEdit
	if field == null:
		check(false, "plugin field %s is available on %s (connected %s)" % [name, Store.current_page, Store.connected])
		await shot("missing_plugin_field")
		return
	await click(field)
	field.select_all()
	field.get_viewport().push_text_input(value)

func installed() -> Array:
	return PluginLogic.parse_plugins(await Backend.plugin_action("list"))
