extends AuditKit
## Large operation results must keep their text and dismissal control reachable.

func run() -> void:
	var lines: PackedStringArray = []
	for i in 300:
		lines.append("Track %03d   -   Café 日本語" % i)
	Dialogs.message(main, "Operation result", "\n".join(lines))
	await wait(0.4)
	var d: ConfirmationDialog = dialogs().back()
	print("result window ", d.size, " parent ", get_window().size)
	await shot_dialogs("large_result")
	check(d.size.y <= get_window().size.y, "long operation result fits parent height")
	var viewer := by_name("Message", d) as TextEdit
	check(viewer != null and not viewer.editable, "long operation result can scroll and be copied")
	if viewer != null:
		await click(viewer)
		viewer.set_caret_line(viewer.get_line_count() - 1)
		await frames(2)
		check(viewer.scroll_vertical > 0 and viewer.get_line(299).begins_with("Track 299"), "last item reachable inside the result")
	await key(KEY_ESCAPE)
	check(dialogs().is_empty(), "long result dismisses with Escape")
	for i in 5:
		Store.notice.emit("Notice %d" % i, false)
	await frames(2)
	check(all_named("Dismiss notice").size() == 3, "at most three notices remain visible")
	await click_name("Dismiss notice")
	await wait(4.3)
	check(all_named("Dismiss notice").is_empty(), "dismissed and displaced notices retire cleanly")
