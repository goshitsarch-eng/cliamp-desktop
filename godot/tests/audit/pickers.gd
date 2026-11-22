extends AuditKit
## Activate each menu item through the displayed popup, then compare its result
## with the independent engine snapshot. Run with --single-window for pointer replay.

func run() -> void:
	await set_size(1280, 800)
	var path := OS.get_environment("SHOT_WAV")
	await Store.run("sources.load", {"args": [path], "name": "replace", "play": true})
	await _speeds()
	await click_name("Equalizer")
	var preset := by_name("Equalizer preset") as OptionButton
	for step in preset.item_count:
		var index := preset.item_count - step - 1
		await click(preset)
		await pick_item(preset.get_popup(), index)
		var value := preset.get_item_text(index)
		check((await Backend.snapshot()).get("eq_preset") == value, "engine EQ preset " + value)
	for i in EqLogic.BANDS:
		var slider := by_name(EqLogic.LABELS[i] + " Hz band") as VSlider
		await click(slider)
		await key(KEY_END)
		await wait(0.4)
		check(EqLogic.band_values(await Backend.snapshot())[i] == 12, "keyboard adjusts " + slider.accessibility_name)
	await click_name("Reset equalizer to Flat")
	await click_name("Visualizer")
	await wait(1)
	for label in ["Visualizer", "Theme"]:
		var options := find_all(func(c: Control) -> bool: return c is OptionButton and c.accessibility_name == label)
		var picker: OptionButton = options[0]
		for i in picker.item_count:
			await click(picker)
			await pick_item(picker.get_popup(), i)
			for frame in 100:
				if not picker.disabled:
					break
				await frames(1)
			var expected := picker.get_item_text(i)
			var snap := await Backend.snapshot()
			var actual: String = Util.text(snap.get("visualizer")) if label == "Visualizer" else Util.text(Util.object(snap.get("theme")).get("name"))
			check(actual == expected, "%s preview %s (engine %s)" % [label, expected, actual])
	await click(by_text("Cancel preview"))
	var page = main._active
	check(not page._restoring or page._next_btn.disabled, "preview controls wait for cancellation to finish")
	await wait(0.4)
	await click_name("Next visualizer")
	await wait(0.3)
	await click_name("Apply appearance")
	await click_name("Enter fullscreen visualizer")
	await wait(0.6)
	check(not dialogs().is_empty(), "fullscreen opens")
	if not dialogs().is_empty():
		var fs: Window = dialogs().back()
		for tip in ["Hide track information (T)", "Show track information (T)", "Previous track (,)", "Next track (.)", "Seek back 5 seconds (Left)", "Seek forward 5 seconds (Right)", "Lower volume (-)", "Raise volume (+)", "Next visualizer"]:
			var b := by_name(tip, fs)
			if b != null and not (b as Button).disabled:
				await click(b)
				await wait(0.2)
		for code in [KEY_T, KEY_V, KEY_MINUS, KEY_EQUAL, KEY_LEFT, KEY_RIGHT, KEY_COMMA, KEY_PERIOD, KEY_SPACE, KEY_ESCAPE]:
			await key(code)
			await wait(0.2)
		check(dialogs().is_empty(), "Escape exits fullscreen")
	await shot("visualizer_after_fullscreen")


func _speeds() -> void:
	var speed := by_name("Playback speed") as MenuButton
	await click(speed)
	var count := speed.get_popup().item_count
	for i in count:
		if i > 0:
			await click(speed)
		var popup := speed.get_popup()
		var expected := popup.get_item_text(i).trim_suffix("x").to_float()
		await pick_item(popup, i)
		check(is_equal_approx(Util.number((await Backend.snapshot()).get("speed")), expected), "playback speed %s" % expected)
	var more := by_name("Playback options") as MenuButton
	await click(more)
	count = more.get_popup().item_count
	for i in count:
		if i > 0:
			await click(more)
		var popup := more.get_popup()
		var label := popup.get_item_text(i)
		await pick_item(popup, i)
		if label.begins_with("Adjust volume"):
			var slider := by_name("Volume in decibels")
			await click(slider)
			await key(KEY_HOME)
			var d: ConfirmationDialog = dialogs().back()
			await click(d.get_ok_button())
			await wait(0.4)
			check(Util.number((await Backend.snapshot()).get("volume")) == ShellActions.volume_floor(), "volume dialog applies")
