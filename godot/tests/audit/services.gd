extends AuditKit
## Walk the live catalog and the provider setup schemas. Do not submit credentials.

func run() -> void:
	await set_size(1280, 800)
	await click_name("Providers")
	await wait(0.6)
	var provider := by_name("Provider") as OptionButton
	for i in provider.item_count:
		await click(provider)
		await pick_item(provider.get_popup(), i)
		await wait(0.4)
		check(provider.selected == i, "provider browser " + provider.get_item_text(i))
		var search := find_all(func(c: Control) -> bool: return c is LineEdit and c.is_visible_in_tree())
		if not search.is_empty():
			await click(search.back())
			await type_text("Café")
			await key(KEY_ENTER)
			await wait(0.3)
		await shot("browser_" + str(i))
	await click_name("Connect service")
	await wait(0.5)
	var chooser := by_name("Music service") as OptionButton
	if chooser == null:
		check(false, "service setup opens")
		return
	var count := chooser.item_count
	for i in range(1, count):
		chooser = by_name("Music service") as OptionButton
		await click(chooser)
		var name := chooser.get_item_text(i)
		await pick_item(chooser.get_popup(), i)
		await wait(0.35)
		chooser = by_name("Music service") as OptionButton
		check(chooser != null and chooser.text == name, "setup form " + name)
		var d: Window = dialogs().back()
		var types := find_all(func(c: Control) -> bool: return c is OptionButton and c != chooser, d)
		var branches: int = 1 if types.is_empty() else types[0].item_count
		for j in branches:
			if not types.is_empty():
				var choices := find_all(func(c: Control) -> bool: return c is OptionButton and c.accessibility_name != "Music service", d)
				var variant_picker: OptionButton = choices[0]
				await click(variant_picker)
				await pick_item(variant_picker.get_popup(), j)
				await wait(0.3)
			var fields := find_all(func(c: Control) -> bool: return c is LineEdit, d)
			for field: LineEdit in fields:
				await click(field)
				field.select_all()
				await type_text("Café")
				check(field.text == "Café", "setup field %s / %s" % [name, field.accessibility_name])
		await shot_dialogs("setup_" + str(i))
	await click(by_text("Cancel", dialogs().back()))
	await wait(0.4)
	check(dialogs().is_empty(), "cancel setup returns to providers")
