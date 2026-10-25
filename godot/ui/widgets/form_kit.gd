class_name FormKit
extends RefCounted
## Small builders shared by the settings and plugin pages.



## A Label in the muted text color. Register it with `track` so a theme change
## recolors it.
static func muted(text: String, size := 12, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 120
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func error_label() -> Label:
	var l := Label.new()
	l.add_theme_color_override("font_color", ThemeBuilder.palette.error)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	l.visible = false
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func set_error(l: Label, text: String) -> void:
	l.text = text
	l.visible = not text.is_empty()


static func heading(title: String, subtitle: String, muted_labels: Array) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 26)
	box.add_child(t)
	var s := muted(subtitle)
	muted_labels.append(s)
	box.add_child(s)
	return box


## Recolors every live label in `labels`, dropping freed ones.
static func recolor(labels: Array) -> void:
	for i in range(labels.size() - 1, -1, -1):
		if not is_instance_valid(labels[i]):
			labels.remove_at(i)
		else:
			(labels[i] as Label).add_theme_color_override("font_color", ThemeBuilder.palette.muted)


## A card: themed PanelContainer with padding around a VBox that is returned.
static func card(content_parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	content_parent.add_child(panel)
	return box


static func section_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	return l


## Builds a fresh ConfirmationDialog, shown by run().
static func make_dialog(title: String, content: Control, ok_text: String, cancel_text: String, min_size: Vector2i) -> ConfirmationDialog:
	var dialog := ConfirmationDialog.new()
	dialog.title = title
	dialog.exclusive = true
	dialog.min_size = Vector2i(Vector2(min_size) * Prefs.ui_scale)
	dialog.get_ok_button().text = ok_text
	dialog.get_cancel_button().text = cancel_text
	dialog.add_child(content)
	return dialog


## Shows `dialog` and returns true when OK was pressed. Frees the dialog.
## `accept`, when valid, is called on OK and returns true to accept; on false
## the dialog stays open (the callback shows its own message).
static func run(host: Node, dialog: ConfirmationDialog, accept := Callable()) -> bool:
	var result := Dialogs.Result.new()
	var done := [false]
	var finish := func(value: bool) -> void:
		if not done[0]:
			done[0] = true
			result.finished.emit(value)
	dialog.confirmed.connect(func() -> void:
		if accept.is_valid() and not accept.call():
			dialog.call_deferred("popup_centered")
			return
		finish.call(true))
	dialog.canceled.connect(finish.bind(false))
	dialog.close_requested.connect(finish.bind(false))
	Util.host(host).add_child(dialog)
	dialog.popup_centered()
	var ok: bool = await result.finished
	dialog.queue_free()
	return ok
