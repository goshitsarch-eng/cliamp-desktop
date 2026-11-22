extends AuditKit

func run() -> void:
	await Store.run("sources.load", {"args":[OS.get_environment("MUSIC")], "name":"replace", "play":true})
	await wait(0.6)
	for page_name in ["Queue", "Play next"]:
		await click_name("Queue")
		await wait(0.7)
		if page_name == "Play next":
			for i in 3:
				await menu_pick(all_named("Track actions")[i], "Play next", "enqueue_for_next")
				await wait(0.3)
			await click_name("Play next")
		await wait(0.6)
		var entries := all_named("Track actions")
		if entries.size() < 2:
			check(false, page_name + " has rows to test")
			return
		var menu: MenuButton = entries[1]
		await click(menu)
		await main._active.refresh()
		check(menu.get_popup().visible, page_name + " row menu survives a refresh of the same tracks")
		var labels: Array[String] = []
		for i in menu.get_popup().item_count:
			labels.append(menu.get_popup().get_item_text(i))
		menu.get_popup().hide()
		await wait(0.5)
		for title in labels:
			# The preceding command can change the track assigned to this row.
			# Wait for the page to read that edit before opening another track.
			await main._active.refresh()
			for i in 60:
				if not main._active._loading and main._active._list_revision == Store.playlist_revision():
					break
				await wait(0.1)
			entries = all_named("Track actions")
			if entries.is_empty():
				check(false, page_name + " has a row for " + title)
				return
			var index := 1 if title == "Move up" else 0
			await menu_pick(entries[mini(index, entries.size() - 1)], title, page_name + "_" + title)
			await wait(0.4)
			if title in ["Add to playlist…", "Track details"]:
				for i in 60:
					if not dialogs().is_empty():
						break
					await wait(0.1)
				if dialogs().is_empty():
					check(false, title + " displays its dialog")
					return
				var dialog: ConfirmationDialog = dialogs().back()
				await click(dialog.get_cancel_button() if dialog.get_cancel_button().visible else dialog.get_ok_button())
				await wait(0.5)
			if Store.current_page != ("queue" if page_name == "Queue" else "next"):
				await click_name(page_name)
				await wait(0.5)
			for toast in all_named("Dismiss notice"):
				if is_instance_valid(toast):
					await click(toast)
	await click_name("Queue")
	await wait(0.7)
	await click_name("Select tracks")
	var rows := find_all(func(c: Control) -> bool: return c is TrackRow)
	if rows.size() >= 3:
		await click(rows[0])
		var shift := InputEventKey.new()
		shift.keycode = KEY_SHIFT
		shift.physical_keycode = KEY_SHIFT
		shift.pressed = true
		Input.parse_input_event(shift)
		await frames(2)
		await click(rows[2])
		shift.pressed = false
		Input.parse_input_event(shift)
		await frames(2)
		check(by_text("3 selected") != null, "Shift selects a contiguous range")
	await click_name("Finish selecting")
