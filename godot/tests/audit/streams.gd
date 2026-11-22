extends "res://tests/audit/sources.gd"

func run() -> void:
	var url := OS.get_environment("STREAM_URL")
	var folder := OS.get_environment("STREAM_FIXTURES")
	var inputs := [folder.path_join("read-only.wav"), url + "/tone.wav", url + "/test.pls", url + "/stream.m3u8"]
	var ssh_source := OS.get_environment("CLIAMP_QA_SSH_SOURCE")
	if not ssh_source.is_empty():
		inputs.append(ssh_source)
	for fixture in inputs:
		await load_source(fixture, true)
		var snapshot := {}
		var expected_path: String = url + "/tone.wav" if fixture.ends_with("/test.pls") else fixture
		var playing_expected := false
		for i in 50:
			snapshot = await Backend.snapshot()
			playing_expected = snapshot.get("state") == "playing" and Util.object(snapshot.get("track")).get("path") == expected_path and Util.number(snapshot.get("position")) > 0
			if playing_expected:
				break
			await wait(0.1)
		check(playing_expected, "plays " + fixture.get_file())
	await load_source(url + "/missing.wav", true)
	await wait(1)
	check(Store.connected, "HTTP 404 leaves engine responsive")
	await load_source(folder.path_join("read-only.wav"), true)
	check(Store.is_playing(), "local playback recovers from HTTP failure")

	var source := folder.path_join("read-only.wav")
	var target := OS.get_environment("HOME").path_join("Music/cliamp/read-only.wav")
	await click_name("Download current track")
	await wait(0.6)
	var expected := FileAccess.get_sha256(source)
	check(FileAccess.file_exists(target) and FileAccess.get_sha256(target) == expected, "saved media matches the original bytes")
	if FileAccess.file_exists(target):
		await load_source(target, true)
		await click_name("Download current track")
		await wait(0.6)
		check(FileAccess.get_sha256(target) == expected, "saving the playing destination preserves its bytes")
