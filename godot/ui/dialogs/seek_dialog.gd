class_name SeekDialog
extends RefCounted
## "Jump to time". Returns an absolute target in seconds only after valid
## confirmation; null when cancelled. The caller owns the playback change.


## Parses seconds, mm:ss or hh:mm:ss like the terminal jump. Omitted clock
## components (":49", "58:", "1::03") count as zero. Returns -1.0 when invalid.
static func parse_time(input: String) -> float:
	var text := input.strip_edges()
	if text.is_empty():
		return -1.0
	var parts := text.split(":")
	if parts.size() > 3:
		return -1.0
	var target := 0.0
	for i in parts.size():
		var part := parts[i].strip_edges()
		if part.is_empty() and parts.size() > 1:
			part = "0"
		if not part.is_valid_int() or part.begins_with("-") or part.begins_with("+"):
			return -1.0
		var value := part.to_int()
		if i > 0 and (part.length() > 2 or value > 59):
			return -1.0
		target = target * 60.0 + value
	return target


static func clock(seconds: float) -> String:
	if is_nan(seconds) or is_inf(seconds) or seconds < 0.0:
		return "-"
	var total := int(floor(seconds))
	var hours := total / 3600
	var minutes := total / 60
	if hours == 0:
		return "%d:%02d" % [minutes, total % 60]
	return "%d:%02d:%02d" % [hours, minutes % 60, total % 60]


static func validate(input: String, duration: float) -> String:
	if is_nan(duration) or is_inf(duration) or duration < 0.0:
		return "The track duration is unavailable."
	var target := parse_time(input)
	if target < 0.0:
		return "Enter a nonnegative time in seconds, mm:ss, or hh:mm:ss."
	if target > duration:
		return "Time must be at or before %s." % clock(duration)
	return ""


static func open(host: Node, position: float, duration: float) -> Variant:
	var safe_duration := duration if not is_nan(duration) and not is_inf(duration) and duration >= 0.0 else 0.0
	var initial := clock(clampf(position, 0.0, safe_duration))
	var error_text := ""
	var typed := [initial]
	while true:
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(380, 0)
		var label := Label.new()
		label.text = "Time"
		box.add_child(label)
		var edit := LineEdit.new()
		edit.text = initial
		edit.placeholder_text = "1:23"
		edit.select_all_on_focus = true
		edit.accessibility_name = "Time"
		edit.accessibility_description = "Seconds, mm:ss, or hh:mm:ss."
		edit.text_changed.connect(func(t: String) -> void: typed[0] = t)
		edit.text_submitted.connect(func(_t: String) -> void: DialogUtil.accept(box))
		box.add_child(edit)
		var helper := Label.new()
		helper.text = "Seconds, mm:ss, or hh:mm:ss.\nTrack duration: %s" % clock(duration)
		helper.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
		helper.add_theme_font_size_override("font_size", 12)
		box.add_child(helper)
		var error := DialogUtil.error_label()
		error.text = error_text
		box.add_child(error)
		DialogUtil.focus(edit)
		var chosen: Variant = await Dialogs.open(host, "Jump to time", box, ["Jump", "Cancel"], Vector2i(420, 0))
		if chosen == null:
			return null
		initial = typed[0]
		error_text = validate(initial, duration)
		if error_text.is_empty():
			return parse_time(initial)
	return null
