extends AuditKit

func run() -> void:
	var folder := OS.get_environment("TAGGED_MUSIC")
	await Store.run("sources.load", {"args": [folder.path_join("timed.flac")], "name":"replace", "play":false})
	await click_name("Lyrics")
	await wait(1)
	check(by_text("Thirty seconds") is Label, "timed lyrics readable while stopped")
	check(by_text("Synced lyrics · select a line to seek") == null, "stopped track has no seek invitation")
	await click_name("Play")
	for i in 100:
		if by_name("Thirty seconds") != null:
			break
		await wait(0.05)
	var line := by_name("Thirty seconds")
	check(line is Button, "same track gains clickable lines when seekable")
	if line != null:
		await click(line)
		check(Util.number((await Backend.snapshot()).get("position")) >= 29.9, "click seeks to thirty seconds")
	await click_name("Advance lyrics 250 ms")
	await wait(0.4)
	check((await Backend.snapshot()).get("lyrics_offset_ms") == 250, "lyrics offset applied")
	await click_name("Delay lyrics 250 ms")
	await click_name("Follow lyrics")
	await click_name("Follow lyrics")
	await click_name("Refresh lyrics")
	await wait(0.5)
	await shot("timed_unicode")
	await Store.run("sources.load", {"args":[folder.path_join("plain.flac")], "name":"replace", "play":true})
	await wait(1)
	check(by_text("Plain verse") is Label, "plain lyrics shown without seek controls")
	check(by_name("Advance lyrics 250 ms") == null, "plain lyrics have no offset control")
