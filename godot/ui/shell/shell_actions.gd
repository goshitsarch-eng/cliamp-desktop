class_name ShellActions
extends RefCounted
## Verbs shared by the player bar, shortcuts and the command palette.


static func favorite(track: Dictionary) -> void:
	if track.is_empty():
		return
	var result: Variant = await Store.run("playlist.bookmark", {"provider": "local", "track": track})
	if result != null:
		Store.lists_stale.emit()


static func download() -> void:
	var result: Variant = await Store.run("save")
	if result != null:
		var output := Util.text(result.get("output"))
		Store.notify("Track downloaded" if output.is_empty() else "Saved to %s" % output)


static func jump_to_time(host: Node) -> void:
	if not Store.connected or Store.state.get("seekable") != true:
		return
	var path := Util.text(Store.track().get("path"))
	var target: Variant = await SeekDialog.open(host, Store.position(), Util.number(Store.state.get("duration")))
	if target == null:
		return
	if not Store.connected or Store.state.get("seekable") != true or Util.text(Store.track().get("path")) != path:
		Store.notify("The playing track changed. Open Jump to time again.")
		return
	await Store.run("seek.absolute", {"value": target})


static func volume_floor() -> float:
	var current := Util.number(Store.state.get("volume"))
	return clampf(Util.number(Store.state.get("volume_min"), minf(-50.0, current)), -90.0, 0.0)


static func adjust_volume(host: Node) -> void:
	var minimum := volume_floor()
	var value := clampf(Util.number(Store.state.get("volume")), minimum, 6.0)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	var label := Label.new()
	label.text = "%.1f dB" % value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = 6.0
	slider.step = 0.5
	slider.value = value
	slider.accessibility_name = "Volume in decibels"
	slider.custom_minimum_size = Vector2(0, 28)
	SliderStyle.apply(slider)
	slider.value_changed.connect(func(v: float) -> void: label.text = "%.1f dB" % v)
	box.add_child(slider)
	var chosen: Variant = await Dialogs.open(host, "Volume", box, ["Apply", "Cancel"], Vector2i(360, 0))
	if chosen != null:
		await Store.run("volume", {"value": slider.value})
