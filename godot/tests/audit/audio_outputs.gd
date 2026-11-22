extends AuditKit
## Windows supplement. Only reselect the active output, or a named test endpoint.

func run() -> void:
	await click_name("Settings")
	await click_name("Refresh audio devices")
	var listing := await Backend.call_op("device", {"name": "list"})
	if OS.get_environment("CLIAMP_QA_AUDIO") == "system":
		check(Backend.failed(listing), "missing switcher is reported")
		for i in 100:
			if _hint_visible():
				break
			await wait(0.1)
		check(_hint_visible(), "Settings explains how to choose the Windows system output")
		check(find_all(func(c: Control) -> bool: return c is Button and c.accessibility_name.ends_with("for audio output")).is_empty(), "unsupported device actions are absent")
		await shot("windows_system_output")
		return
	if Backend.failed(listing):
		check(false, "list Windows playback endpoints: " + Util.text(listing.get("error", {}).get("message")))
		return
	var devices := Util.objects(listing.get("devices"))
	for device in devices:
		var name := Util.text(device.get("name"))
		if device.get("active") != true and name != OS.get_environment("CLIAMP_QA_AUDIO_ENDPOINT"):
			continue
		var label := Util.text(device.get("description"), name)
		var target := "Use %s for audio output" % label
		for _frame in 150:
			if by_name(target) != null:
				break
			await wait(0.1)
		await click_name(target)
		for i in 50:
			if (await Backend.snapshot()).get("device") == name:
				check(true, "selected output matches the listed endpoint")
				for _tick in 30:
					if main._active._device_label.text == label:
						break
					await wait(0.1)
				check(main._active._device_label.text == label, "current output uses the readable device name")
				await shot("windows_selected_output")
				return
			await wait(0.1)
		break
	check(false, "the selected test endpoint is available and applied")


func _hint_visible() -> bool:
	return not find_all(func(c: Control) -> bool: return c is Label and c.text.contains("Windows Settings") and not c.text.contains("Get-AudioDevice")).is_empty()
