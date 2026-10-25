extends AuditKit
## Phase 1 changes settings and window state, phase 2 (relaunch, same profile)
## verifies they persisted. PHASE=1|2.


func _edit(name: String) -> LineEdit:
	return by_name(name) as LineEdit


func run() -> void:
	var phase := OS.get_environment("PHASE")
	if phase == "1":
		await set_size(1280, 800)
	Store.navigate("settings")
	await wait(1.5)
	if phase == "1":
		# invalid values
		var vol := _edit("Volume")
		var errors_before := find_all(func(c: Control) -> bool: return c is Label and c.is_visible_in_tree() and (c as Label).text.contains("Range")).size()
		for bad in ["abc", "999", "-999", "", "1e3", "   "]:
			vol.text = bad
			vol.text_changed.emit(bad)
			await wait(0.3)
			var msgs := find_all(func(c: Control) -> bool: return c is Label and c.is_visible_in_tree() and c.get_parent() != null and c.modulate.a > 0 and (c as Label).text != "" and ThemeBuilder.palette.error.is_equal_approx((c as Label).get_theme_color("font_color")))
			print("volume '%s' -> errors: %s" % [bad, msgs.map(func(l: Label) -> String: return l.text)])
		await shot("settings_invalid_volume")
		# valid change and save
		vol.text = "-6"
		vol.text_changed.emit("-6")
		_edit("Seek large step sec").text = "45"
		_edit("Seek large step sec").text_changed.emit("45")
		await wait(0.3)
		await click_name("Save preference changes")
		await wait(2.0)
		print("after save, volume field: ", _edit("Volume").text, " state volume: ", Store.state.get("volume"))
		await shot("settings_saved")
		# interface scale
		var scale := by_name("Interface scale") as HSlider
		scale.value = 1.25
		await wait(2.0)
		print("ui_scale now: ", Prefs.ui_scale)
		await set_size(1500, 900)
		await wait(0.5)
		Prefs.save()
		var mono := by_name("Mono audio") as CheckButton
		mono.button_pressed = true
		await wait(0.8)
		print("mono state: ", Store.state.get("mono"))
	else:
		print("PHASE2 volume field: ", _edit("Volume").text, " seek: ", _edit("Seek large step sec").text)
		print("PHASE2 ui_scale: ", Prefs.ui_scale, " window size: ", get_window().size, " mode: ", get_window().mode)
		print("PHASE2 mono: ", Store.state.get("mono"), " volume state: ", Store.state.get("volume"))
		await shot("settings_relaunch")
		Prefs.set_ui_scale(1.0)
		await Store.run("mono", {"name": "off"})
