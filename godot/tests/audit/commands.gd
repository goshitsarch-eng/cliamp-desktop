extends AuditKit
## Activate each built-in palette entry from its rendered tree.

func run() -> void:
	await Store.run("sources.load", {"args":[OS.get_environment("MUSIC")], "name":"replace", "play":true})
	await click_name("Keyboard shortcuts and commands")
	var palette := by_name("Commands") as Tree
	if palette == null:
		check(false, "palette has a command tree")
		return
	var names: Array[String] = []
	for item in palette.get_root().get_children():
		names.append(item.get_text(0))
	await key(KEY_ESCAPE)
	for title in names:
		await click_name("Keyboard shortcuts and commands")
		await wait(0.2)
		palette = by_name("Commands")
		var field := by_name("Find a command") as LineEdit
		if field == null or palette == null:
			check(false, "palette is available for " + title)
			return
		await click(field)
		field.select_all()
		await type_text(title)
		await wait(0.15)
		await frames(3)
		var item := palette.get_selected()
		if item == null or item.get_text(0) != title:
			check(false, "filter selects %s (text %s, selected %s)" % [title, field.text, item.get_text(0) if item != null else "<none>"])
			return
		var hit := palette.get_item_area_rect(item, 0).get_center()
		await click(palette, MOUSE_BUTTON_LEFT, hit - palette.size / 2.0)
		await wait(0.35)
		check(by_name("Find a command") == null, "activate command " + title)
		if title.begins_with("Open "):
			check(main._active.visible and title == "Open " + Pages.LIST[Pages.index_of(Store.current_page)]["label"], "destination " + title)
		if title == "Compact player":
			check(main._compact_player, "palette opens compact player")
			await key(KEY_ESCAPE)
		if not dialogs().is_empty():
			await key(KEY_ESCAPE)
		for toast in all_named("Dismiss notice"):
			if is_instance_valid(toast):
				await click(toast)
	await click_name("Keyboard shortcuts and commands")
	var search := by_name("Find a command") as LineEdit
	if search != null:
		await click(search)
		await type_text("No command")
		check(by_text("No matching commands") != null, "empty palette search")
	await key(KEY_ESCAPE)
