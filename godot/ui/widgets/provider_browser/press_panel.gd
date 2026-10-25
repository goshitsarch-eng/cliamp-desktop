class_name PressPanel
extends PanelContainer
## A panel that acts as one button: chips and list rows with child controls.
## Labels inside ignore the mouse, so a click anywhere outside child buttons
## presses the panel. Enter and Space press it while focused.

signal pressed

var disabled := false:
	set(value):
		disabled = value
		mouse_default_cursor_shape = Control.CURSOR_ARROW if value else Control.CURSOR_POINTING_HAND
		modulate.a = 0.5 if value else 1.0
		_apply_style()

var _normal: StyleBox
var _hover: StyleBox
var _is_hover := false
var _focus: StyleBoxFlat


func _init(normal: StyleBox = null, hover: StyleBox = null, focus_color := Color.WHITE) -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_normal = normal
	_hover = hover if hover != null else normal
	_focus = StyleBoxFlat.new()
	_focus.draw_center = false
	_focus.border_color = focus_color
	_focus.set_border_width_all(2)
	_focus.set_corner_radius_all(10)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_apply_style()


func _on_hover(inside: bool) -> void:
	_is_hover = inside
	_apply_style()


func _apply_style() -> void:
	var style := _hover if _is_hover and not disabled else _normal
	if style != null:
		add_theme_stylebox_override("panel", style)


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		pressed.emit()
	elif event.is_action_pressed("ui_accept"):
		accept_event()
		pressed.emit()


func _draw() -> void:
	if has_focus():
		draw_style_box(_focus, Rect2(Vector2.ZERO, size))
