extends AuditKit
## Use disposable credentials against an unavailable loopback endpoint.
func run() -> void:
	await click_name("Providers")
	await click_name("Connect service")
	await wait(0.6)
	var picker := by_name("Music service") as OptionButton
	await click(picker)
	await pick_item(picker.get_popup(), 1)
	await wait(0.4)
	await click_name("Save provider")
	check(by_text("This field is required.") != null, "missing provider credentials explained")
	for label in ["Server URL *", "Username *", "Password *"]:
		var field := by_name(label) as LineEdit
		await click(field)
		field.select_all()
		field.get_viewport().push_text_input("http://127.0.0.1:1" if label == "Server URL *" else "audit-fixture")
	await click_name("Save provider")
	for i in 100:
		if by_name("Save without connection check") != null:
			break
		await wait(0.1)
	check(by_name("Save without connection check") != null, "failed service probe offers explicit offline save")
	await click_name("Save without connection check")
	await wait(0.5)
	check(not dialogs().is_empty() and dialogs().back().title == "Your provider is configured", "offline save is confirmed")
	await click_name("Restart player")
	await wait(3)
	check(Store.providers.any(func(p: Dictionary) -> bool: return p.get("key") == "navidrome"), "configured provider registered after restart")
	var providers := by_name("Provider") as OptionButton
	check(range(providers.item_count).any(func(i: int) -> bool: return providers.get_item_text(i).to_lower().contains("navidrome")), "configured provider appears without leaving the page")
