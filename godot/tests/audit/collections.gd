extends AuditKit
## Exercise queue batch edits, playlist tools and destructive confirmations on a disposable profile.

func run() -> void:
	var music := OS.get_environment("MUSIC")
	await Store.run("sources.load", {"args":[music], "name":"replace", "play":false})
	await wait(0.6)
	var select := await wait_named("Select tracks")
	select.grab_focus()
	await main._active.refresh()
	check(is_instance_valid(select) and select.has_focus(), "queue toolbar retains focus during a background refresh")
	await select_all_rows()
	await click(by_text("Append"))
	await wait(0.6)
	check((await tracks("queue.list")).size() == 8, "batch append adds four tracks")
	await click_name("Undo last queue edit")
	await wait(0.6)
	check((await tracks("queue.list")).size() == 4, "undo restores original queue")
	await select_all_rows()
	await click(by_text("Play next", main._active))
	await wait(0.6)
	var pending := await tracks("playnext.list")
	check(pending.size() == 4 or (pending.size() == 3 and Store.is_playing()), "batch play next enqueues selection")
	await select_all_rows()
	await click(by_text("Save to playlist"))
	await wait(1)
	await click_name("Place at the beginning")
	await click_name("New playlist")
	var field := await wait_named("Playlist name") as LineEdit
	if field == null:
		check(false, "save selection prompts for a name")
		return
	await click(field)
	field.get_viewport().push_text_input("Batch Café")
	await click(dialogs().back().get_ok_button())
	await wait(0.6)
	check((await saved()).size() == 4, "selection saved into a new local playlist")
	var prior := await tracks("queue.list")
	await select_all_rows()
	await click(by_text("Replace queue"))
	await answer(false)
	check(await tracks("queue.list") == prior, "batch replace cancellation")
	await click(by_text("Replace queue"))
	await answer(true)
	check(Store.is_playing(), "batch replace starts playback")
	await select_all_rows()
	await click(by_text("Remove"))
	await answer(true)
	check((await tracks("queue.list")).is_empty(), "batch remove clears selected tracks")
	await click_name("Undo last queue edit")
	await wait(0.6)
	await click_name("Clear queue")
	await answer(true)
	check((await tracks("queue.list")).is_empty(), "confirmed clear empties the queue")
	await click_name("Undo last queue edit")
	await wait(0.6)
	await click_name("Playlists")
	await wait(0.6)
	var cards := find_all(func(c: Control) -> bool: return c is CollectionCard and c.accessibility_name.contains("Batch Café"))
	if cards.is_empty():
		check(false, "saved playlist appears in browser")
		return
	var card: CollectionCard = cards[0]
	card.grab_focus()
	await main._active.refresh()
	check(is_instance_valid(card) and card.has_focus(), "unchanged playlist card retains focus after refresh")
	if not is_instance_valid(card):
		return
	await click(card)
	await wait(0.6)
	await click_name("Playlist tools: files, directories, sorting and undo")
	await wait(0.6)
	for i in PlaylistToolsDialog.SORTS.size():
		var picker := await wait_named("Sort by") as OptionButton
		if picker == null:
			check(false, "playlist tools are open")
			return
		await click(picker)
		await pick_item(picker.get_popup(), i)
		await click_name("Sort and save")
		await wait_named("Sort by")
		check((await saved()).size() == 4, "sorting preserves all entries / " + str(PlaylistToolsDialog.SORTS[i][1]))
	var before := await saved()
	await click(await wait_named("Move track down"))
	await wait_named("Sort by")
	check((await saved())[1].get("path") == before[0].get("path"), "move down persists")
	await click(all_named("Move track up")[1])
	await wait_named("Sort by")
	check((await saved())[0].get("path") == before[0].get("path"), "move up persists")
	await click_name("Undo last playlist edit")
	await wait(0.5)
	await wait_named("Undo last playlist edit")
	await click(by_name("Refresh", dialogs().back()))
	await wait(0.5)
	var manage: ConfirmationDialog = dialogs().back()
	for i in 80:
		if not manage.get_ok_button().disabled:
			break
		await wait(0.1)
	await click(manage.get_ok_button())
	for i in 80:
		if dialogs().is_empty():
			break
		await wait(0.1)
	check(dialogs().is_empty(), "Done closes playlist tools after refresh")
	await click_name("Load collection")
	await wait(0.6)
	if not dialogs().is_empty():
		await answer(true)
	check((await tracks("queue.list")).size() == 4, "load collection restores queue")
	await click_name("History")
	await wait(0.5)
	if by_name("Clear history") != null:
		await click_name("Clear history")
		await answer(true)
		check(by_name("Clear history") == null, "confirmed history clear removes rows")

func select_all_rows() -> void:
	if by_name("Select visible") != null:
		await click_name("Finish selecting")
	await click_name("Select tracks")
	await click_name("Select visible")
	await wait(0.2)

func tracks(operation: String, params := {}) -> Array:
	return Util.objects((await Backend.call_op(operation, params)).get("tracks"))

func saved() -> Array:
	return await tracks("provider.tracks", {"provider":"local", "playlist":"Batch Café", "limit":200})

func answer(yes: bool) -> void:
	await wait(0.4)
	if dialogs().is_empty():
		check(false, "confirmation is displayed")
		return
	var d: ConfirmationDialog = dialogs().back()
	await click(d.get_ok_button() if yes else d.get_cancel_button())
	await wait(0.6)
