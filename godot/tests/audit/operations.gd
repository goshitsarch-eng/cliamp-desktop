extends AuditKit
## Exercise the operation browser without submitting destructive operations.

func run() -> void:
	await click_name("Settings")
	await wait(1)
	await click_name("Browse engine operations")
	var picker := by_name("Engine operation") as OptionButton
	if picker == null:
		check(false, "engine operation dialog opens")
		return
	var d := picker.get_window() as ConfirmationDialog
	var readonly_index := -1
	for i in picker.item_count:
		await click(picker)
		await pick_item(picker.get_popup(), i)
		check(picker.selected == i, "operation details " + picker.get_item_text(i))
		if picker.get_item_text(i) == "queue.list":
			readonly_index = i
	await click(picker)
	await pick_item(picker.get_popup(), readonly_index)
	var edit := by_name("Parameters as a JSON object", d) as TextEdit
	for invalid in ["", "[]", "{a", "日本語"]:
		await click(edit)
		edit.select_all()
		edit.get_viewport().push_text_input(invalid if invalid != "" else " ")
		await click(d.get_ok_button())
		check(by_text("Enter a JSON object.", d) != null and d.visible, "invalid parameters keep dialog open")
	await click(edit)
	edit.select_all()
	edit.get_viewport().push_text_input('{"limit":1}')
	await click(d.get_ok_button())
	await wait(0.8)
	check(not dialogs().is_empty() and dialogs().back().title == "Operation result", "read-only operation returns result dialog")
	if not dialogs().is_empty():
		await click(dialogs().back().get_ok_button())
