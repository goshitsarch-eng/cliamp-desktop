extends AuditKit
## Plugins source input, Settings preference form validation and persistence,
## and Tab-key traversal.


func _page_text() -> Array:
	return find_all(func(c: Control) -> bool: return c is Label and c.is_visible_in_tree() and (c as Label).text.length() > 0).map(func(l: Label) -> String: return l.text.left(90))


func run() -> void:
	await set_size(1280, 800)
	Store.navigate("plugins")
	await wait(1.2)
	var src := by_name("Plugin source") as LineEdit
	if src == null:
		for c in find_all(func(c: Control) -> bool: return c is LineEdit and c.is_visible_in_tree()):
			print("lineedit: ", c.accessibility_name, " / ", (c as LineEdit).placeholder_text)
		src = find_all(func(c: Control) -> bool: return c is LineEdit and c.is_visible_in_tree() and c.get_window() == get_tree().root)[1]
	for value in ["", "   ", "not a url", "owner/does-not-exist", "http://127.0.0.1:1/x.lua", "ftp://example.com/x.lua", "C:\\Windows\\System32\\drivers\\etc\\hosts", "x".repeat(600), "'; DROP TABLE plugins; --", "日本語/プラグイン"]:
		src.text = value
		await click_name("Review plugin source")
		await wait(1.8)
		var dlg := dialogs()
		print("plugin source '%s' -> dialogs=%d" % [value.left(30), dlg.size()])
		if not dlg.is_empty():
			await shot_dialogs("plugin_review_" + str(value.length()))
			await close_dialogs()
		else:
			print("   page text: ", _page_text().filter(func(t: String) -> bool: return t.contains("rror") or t.contains("not") or t.contains("could") or t.contains("Enter")))
	await shot("plugins_after_inputs")
	lint("plugins-after-inputs")

	# Run plugin command with empty input
	await click_name("Run plugin command")
	await wait(0.6)
	await shot_dialogs("plugin_command")
	await close_dialogs()

	# Settings preferences form
	Store.navigate("settings")
	await wait(1.5)
	var edits := find_all(func(c: Control) -> bool: return c is LineEdit and c.is_visible_in_tree() and c.get_window() == get_tree().root)
	for e: LineEdit in edits:
		print("settings lineedit: '", e.accessibility_name, "' placeholder='", e.placeholder_text, "' text='", e.text, "'")
	var buttons := find_all(func(c: Control) -> bool: return c is BaseButton and c.is_visible_in_tree() and c.get_window() == get_tree().root and c.accessibility_name.to_lower().contains("save") or c.accessibility_name.to_lower().contains("discard"))
	print("save/discard buttons: ", buttons.map(func(b: Control) -> String: return b.accessibility_name))

	# Tab traversal: list focus order on the queue page
	Store.navigate("queue")
	await wait(1.0)
	var first := by_name("Search") as Control
	first.grab_focus()
	var order: Array[String] = []
	for i in 40:
		await key(KEY_TAB)
		var f := get_viewport().gui_get_focus_owner()
		if f == null:
			order.append("<none>")
			break
		order.append("%s#%s" % [f.get_class(), f.accessibility_name if not f.accessibility_name.is_empty() else label_of(f)])
	print("tab order: ", order)
	await shot("tab_focus")
