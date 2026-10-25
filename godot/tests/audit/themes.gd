extends AuditKit
## Applies light and dark engine themes and captures the shell, a dialog and a popup.


func run() -> void:
	await set_size(1280, 800)
	var paths: Array = []
	var dir := OS.get_environment("MUSIC")
	for f in DirAccess.get_files_at(dir):
		paths.append(dir.path_join(f))
	paths.sort()
	await Store.run("sources.load", {"args": paths, "name": "replace", "play": true, "if_revision": Store.state.get("playlist_revision", 0)})
	await wait(1.0)
	for theme in OS.get_environment("THEMES").split(","):
		var r = await Store.run("desktop.theme", {"name": theme})
		await wait(0.8)
		print("theme ", theme, " applied=", r != null, " bg=", ThemeBuilder.palette.background.to_html(), " fg=", ThemeBuilder.palette.foreground.to_html(), " accent=", ThemeBuilder.palette.accent.to_html(), " dark=", ThemeBuilder.palette.dark)
		Store.navigate("queue")
		await wait(0.8)
		await shot("queue_" + theme)
		var menus := all_named("Track actions")
		if not menus.is_empty():
			await click(menus[0])
			await wait(0.3)
			await shot_popup((menus[0] as MenuButton).get_popup(), "menu_" + theme)
			(menus[0] as MenuButton).get_popup().hide()
		Store.navigate("settings")
		await wait(1.2)
		await shot("settings_" + theme)
		AddSourceDialog.run(main)
		await wait(0.6)
		await shot_dialogs("add_" + theme)
		await close_dialogs()
	await Store.run("desktop.theme", {"name": "Default - Terminal colors"})
