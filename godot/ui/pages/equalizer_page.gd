extends Page
## Ten-band equalizer with presets. Dragging a band previews its value; the
## engine is only told on release ('eq' with band and value), as in app.dart.

var _preset: OptionButton
var _sliders: Array[VSlider] = []
var _db_labels: Array[Label] = []
var _muted_labels: Array[Label] = []
var _top_icon: Label
var _dragging: Array[bool] = []
var _building := true


func _init() -> void:
	super()
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 14)
	scroll.add_child(root)

	var title := Label.new()
	title.text = Pages.LIST[Pages.index_of("equalizer")]["title"]
	title.add_theme_font_size_override("font_size", 26)
	root.add_child(title)
	var sub := Label.new()
	sub.text = "A ten-band equalizer, shaped around your sound."
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
	_muted_labels.append(sub)
	root.add_child(sub)

	var card := PanelContainer.new()
	root.add_child(card)
	var inner := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		inner.add_theme_constant_override("margin_" + side, 22)
	card.add_child(inner)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	inner.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	_top_icon = Icons.label("equalizer", 22, ThemeBuilder.palette.accent)
	top.add_child(_top_icon)
	var heading := Label.new()
	heading.text = "Equalizer"
	heading.add_theme_font_size_override("font_size", 16)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	_preset = OptionButton.new()
	_preset.accessibility_name = "Equalizer preset"
	_preset.custom_minimum_size = Vector2(180, 0)
	for p in EqLogic.PRESETS:
		_preset.add_item(p)
	_preset.item_selected.connect(_on_preset)
	top.add_child(_preset)
	top.add_child(Icons.button("restart_alt", "Reset equalizer to Flat", _on_reset))

	var bands := HBoxContainer.new()
	bands.custom_minimum_size = Vector2(0, 270)
	bands.add_theme_constant_override("separation", 4)
	col.add_child(bands)
	for i in EqLogic.BANDS:
		_dragging.append(false)
		var c := VBoxContainer.new()
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bands.add_child(c)
		var db := Label.new()
		db.text = EqLogic.db_text(0.0)
		db.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		db.add_theme_font_size_override("font_size", 10)
		db.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
		c.add_child(db)
		_db_labels.append(db)
		_muted_labels.append(db)
		var s := VSlider.new()
		s.min_value = EqLogic.MIN_DB
		s.max_value = EqLogic.MAX_DB
		s.step = 1.0
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
		s.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		s.accessibility_name = "%s Hz band" % EqLogic.LABELS[i]
		s.drag_started.connect(func() -> void: _dragging[i] = true)
		s.drag_ended.connect(func(changed: bool) -> void: _on_drag_ended(i, changed))
		s.value_changed.connect(func(v: float) -> void: _on_value_changed(i, v))
		c.add_child(s)
		_sliders.append(s)
		var f := Label.new()
		f.text = EqLogic.LABELS[i]
		f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		f.add_theme_font_size_override("font_size", 11)
		f.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
		_muted_labels.append(f)
		c.add_child(f)
	var axis := Label.new()
	axis.text = "Frequency · Hz"
	axis.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	axis.add_theme_font_size_override("font_size", 10)
	axis.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
	_muted_labels.append(axis)
	col.add_child(axis)

	var spectrum_card := PanelContainer.new()
	root.add_child(spectrum_card)
	var sm := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		sm.add_theme_constant_override("margin_" + side, 20)
	spectrum_card.add_child(sm)
	var spectrum := SpectrumView.new()
	spectrum.custom_minimum_size = Vector2(160, 110)
	sm.add_child(spectrum)

	_building = false
	Store.state_changed.connect(func(_s: Dictionary) -> void: _sync())
	ThemeBuilder.palette_changed.connect(_recolor)
	_sync()


func _recolor(_p: Palette) -> void:
	var p := ThemeBuilder.palette
	_top_icon.add_theme_color_override("font_color", p.accent)
	for l in _muted_labels:
		l.add_theme_color_override("font_color", p.muted)


func activate() -> void:
	_sync()


func _sync() -> void:
	var values := EqLogic.band_values(Store.state)
	for i in EqLogic.BANDS:
		if _dragging[i]:
			continue
		_sliders[i].set_value_no_signal(values[i])
		_db_labels[i].text = EqLogic.db_text(values[i])
	var name := EqLogic.preset_or_flat(Store.state)
	_preset.select(EqLogic.PRESETS.find(name))


func _on_value_changed(band: int, value: float) -> void:
	_db_labels[band].text = EqLogic.db_text(value)
	# Keyboard and wheel changes have no drag; commit them directly.
	if not _dragging[band] and not _building:
		_commit(band, value)


func _on_drag_ended(band: int, _changed: bool) -> void:
	_dragging[band] = false
	_commit(band, EqLogic.snap_db(_sliders[band].value))


func _commit(band: int, value: float) -> void:
	await Store.run("eq", {"band": band, "value": value})
	if not _dragging[band]:
		_sync()


func _on_preset(index: int) -> void:
	await Store.run("eq", {"name": EqLogic.PRESETS[index]})
	_sync()


func _on_reset() -> void:
	await Store.run("eq", {"name": "Flat"})
	_sync()
