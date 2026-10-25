extends AuditKit
## Clicks every enabled button, option button and menu on every page, captures
## what opens, dismisses it, and returns to the page.

var SKIP: Array = ["clear", "delete", "remove", "quit", "restart"] + Array(OS.get_environment("SKIP_EXTRA").split(","))


func _controls() -> Array:
	return find_all(func(c: Control) -> bool:
		return c is BaseButton and c.is_visible_in_tree() and not (c as BaseButton).disabled and c.get_window() == get_tree().root and c.get_global_rect().size.x > 0 and _in_page(c))


func _in_page(c: Node) -> bool:
	var n := c
	while n != null:
		if n is Page:
			return true
		n = n.get_parent()
	return false


func _label(c: Control) -> String:
	var n := c.accessibility_name
	if n.is_empty():
		n = label_of(c)
	return n


func _skip(name: String) -> bool:
	for s in SKIP:
		if not s.is_empty() and name.to_lower().contains(s):
			return true
	return false


func run() -> void:
	await set_size(1280, 800)
	var paths: Array = []
	var dir := OS.get_environment("MUSIC")
	for f in DirAccess.get_files_at(dir):
		paths.append(dir.path_join(f))
	paths.sort()
	await Store.run("sources.load", {"args": paths, "name": "replace", "play": false, "if_revision": Store.state.get("playlist_revision", 0)})
	var only := OS.get_environment("ONLY_PAGES")
	for page: Dictionary in Pages.LIST:
		if not only.is_empty() and not only.split(",").has(page["id"]):
			continue
		Store.navigate(page["id"])
		await wait(1.5)
		var seen := {}
		var budget := 60
		while budget > 0:
			budget -= 1
			var next: Control = null
			for c: Control in _controls():
				var key := "%s|%s|%s" % [_label(c), c.get_class(), str(c.get_global_rect().position)]
				if seen.has(key) or _skip(_label(c)):
					continue
				seen[key] = true
				next = c
				break
			if next == null:
				break
			var name := _label(next)
			var tag := "%s/%s" % [page["id"], name.left(30)]
			print("CLICK ", tag, " (", next.get_class(), ")")
			await click(next)
			await wait(0.5)
			var popped := false
			if not is_instance_valid(next):
				pass
			elif next is OptionButton or next is MenuButton:
				var pm: PopupMenu = (next as OptionButton).get_popup() if next is OptionButton else (next as MenuButton).get_popup()
				if pm.visible:
					popped = true
					await shot_popup(pm, tag.replace("/", "_"))
					print("   popup items: ", pm.item_count)
					pm.hide()
			if not dialogs().is_empty():
				await shot_dialogs(tag.replace("/", "_"))
				await close_dialogs()
			if Store.current_page != page["id"]:
				print("   navigated to ", Store.current_page)
				Store.navigate(page["id"])
				await wait(1.0)
			if OS.get_environment("NOLINT").is_empty():
				lint("after-click-" + tag)
		await shot("done_" + page["id"])
