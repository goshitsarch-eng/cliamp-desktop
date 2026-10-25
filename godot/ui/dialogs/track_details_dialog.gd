class_name TrackDetailsDialog
extends RefCounted
## Read-only metadata of one track.

const LABELS: Array = [
	["title", "Title"], ["artist", "Artist"], ["album", "Album"], ["genre", "Genre"],
	["year", "Year"], ["track_number", "Track number"], ["station", "Station"],
	["stream_title", "Now playing"], ["path", "Path"],
]


static func open(host: Node, track: Dictionary) -> void:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(500, 360)
	scroll.add_child(_content(track))
	await Dialogs.open(host, Util.text(track.get("title"), "Track details"), scroll, ["Close"], Vector2i(520, 0))


static func _content(track: Dictionary) -> Control:
	var palette := ThemeBuilder.palette
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	for entry: Array in LABELS:
		var value := Util.text(track.get(entry[0]))
		if value.is_empty():
			continue
		var field := VBoxContainer.new()
		field.add_theme_constant_override("separation", 2)
		var caption := Label.new()
		caption.text = entry[1]
		caption.add_theme_color_override("font_color", palette.muted)
		caption.add_theme_font_size_override("font_size", 11)
		field.add_child(caption)
		field.add_child(_selectable(value, entry[1]))
		box.add_child(field)
	var duration := Label.new()
	duration.text = "Duration: %s" % Util.duration_or_unknown(track.get("duration_secs"))
	box.add_child(duration)
	var notes := {
		"dir_sourced": "Included by a directory source",
		"unplayable": "This source cannot play this item.",
		"restricted": "This item requires permission or a subscription.",
	}
	for key: String in notes:
		if track.get(key) == true:
			var note := Label.new()
			note.text = notes[key]
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			box.add_child(note)
	var more := Button.new()
	more.text = "Additional metadata"
	more.toggle_mode = true
	more.alignment = HORIZONTAL_ALIGNMENT_LEFT
	more.accessibility_name = "Additional metadata"
	box.add_child(more)
	var raw := _selectable(JSON.stringify(track, "  "), "Additional metadata")
	raw.visible = false
	more.toggled.connect(func(on: bool) -> void: raw.visible = on)
	box.add_child(raw)
	return box


static func _selectable(text: String, name: String) -> Control:
	var label := RichTextLabel.new()
	label.fit_content = true
	label.selection_enabled = true
	label.context_menu_enabled = true
	label.scroll_active = false
	label.bbcode_enabled = false
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	label.accessibility_name = name
	label.add_theme_color_override("default_color", ThemeBuilder.palette.foreground)
	return label
