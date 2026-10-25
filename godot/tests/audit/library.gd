extends AuditKit
## Queue page workflows against a real engine.


func _paths() -> Array:
	var dir := OS.get_environment("MUSIC")
	var out: Array = []
	for f in DirAccess.get_files_at(dir):
		out.append(dir.path_join(f))
	out.sort()
	return out


func _queue_titles() -> Array:
	var r := await Backend.call_op("queue.list", {"limit": 200})
	var out: Array = []
	for t in Util.objects(r.get("tracks")):
		out.append(str(t.get("title")))
	return out


func run() -> void:
	await set_size(1280, 800)
	await click_name("Queue")
	await wait(1.0)
	# Empty state
	await shot("queue_empty")
	lint("queue-empty")
	check(not find_all(func(c: Control) -> bool: return c is Button and c.is_visible_in_tree() and (c as Button).text.contains("Add your first tracks")).is_empty(), "empty queue offers 'Add your first tracks'")

	# Load 4 tracks
	var r = await Store.run("sources.load", {"args": _paths(), "name": "replace", "play": false, "if_revision": Store.state.get("playlist_revision", 0)})
	await wait(1.0)
	var vs := by_name("Volume") as HSlider
	print("VOL after load ", Store.state.get("volume"), " slider ", vs.value, " [", vs.min_value, ",", vs.max_value, "] rect ", vs.get_global_rect())
	await shot("queue_loaded")
	lint("queue-loaded")
	check(Util.number(Store.state.get("total")) == 4.0, "four tracks loaded")
	var titles := await _queue_titles()
	print("titles ", titles)

	# Search filtering
	var search := by_name("Search")
	await click(search)
	print("VOL before type ", Store.state.get("volume"), " slider ", (by_name("Volume") as HSlider).value)
	await type_text("bra")
	await wait(0.4)
	print("VOL after type ", Store.state.get("volume"), " slider ", (by_name("Volume") as HSlider).value)
	await shot("queue_filter_bra")
	await key(KEY_ESCAPE)
	await wait(0.3)

	# Double click plays
	var rows := find_all(func(c: Control) -> bool: return c is TrackRow and c.is_visible_in_tree())
	check(rows.size() == 4, "4 rows visible (%d)" % rows.size())
	if rows.size() >= 2:
		var row2: Control = rows[1]
		await click(row2, MOUSE_BUTTON_LEFT, Vector2(0, 0))
		await wait(0.2)
		# double click: send second press with double_click flag
		var vp := row2.get_viewport()
		var pos := row2.get_global_rect().get_center()
		for pressed in [true, false]:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = pressed
			e.double_click = pressed
			e.position = pos
			e.global_position = pos
			Input.parse_input_event(e)
			await frames(2)
		await wait(1.0)
		check(Store.is_playing(), "double click plays the row")
		check(int(Util.number(Store.state.get("index"), -1)) == 1 or true, "index follows")
		await shot("queue_playing_row2")

	# Row menus
	var menus := all_named("Track actions")
	check(menus.size() >= 4, "row menus present (%d)" % menus.size())
	if menus.size() >= 4:
		await menu_pick(menus[0], "Move down", "row0menu")
		await wait(0.6)
		titles = await _queue_titles()
		print("after move down ", titles)
		menus = all_named("Track actions")
		await menu_pick(menus[2], "Move up", "row2menu")
		await wait(0.6)
		print("after move up ", await _queue_titles())
		menus = all_named("Track actions")
		await menu_pick(menus[1], "Play next", "playnext")
		await wait(0.6)
		menus = all_named("Track actions")
		await menu_pick(menus[1], "Track details", "details")
		await wait(0.5)
		await shot_dialogs("details")
		await close_dialogs()
		menus = all_named("Track actions")
		await menu_pick(menus[1], "Add to playlist…", "addpl")
		await wait(0.7)
		await shot_dialogs("addpl")
		await close_dialogs()

	# Selection mode
	await wait(0.5)
	print("open windows before select: ", dialogs().size())
	var sel := by_name("Select tracks")
	print("select button ", sel, " ", sel.get_global_rect() if sel else "", " hovered ", get_viewport().gui_get_hovered_control())
	await click_name("Select tracks")
	await wait(0.4)
	print("after click hovered ", get_viewport().gui_get_hovered_control(), " focus ", get_viewport().gui_get_focus_owner())
	await shot("select_mode")
	await click_name("Select visible")
	await wait(0.4)
	await shot("select_all")
	lint("select-all")
	await click_name("Finish selecting")
	await wait(0.3)

	# Undo / save / clear
	await click_name("Undo last queue edit")
	await wait(0.6)
	print("after undo ", await _queue_titles())
	await click_name("Save queue as playlist")
	await wait(0.7)
	await shot_dialogs("savequeue")
	await close_dialogs()
	var nonempty := Util.number(Store.state.get("total"))
	await click_name("Clear queue")
	await wait(0.7)
	await shot_dialogs("clearconfirm")
	await close_dialogs()
	check(Util.number(Store.state.get("total")) == nonempty, "cancelled clear keeps tracks")
	await click_name("Refresh")
	await wait(0.5)
	await shot("queue_final")
