class_name AuditKit
extends Node
## Windowed audit helpers: boots the real shell, sends real mouse and key events
## through the viewport, saves screenshots and lints the layout. Scenarios extend
## this and override `run()`. Needs a real cliamp (CLIAMP_BINARY) and SHOT_DIR.

var main: Control
var shot_dir := ""
var findings: Array[String] = []
var _shot_count := 0


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
	var deadline := Time.get_ticks_msec() + 45000
	while not Store.connected and Time.get_ticks_msec() < deadline:
		await wait(0.1)
	await frames(3)
	get_window().grab_focus()
	await wait(0.3)


func finish() -> void:
	var f := FileAccess.open(shot_dir.path_join("findings.txt"), FileAccess.WRITE)
	f.store_string("\n".join(findings))
	f.close()
	print("audit: %d finding(s)" % findings.size())
	if not dialogs().is_empty():
		await close_dialogs()
	await Backend.close()
	get_tree().quit(0 if findings.is_empty() else 1)


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


func wait_named(accessibility: String) -> Control:
	var c := by_name(accessibility)
	for i in 80:
		if c != null and not (c is BaseButton and c.disabled):
			return c
		await wait(0.1)
		c = by_name(accessibility)
	return null


func click_name(accessibility: String) -> void:
	var c := await wait_named(accessibility)
	if c == null:
		check(false, "no visible control named '%s'" % accessibility)
		return
	await click(c)


func click(c: Control, button := MOUSE_BUTTON_LEFT, offset := Vector2.ZERO) -> void:
	if c == null:
		check(false, "click target missing")
		return
	# Group expansion queues a layout pass. Scrolling against the old extent
	# can leave the next editor underneath the transport on a slow display.
	await frames(2)
	if not is_instance_valid(c):
		check(false, "control disappeared before scrolling")
		return
	var ancestor := c.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(c)
		ancestor = ancestor.get_parent()
	await frames(2)
	if not is_instance_valid(c):
		check(false, "control disappeared before click")
		return
	var win := c.get_window()
	var local_input := win.is_embedded() and not (c is OptionButton or c is MenuButton)
	var vp := get_tree().root if win.is_embedded() else win
	var pos := vp.get_screen_transform().affine_inverse() * c.get_screen_transform() * (c.size / 2.0 + offset)
	if not get_tree().root.gui_embed_subwindows:
		win.grab_focus()
		vp.warp_mouse(pos)
		await frames(2)
	var move := InputEventMouseMotion.new()
	move.window_id = vp.get_window_id()
	move.position = pos
	move.global_position = pos
	move.relative = Vector2.ONE
	move.velocity = Vector2(60, 60)
	if local_input:
		vp.push_input(move, true)
	else:
		Input.parse_input_event(move)
		await frames(1)
	if not is_instance_valid(c):
		check(false, "control disappeared during pointer motion")
		return
	var activated := [false]
	var observe := func() -> void: activated[0] = true
	var button_target := c as BaseButton
	var description := "%s (%s)" % [c.accessibility_name, label_of(c)]
	if button_target != null and not button_target.disabled:
		button_target.pressed.connect(observe)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.window_id = vp.get_window_id()
		event.pressed = pressed
		event.position = pos
		event.global_position = pos
		event.button_mask = 0 if not pressed else (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT)
		if local_input:
			vp.push_input(event, true)
		else:
			Input.parse_input_event(event)
			# Keep a short test click inside Godot's popup grab threshold even
			# on a slow or unfocused display. Dispatch both edges in order.
			Input.flush_buffered_events()
	await frames(2)
	if is_instance_valid(button_target) and button_target.pressed.is_connected(observe):
		button_target.pressed.disconnect(observe)
		var opened: bool = (c is OptionButton or c is MenuButton) and c.get_popup().visible
		if not activated[0] and not opened:
			print("missed target ", description, " point ", pos, " window ", win.size, " hovered ", win.gui_get_hovered_control())
			await shot("missed_pointer_" + str(_shot_count))
		check(activated[0] or opened, "pointer activates " + description)


func key(code: Key, ctrl := false, alt := false, shift := false, unicode := 0) -> void:
	var win := get_window()
	var open := dialogs()
	if not open.is_empty() and not (open.back() as Window).is_embedded():
		win = open.back()
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.physical_keycode = code
		e.pressed = pressed
		e.ctrl_pressed = ctrl
		e.alt_pressed = alt
		e.shift_pressed = shift
		e.unicode = unicode
		e.window_id = win.get_window_id()
		Input.parse_input_event(e)
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
	return await pick_item(popup, found)


## Use pointer hit testing in an embedded popup. Native menus receive keyboard events.
func pick_item(popup: PopupMenu, index: int) -> bool:
	var label := popup.get_item_text(index)
	var selected := [-1]
	var observe := func(id: int) -> void: selected[0] = id
	var expected := popup.get_item_id(index)
	if not popup.visible:
		# A fast mouse release over a popup can dismiss it. Reopen through the
		# focused picker and verify both visibility and the resulting selection.
		print("Popup dismissed before selection; reopening with the keyboard: ", label)
		var owner := popup.get_parent() as BaseButton
		if owner != null and owner.has_focus():
			await key(KEY_SPACE)
		if not is_instance_valid(popup) or not popup.visible:
			check(false, "menu closed before choosing " + label)
			return false
	popup.id_pressed.connect(observe)
	if popup.is_embedded():
		popup.scroll_to_item(index)
		await frames(2)
		popup.set_focused_item(-1)
		var root := get_tree().root
		var at := Vector2.ZERO
		for y in range(6, popup.size.y - 2, 5):
			at = root.get_screen_transform().affine_inverse() * popup.get_screen_transform() * Vector2(popup.size.x / 2.0, y)
			var move := InputEventMouseMotion.new()
			move.position = at
			move.global_position = at
			move.relative = Vector2(0, 5)
			move.velocity = Vector2(0, 300)
			root.push_input(move, true)
			if popup.get_focused_item() == index:
				for pressed in [true, false]:
					var event := InputEventMouseButton.new()
					event.button_index = MOUSE_BUTTON_LEFT
					event.pressed = pressed
					event.position = at
					event.global_position = at
					root.push_input(event, true)
				break
	else:
		for i in popup.item_count + 1:
			if popup.get_focused_item() == index:
				break
			await popup_key(popup, KEY_DOWN)
		if popup.get_focused_item() == index:
			await popup_key(popup, KEY_ENTER)
	await frames(2)
	if is_instance_valid(popup):
		popup.id_pressed.disconnect(observe)
		if popup.visible:
			popup.hide()
	check(selected[0] == expected, "select menu item " + label)
	await wait(0.15)
	return selected[0] == expected


func popup_key(popup: PopupMenu, code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.window_id = popup.get_window_id()
		if popup.is_embedded():
			get_tree().root.push_input(event, true)
		else:
			Input.parse_input_event(event)
		await frames(1)


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
	for w in get_tree().root.find_children("*", "Window", true, false):
		if not w is Popup and (w as Window).visible:
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
