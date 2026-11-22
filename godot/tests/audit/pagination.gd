extends AuditKit

func run() -> void:
	var template := OS.get_environment("SHOT_WAV")
	var songs: Array = []
	for i in 205:
		songs.append({"title":"Fixture %03d" % i, "path":template})
	await Store.run("tracks.replace", {"tracks":songs, "play":false})
	await wait(0.7)
	await click_name("Load more · 200 of 205")
	await wait(0.6)
	check(main._active._items.size() == 205, "next queue page appended")
	await click(by_name("Search"))
	await type_text("204")
	await wait(0.4)
	check(by_name("Play Fixture 204") != null, "last record searchable after pagination")
	await key(KEY_ESCAPE)
	await Store.run("playlist.create", {"provider":"local","playlist":"Page test"})
	await click_name("Playlists")
	await wait(0.5)
	var cards := find_all(func(c: Control) -> bool: return c is CollectionCard and c.accessibility_name == "Page test")
	await click(cards[0])
	await wait(0.5)
	check(by_text("This playlist is empty") != null and by_name("Add tracks") != null, "empty collection offers to populate existing playlist")
	await click_name("Add tracks")
	await wait(0.6)
	check(not dialogs().is_empty() and dialogs().back().title == "Manage Page test", "empty collection action opens its own tools")
	if not dialogs().is_empty():
		await click(dialogs().back().get_ok_button())
