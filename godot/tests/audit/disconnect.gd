extends AuditKit
## Kills the engine under the running app and checks the error state and recovery.


func run() -> void:
	await set_size(1280, 800)
	await Store.run("sources.load", {"args": [OS.get_environment("SHOT_WAV")], "name": "replace", "play": true, "if_revision": Store.state.get("playlist_revision", 0)})
	await wait(1.5)
	check(Store.connected, "connected before kill")
	if not Backend.owns_daemon():
		check(false, "disconnect test needs a private, app-owned engine")
		return
	Backend._daemon.kill()
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
		check(Store.connected, "Retry recovers the engine")
		await shot("reconnected")
	check(Store.connected, "engine is available again")
	Store.navigate("queue")
	await wait(1.0)
	check(by_name("Select tracks") != null, "queue controls return after reconnect")
	await shot("queue_after")

	# Hold the automatic retry until after the explicit button has been exercised.
	Backend.reconnect_delay = 20.0
	Backend._daemon.kill()
	for i in 50:
		if not Store.connected:
			break
		await wait(0.1)
	check(not Store.connected, "offline state available before manual retry")
	for page in Pages.LIST:
		await click_name(page["label"])
		await wait(0.1)
	await click_name("Retry connection")
	for i in 60:
		if Store.connected:
			break
		await wait(0.1)
	check(Store.connected, "explicit Retry reconnects before the scheduled delay")
