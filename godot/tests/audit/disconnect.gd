extends AuditKit
## Kills the engine under the running app and checks the error state and recovery.


func run() -> void:
	await set_size(1280, 800)
	await Store.run("sources.load", {"args": [OS.get_environment("SHOT_WAV")], "name": "replace", "play": true, "if_revision": Store.state.get("playlist_revision", 0)})
	await wait(1.5)
	check(Store.connected, "connected before kill")
	OS.execute("taskkill", ["/F", "/IM", "cliamp.exe"])
	for i in 20:
		await wait(1.0)
		if not Store.connected:
			break
	print("connected after kill: ", Store.connected, " error: ", Store.connection_error)
	await wait(2.0)
	await shot("disconnected")
	lint("disconnected")
	print("connected 2s later: ", Store.connected)
	if not Store.connected:
		# every page must survive the offline state
		for page: Dictionary in Pages.LIST:
			Store.navigate(page["id"])
			await wait(0.5)
		await shot("disconnected_page")
		await click_name("Retry connection")
		for i in 30:
			await wait(1.0)
			if Store.connected:
				break
		print("connected after Retry: ", Store.connected)
		await shot("reconnected")
	Store.navigate("queue")
	await wait(1.0)
	await shot("queue_after")
