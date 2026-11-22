extends AuditKit

func run() -> void:
	await set_size(1280, 800)
	await Store.run("sources.load", {"args":[OS.get_environment("MUSIC")], "name":"replace", "play":true})
	await click(by_name("Search"))
	var seen := {}
	for i in 120:
		await key(KEY_TAB)
		var control := get_viewport().gui_get_focus_owner()
		if control == null:
			continue
		if control is MenuButton and not seen.has(control.accessibility_name):
			var name := control.accessibility_name
			seen[name] = true
			await key(KEY_ENTER)
			check(control.get_popup().visible, "Tab and Enter open " + name)
			await key(KEY_ESCAPE)
		if seen.has("Playback speed") and seen.has("Playback options") and seen.has("Track actions"):
			break
	check(seen.has("Playback speed") and seen.has("Playback options") and seen.has("Track actions"), "all queue and transport menus in Tab order")
	await key(KEY_TAB, false, false, true)
	check(get_viewport().gui_get_focus_owner() != null, "Shift+Tab returns focus")
	await key(KEY_F, true)
	await type_text("Café")
	await key(KEY_LEFT)
	await key(KEY_DELETE)
	check((by_name("Search") as LineEdit).text == "Caf", "Delete edits search at cursor")
	await key(KEY_BACKSPACE)
	await key(KEY_ESCAPE)
	await key(KEY_RIGHT, true)
	await wait(0.6)
	await key(KEY_LEFT, true)
	await wait(0.6)
	await key(KEY_RIGHT, false, true)
	await wait(0.4)
	check(Util.number((await Backend.snapshot()).get("position")) >= 9, "Alt+Right seeks ahead")
	await key(KEY_LEFT, false, true)
	await key(KEY_R, true)
	await key(KEY_S, true)
	await key(KEY_Z, true)
	await wait(0.5)
