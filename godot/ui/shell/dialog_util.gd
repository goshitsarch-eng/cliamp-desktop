class_name DialogUtil
extends RefCounted
## Small helpers for content shown inside Dialogs.open().


## Presses the OK button of the dialog that holds `content`, as Enter would.
static func accept(content: Node) -> void:
	var window := content.get_window()
	if window is AcceptDialog:
		(window as AcceptDialog).get_ok_button().pressed.emit()


## Moves keyboard focus to `control` once its dialog is shown.
static func focus(control: Control) -> void:
	control.call_deferred("grab_focus")


static func error_label() -> Label:
	var error := Label.new()
	error.add_theme_color_override("font_color", ThemeBuilder.palette.error)
	error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return error
