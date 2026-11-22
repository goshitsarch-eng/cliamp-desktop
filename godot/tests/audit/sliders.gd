extends AuditKit

func run() -> void:
	await Store.run("sources.load", {"args":[OS.get_environment("MUSIC")], "name":"replace", "play":true})
	await wait(0.6)
	await drag_slider(by_name("Volume"), 0.82, 0.35)
	var current := await Backend.snapshot()
	check(Util.number(current.get("volume")) < -15.0, "volume drag reaches the engine")
	await drag_slider(by_name("Seek"), 0.1, 0.65)
	current = await Backend.snapshot()
	check(Util.number(current.get("position")) > 48 and Util.number(current.get("position")) < 70, "seek drag reaches the engine")
	await click_name("Equalizer")
	await wait(0.4)
	await drag_slider(by_name("1k Hz band"), 0.5, 0.12)
	check(EqLogic.band_values(await Backend.snapshot())[4] > 4, "EQ drag updates 1 kHz")
	await click_name("Reset equalizer to Flat")
	# Exercise the narrow layout as a constrained desktop would present it.
	get_window().min_size = Vector2i(660, 540)
	await set_size(740, 600)
	await wait(0.6)
	var more := by_name("Playback options") as MenuButton
	var old_bookmark: bool = Store.track().get("bookmark") == true
	for i in 2:
		await click(more)
		var popup := more.get_popup()
		var index := popup.get_item_index(0)
		if index < 0:
			check(false, "narrow transport exposes favorite")
			break
		await pick_item(popup, index)
		await wait(0.6)
		check((Store.track().get("bookmark") == true) == (not old_bookmark if i == 0 else old_bookmark), "narrow favorite toggles")
	await menu_pick(more, "Adjust volume...", "compact_volume")
	var before := Util.number((await Backend.snapshot()).get("volume"))
	var slider := by_name("Volume in decibels")
	if slider != null:
		await click(slider)
		await key(KEY_END)
		await click(dialogs().back().get_cancel_button())
		check(Util.number((await Backend.snapshot()).get("volume")) == before, "cancel volume preserves original level")
	Prefs.set_ui_scale(1.0)

func drag_slider(slider: Slider, start: float, ending: float) -> void:
	if slider == null:
		check(false, "drag target visible")
		return
	var root := get_tree().root
	var horizontal := slider is HSlider
	var rect := slider.get_global_rect()
	var pos := rect.position + rect.size * (Vector2(start, 0.5) if horizontal else Vector2(0.5, start))
	var to := rect.position + rect.size * (Vector2(ending, 0.5) if horizontal else Vector2(0.5, ending))
	var move := InputEventMouseMotion.new()
	move.position = pos
	move.global_position = pos
	root.push_input(move, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	event.position = pos
	event.global_position = pos
	root.push_input(event, true)
	for i in range(1, 6):
		var next := pos.lerp(to, i / 5.0)
		move = InputEventMouseMotion.new()
		move.position = next
		move.global_position = next
		move.relative = (to - pos) / 5.0
		move.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(move, true)
		await frames(1)
	event.pressed = false
	event.button_mask = 0
	event.position = to
	event.global_position = to
	root.push_input(event, true)
	await wait(0.6)
