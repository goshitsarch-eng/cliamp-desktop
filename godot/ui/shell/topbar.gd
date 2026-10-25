class_name ShellTopbar
extends MarginContainer
## Search box, background activity, command palette and Add music.

signal add_requested
signal palette_requested
signal jobs_requested

var compact := false
var _search: LineEdit
var _search_row: HBoxContainer
var _explore: Label
var _tagline: Label
var _add: Button
var _icon: Label
var _wide := true


func _init() -> void:
	add_theme_constant_override("margin_top", 22)
	add_theme_constant_override("margin_bottom", 18)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)

	var left := Control.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.custom_minimum_size = Vector2(0, 42)
	row.add_child(left)
	_search_row = HBoxContainer.new()
	_search_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_search_row.add_theme_constant_override("separation", 0)
	left.add_child(_search_row)
	_search = LineEdit.new()
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.accessibility_name = "Search"
	_search.placeholder_text = "Search your music..."
	_search.text_changed.connect(func(text: String) -> void: Store.set_filter(text))
	_search.text_submitted.connect(func(text: String) -> void: Store.search_submitted.emit(text))
	_search.gui_input.connect(_on_search_input)
	_search_row.add_child(_search)
	_explore = Label.new()
	_explore.text = "Explore your music"
	_explore.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_explore.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_explore.add_theme_font_size_override("font_size", 16)
	left.add_child(_explore)

	row.add_child(Icons.button("task_alt", "Background activity", func() -> void: jobs_requested.emit()))
	row.add_child(Icons.button("keyboard", "Keyboard shortcuts and commands", func() -> void: palette_requested.emit()))
	_tagline = Label.new()
	_tagline.text = "ALL YOUR MUSIC. ONE PLACE."
	_tagline.add_theme_font_size_override("font_size", 10)
	_tagline.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tagline)
	_add = Button.new()
	_add.text = "Add music"
	_add.accessibility_name = "Add music"
	_add.custom_minimum_size = Vector2(0, 42)
	_add.pressed.connect(func() -> void: add_requested.emit())
	row.add_child(_add)
	set_compact(false)


func _ready() -> void:
	Store.connection_changed.connect(_refresh)
	Store.navigate_requested.connect(func(_id: String) -> void: call_deferred("_refresh"))
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: _restyle())
	_restyle()
	_refresh()


func set_compact(value: bool) -> void:
	compact = value
	var side := 20 if value else 32
	add_theme_constant_override("margin_left", side)
	add_theme_constant_override("margin_right", side)
	_add.text = "Add" if value else "Add music"
	_update_tagline()


## Called with the window width so the tagline can hide on narrow windows.
func set_width(width: float) -> void:
	_wide = width >= 1120
	_update_tagline()


func _update_tagline() -> void:
	_tagline.visible = not compact and _wide


## Shows the search box, or the heading that replaces it on the Providers page.
func update_for_page(page_id: String) -> void:
	var browse := page_id == "providers" and Store.supports("provider.browse")
	_search.visible = not browse
	_explore.visible = browse
	_search.placeholder_text = "Search this provider..." if page_id == "providers" else "Search your music..."


func clear_search() -> void:
	_search.text = ""
	Store.set_filter("")


func focus_search() -> bool:
	if not _search.is_visible_in_tree():
		return false
	_search.grab_focus()
	_search.select_all()
	return true


func has_text() -> bool:
	return not _search.text.is_empty()


func _refresh() -> void:
	_add.disabled = not Store.connected
	update_for_page(Store.current_page)


func _on_search_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		clear_search()
		_search.release_focus()
		_search.accept_event()


func _restyle() -> void:
	var p := ThemeBuilder.palette
	_tagline.add_theme_color_override("font_color", p.muted)
	var style := StyleBoxFlat.new()
	style.bg_color = p.accent
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = p.accent.lightened(0.12)
	var disabled := style.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(p.foreground, 0.12)
	_add.add_theme_stylebox_override("normal", style)
	_add.add_theme_stylebox_override("hover", hover)
	_add.add_theme_stylebox_override("pressed", hover)
	_add.add_theme_stylebox_override("disabled", disabled)
	_add.add_theme_color_override("font_color", p.on_accent())
	_add.add_theme_color_override("font_hover_color", p.on_accent())
	_add.add_theme_color_override("font_pressed_color", p.on_accent())
	_add.add_theme_color_override("font_focus_color", p.on_accent())
	_add.add_theme_color_override("font_disabled_color", p.muted)
