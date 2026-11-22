extends "res://tests/audit/catalog.gd"
## Optional integration against a disposable local Navidrome with a tagged album.

func run() -> void:
	await click_name("Providers")
	await click_name("Connect service")
	await wait(0.5)
	var services := by_name("Music service") as OptionButton
	await click(services)
	await pick_item(services.get_popup(), 1)
	await wait(0.4)
	for setting in [["Server URL *", "CLIAMP_QA_NAVIDROME_URL"], ["Username *", "CLIAMP_QA_NAVIDROME_USER"], ["Password *", "CLIAMP_QA_NAVIDROME_PASSWORD"]]:
		var field := by_name(setting[0]) as LineEdit
		await click(field)
		field.get_viewport().push_text_input(OS.get_environment(setting[1]))
	await click_name("Save provider")
	for i in 80:
		if by_name("Restart player") != null:
			break
		await wait(0.1)
	if by_name("Restart player") == null:
		check(false, "real server validates supplied test account")
		return
	await click_name("Restart player")
	await wait(3)
	var picker := by_name("Provider") as OptionButton
	var idx := -1
	for i in picker.item_count:
		if picker.get_item_text(i).to_lower().contains("navidrome"):
			idx = i
	if idx < 0:
		check(false, "server registered after successful setup")
		return
	await click(picker)
	await pick_item(picker.get_popup(), idx)
	var b: ProviderBrowser = find_all(func(c: Control) -> bool: return c is ProviderBrowser)[0]
	await settle(b)
	await click(by_name("Artists", b))
	await settle(b)
	if not await open_record(b, "QA Ensemble"):
		return
	if not await open_record(b, "Studio audit"):
		return
	check(b._items.size() == 2, "drilling through artist and album returns both tracks")
	await shot("album_tracks")
	await click(by_name("Add collection to queue", b))
	await settle(b)
	check(Util.number((await Backend.snapshot()).get("total")) == 2, "server collection appended to queue")
	var menu := by_name("Track actions", b) as MenuButton
	if menu == null:
		check(false, "server album has a track menu")
		return
	var options: Array[String] = []
	for i in menu.get_popup().item_count:
		options.append(menu.get_popup().get_item_text(i))
	for option in options:
		menu = by_name("Track actions", b)
		if menu == null:
			break
		await menu_pick(menu, option, "server_track")
		await settle(b)
		if option in ["Add to playlist...", "Track details"]:
			for i in 50:
				if not dialogs().is_empty():
					break
				await wait(0.1)
			if not dialogs().is_empty():
				var d: ConfirmationDialog = dialogs().back()
				if option == "Track details":
					check(d.size.y <= get_window().size.y, "server track details fit parent height")
					await click(by_name("Additional metadata", d))
					await shot_dialogs("server_track_details")
					await click(by_name("Additional metadata", d))
				await click(d.get_cancel_button() if d.get_cancel_button().visible else d.get_ok_button())
				await wait(0.3)
		if b._view.kind != "tracks" and by_name("Back to previous collection", b) != null:
			await click(by_name("Back to previous collection", b))
			await settle(b)
	var heart := by_name("Favorite track", b)
	if heart != null:
		await click(heart)
		await settle(b)
		var changed := by_name("Remove track favorite", b)
		check(changed != null, "server track favorite appears in the collection")
		if changed != null:
			await click(changed)
			await settle(b)
	await click(by_name("Albums", b))
	await settle(b)
	var sort := by_name("Sort", b) as OptionButton
	if sort != null:
		var names := sort.item_count
		for i in names:
			sort = by_name("Sort", b)
			await click(sort)
			await pick_item(sort.get_popup(), i)
			await settle(b)
	await click(by_name("Artists", b))
	await settle(b)
	if not await open_record(b, "QA Ensemble") or not await open_record(b, "Studio audit"):
		return
	await click(by_name("Play collection", b))
	for i in 80:
		if Store.is_playing() and Store.current_page == "queue":
			break
		await wait(0.1)
	check(Store.is_playing() and Store.current_page == "queue", "server collection starts playback in queue")
	await wait(1)
	check(Util.number((await Backend.snapshot()).get("position")) > 0, "server audio advances")
	await shot("server_playback")
	# Leave the fixture playing past the engine's reporting threshold. A
	# server play-count readback can then verify submission independently.
	var first_title := Util.text(Store.track().get("title"))
	var duration := Util.number(Store.state.get("duration"))
	if duration <= 0 or duration > 180:
		check(false, "server fixture has a short known duration")
		return
	await wait(duration / 2.0 + 2.0)
	check(Store.position() >= duration / 2.0, "server recording played past halfway")
	await click_name("Next track")
	for i in 50:
		if Store.is_playing() and Util.text(Store.track().get("title")) != first_title:
			break
		await wait(0.1)
	check(Store.is_playing() and Util.text(Store.track().get("title")) != first_title, "server advances to another recording")
	await wait(1.0)

func open_record(browser: ProviderBrowser, title: String) -> bool:
	var rows := find_all(func(c: Control) -> bool: return c is PressPanel and c.accessibility_name.begins_with(title), browser)
	check(not rows.is_empty(), "browse record " + title)
	if rows.is_empty():
		return false
	await click(rows[0])
	await settle(browser)
	return true
