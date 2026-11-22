extends AuditKit
## The loopback server delays a playlist response long enough to cancel its job.

func run() -> void:
	await click_name("Add music")
	var source := by_name("File, folder, playlist, URL, or ssh:// path") as TextEdit
	if source == null:
		check(false, "add sources editor appears")
		return
	await click(source)
	source.get_viewport().push_text_input(OS.get_environment("STREAM_URL") + "/slow.pls")
	await click(dialogs().back().get_ok_button())
	await wait(0.6)
	await click_name("Background activity")
	var cancel: Button
	for i in 40:
		cancel = by_name("Cancel operation")
		if cancel != null and not cancel.disabled:
			break
		await wait(0.1)
	if cancel == null or cancel.disabled:
		check(false, "slow import offers a live Cancel operation")
		return
	var ids := {}
	for job: BackendJob in Backend.current_jobs():
		if job.is_active():
			ids[job.id] = true
	cancel.grab_focus()
	await wait(1.2)
	if not is_instance_valid(cancel) or not cancel.has_focus():
		check(false, "Cancel keeps keyboard focus as the elapsed time updates")
		return
	check(true, "Cancel keeps keyboard focus as the elapsed time updates")
	await click(cancel)
	var canceled := false
	for i in 80:
		for job: BackendJob in Backend.current_jobs():
			if ids.has(job.id) and job.state == "canceled":
				canceled = true
		if canceled:
			break
		await wait(0.1)
	check(canceled, "engine acknowledges cancellation of active import")
	await shot_dialogs("cancelled_import")
	await click(dialogs().back().get_ok_button())
