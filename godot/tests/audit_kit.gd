class_name AuditKit
extends Node
## Windowed audit helpers: boots the real shell, sends real mouse and key events
## through the viewport, saves screenshots and lints the layout. Scenarios extend
## this and override `run()`. Needs a real cliamp (CLIAMP_BINARY) and SHOT_DIR.

var main: Control
var shot_dir := ""
var findings: Array[String] = []
var _shot_count := 0
var synthetic := 0


func _ready() -> void:
	shot_dir = OS.get_environment("SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(shot_dir)
	await boot()
	await run()
	await finish()


func run() -> void:
	pass


func boot() -> void:
	# Mounted on the root window like the real main scene; under a plain Node,
	# Godot skips the window theme and the shell renders with the default theme.
	main = load("res://ui/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await wait(2.5)
	get_window().grab_focus()
	await wait(0.3)


func finish() -> void:
	var f := FileAccess.open(shot_dir.path_join("findings.txt"), FileAccess.WRITE)
	f.store_string("\n".join(findings))
	f.close()
	print("audit: %d finding(s)" % findings.size())
	await Backend.close()
	get_tree().quit()


func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func note(msg: String) -> void:
	findings.append(msg)
	print("FINDING ", msg)


func set_size(w: int, h: int) -> void:
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.size = Vector2i(w, h)
	await wait(0.4)


func shot(name: String) -> void:
	await frames(2)
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(shot_dir.path_join("%02d_%s.png" % [_shot_count, name]))
	_shot_count += 1


## Screenshot of every open dialog window (native windows are not in the main viewport).
func shot_dialogs(name: String) -> void:
	await frames(3)
	var i := 0
	for d in dialogs():
		RenderingServer.force_draw()
		var img := (d as Window).get_texture().get_image()
		img.save_png(shot_dir.path_join("%02d_%s_win%d.png" % [_shot_count, name, i]))
		i += 1
	_shot_count += 1


func check(cond: bool, what: String) -> void:
	if cond:
		print("ok   ", what)
	else:
		note("CHECK FAILED: " + what)


## Visible, enabled controls anywhere under `root` (default: the shell and every
## open dialog window), matched by predicate.
func find_all(pred: Callable, root: Node = null) -> Array:
	var out: Array = []
	var roots: Array = [root] if root != null else [get_tree().root]
	for r in roots:
		_collect(r, pred, out)
	return out


func _collect(node: Node, pred: Callable, out: Array) -> void:
	if node is CanvasItem and not (node as CanvasItem).visible and not (node is Window):
		return
	if node is Window and not (node as Window).visible:
		return
	if node is Control and pred.call(node):
		out.append(node)
	for c in node.get_children():
		_collect(c, pred, out)


func label_of(c: Control) -> String:
	if c is Button:
		return (c as Button).text
	if c is Label:
		return (c as Label).text
	if c is LineEdit:
		return (c as LineEdit).placeholder_text
	return ""


func by_name(accessibility: String, root: Node = null) -> Control:
	var hits := find_all(func(c: Control) -> bool: return c.accessibility_name == accessibility and c.is_visible_in_tree(), root)
	return hits[0] if not hits.is_empty() else null


func by_text(text: String, root: Node = null) -> Control:
	var hits := find_all(func(c: Control) -> bool: return (c is Button or c is Label) and label_of(c) == text and c.is_visible_in_tree(), root)
	return hits[0] if not hits.is_empty() else null


func window_of(c: Node) -> Window:
	return c.get_window()


func click_name(accessibility: String) -> void:
	var c := by_name(accessibility)
	if c == null:
		note("click: no visible control named '%s'" % accessibility)
		return
	await click(c)


func click(c: Control, button := MOUSE_BUTTON_LEFT, offset := Vector2.ZERO) -> void:
	if c == null:
		note("click: control missing")
		return
	var vp := c.get_viewport()
	if not c.get_window().has_focus():
		c.get_window().grab_focus()
		await wait(0.3)
	var pos := c.get_global_rect().get_center() + offset
	for step in [Vector2(-3, -2), Vector2.ZERO]:
		var move := InputEventMouseMotion.new()
		move.position = pos + step
		move.global_position = pos + step
		move.relative = Vector2(3, 2)
		Input.parse_input_event(move)
		await frames(1)
	if OS.get_environment("AUDIT_DEBUG") != "":
		print("click ", c.accessibility_name, " hovered=", vp.gui_get_hovered_control(), " focus=", vp.gui_get_focus_owner(), " dragging=", vp.gui_is_dragging())
	var fired := [false]
	var watch := Callable()
	if c is BaseButton and not (c is MenuButton) and not (c is OptionButton):
		watch = func() -> void: fired[0] = true
		(c as BaseButton).pressed.connect(watch)
	var menu_open := c is MenuButton or c is OptionButton
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.pressed = true
	down.position = pos
	down.global_position = pos
	down.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	Input.parse_input_event(down)
	await frames(1)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)
	await frames(2)
	if watch.is_valid():
		(c as BaseButton).pressed.disconnect(watch)
		if not fired[0] and not (c as BaseButton).disabled and (c as BaseButton).toggle_mode == false:
			synthetic += 1
			print("synthetic click (window had no hover): ", c.accessibility_name, label_of(c))
			(c as BaseButton).pressed.emit()
			await frames(2)
	elif not (c is BaseButton) and is_instance_valid(c):
		if vp.gui_get_hovered_control() != c and c.has_method("_gui_input"):
			synthetic += 1
			print("synthetic gui_input click: ", c.get_class(), " ", c.accessibility_name)
			var d := InputEventMouseButton.new()
			d.button_index = MOUSE_BUTTON_LEFT
			d.pressed = true
			d.position = c.size / 2.0
			d.global_position = pos
			c.call("_gui_input", d)
			var u := d.duplicate() as InputEventMouseButton
			u.pressed = false
			c.call("_gui_input", u)
			await frames(2)
	elif menu_open:
		var popup: PopupMenu = (c as OptionButton).get_popup() if c is OptionButton else (c as MenuButton).get_popup()
		if not popup.visible and not (c as BaseButton).disabled:
			synthetic += 1
			print("synthetic menu open: ", c.accessibility_name)
			if c is OptionButton:
				(c as OptionButton).show_popup()
			else:
				(c as MenuButton).show_popup()
			await frames(2)


func key(code: Key, ctrl := false, alt := false, shift := false, unicode := 0) -> void:
	var vp: Viewport = get_viewport()
	var open := dialogs()
	if not open.is_empty():
		vp = open.back()
	else:
		var focus := vp.gui_get_focus_owner()
		if focus != null:
			vp = focus.get_viewport()
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		e.alt_pressed = alt
		e.shift_pressed = shift
		e.unicode = unicode
		vp.push_input(e)
		if vp is Window and vp != get_tree().root:
			# Dialogs read Escape/Enter from the OS window event, which push_input skips.
			(vp as Window).window_input.emit(e)
		await frames(1)
	await frames(2)


func type_text(text: String) -> void:
	for i in text.length():
		var ch := text.unicode_at(i)
		await key(OS.find_keycode_from_string(text[i].to_upper()) if ch < 128 else KEY_UNKNOWN, false, false, false, ch)


## Opens a MenuButton with a real click, saves its popup, then picks the entry
## with this text (as the popup would on selection). Returns false when absent.
func menu_pick(button: MenuButton, text: String, tag := "menu") -> bool:
	await click(button)
	await wait(0.3)
	var popup := button.get_popup()
	check(popup.visible, "%s popup opens" % tag)
	await shot_popup(popup, tag)
	var labels: Array[String] = []
	for i in popup.item_count:
		labels.append(popup.get_item_text(i))
	var found := -1
	for i in popup.item_count:
		if popup.get_item_text(i) == text:
			found = i
	if found < 0:
		note("%s: entry '%s' not in %s" % [tag, text, labels])
		popup.hide()
		return false
	if popup.is_item_disabled(found):
		note("%s: entry '%s' is disabled" % [tag, text])
		popup.hide()
		return false
	popup.hide()
	popup.id_pressed.emit(popup.get_item_id(found))
	await wait(0.4)
	return true


func shot_popup(popup: Window, name: String) -> void:
	if not popup.visible:
		return
	RenderingServer.force_draw()
	popup.get_texture().get_image().save_png(shot_dir.path_join("%02d_%s_popup.png" % [_shot_count, name]))
	_shot_count += 1


func all_named(accessibility: String) -> Array:
	return find_all(func(c: Control) -> bool: return c.accessibility_name == accessibility and c.is_visible_in_tree())


func dialogs() -> Array:
	var out: Array = []
	for w in get_tree().root.get_children():
		if w is Window and (w as Window).visible:
			out.append(w)
	return out


func close_dialogs() -> void:
	for d in dialogs():
		d.hide()
		d.close_requested.emit()
	await wait(0.2)
	if not get_window().has_focus():
		get_window().grab_focus()
		await wait(0.3)


## Walks the visible tree and records controls that leave their window or the
## clip rect of an ancestor, and non-wrapping text that does not fit.
func lint(tag: String, root: Node = null) -> void:
	var r: Node = root if root != null else main
	var window_rect := Rect2(Vector2.ZERO, Vector2(r.get_window().size) / r.get_window().content_scale_factor)
	var all := find_all(func(c: Control) -> bool: return c.is_visible_in_tree() and c.size.x > 0 and c.size.y > 0, r)
	for c: Control in all:
		var rect := c.get_global_rect()
		var clip := _clip_rect(c, window_rect)
		if rect.size.x > 0 and (rect.end.x > clip.end.x + 1.5 or rect.position.x < clip.position.x - 1.5):
			if not _inside_scroll(c):
				note("[%s] %s '%s' leaves its clip horizontally: %s vs %s" % [tag, c.get_class(), label_of(c), rect, clip])
		if c is Label:
			var l := c as Label
			if l.text.is_empty() or l.autowrap_mode != TextServer.AUTOWRAP_OFF:
				continue
			var font := l.get_theme_font("font")
			var fs := l.get_theme_font_size("font_size")
			var w := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w > l.size.x + 1.0 and not (l.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING or l.clip_text):
				note("[%s] Label '%s' text %.0fpx wider than box %.0fpx" % [tag, l.text.left(40), w, l.size.x])
			elif w > l.size.x + 1.0 and not _has_tooltip(l):
				note("[%s] Label '%s' is truncated (%.0f > %.0f) with no tooltip" % [tag, l.text.left(40), w, l.size.x])
		elif c is Button:
			var b := c as Button
			if b.text.is_empty() or b.icon != null:
				continue
			var font := b.get_theme_font("font")
			var fs := b.get_theme_font_size("font_size")
			var w := font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if w > b.size.x + 1.0 and not b.clip_text:
				note("[%s] Button '%s' text %.0fpx wider than box %.0fpx" % [tag, b.text.left(40), w, b.size.x])


func _has_tooltip(c: Control) -> bool:
	var n: Node = c
	while n is Control:
		if not (n as Control).tooltip_text.is_empty() and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			return true
		n = n.get_parent()
	return false


func _inside_scroll(c: Control) -> bool:
	var n := c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return true
		n = n.get_parent()
	return false


func _clip_rect(c: Control, window_rect: Rect2) -> Rect2:
	var rect := window_rect
	var n := c.get_parent()
	while n != null:
		if n is Control and ((n as Control).clip_contents or n is ScrollContainer):
			rect = rect.intersection((n as Control).get_global_rect())
		n = n.get_parent()
	return rect
