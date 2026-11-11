class_name SaveToPlaylistDialog
extends RefCounted
## "Save N tracks to playlist": lists every writable playlist of every provider,
## plus "New playlist" where a provider can create one, then writes the tracks.
## Shared by the library pages and the provider browser.


## Runs the whole flow. Returns true when a playlist was updated.
static func save(host: Node, tracks: Array) -> bool:
	if tracks.is_empty():
		return false
	var destinations := await collect_destinations()
	if not is_instance_valid(host) or not host.is_inside_tree():
		return false
	var picked := await _choose(host, tracks.size(), destinations)
	if picked.is_empty():
		return false
	var selected: Dictionary = picked["item"]
	var prepend: bool = picked["prepend"]
	var provider := Util.text(selected.get("provider"))
	var name := Util.text(selected.get("id"))
	if selected.get("new") == true:
		var validator := LibraryLogic.playlist_name_error if provider == "local" else Callable()
		var value: Variant = await Dialogs.prompt(host, "Create playlist", "Playlist name", "", "", false, "Create", validator)
		if value == null:
			return false
		var created: Variant = await Store.run("playlist.create", {"provider": provider, "playlist": value})
		if created == null:
			return false
		name = Util.text(created.get("playlist"), value)
	var result: Variant = await Store.run("playlist.prepend" if prepend else "playlist.add_many",
		{"provider": provider, "playlist": name, "tracks": tracks})
	if result == null:
		return false
	var skipped: Variant = result.get("skipped")
	Store.notify("Playlist updated" + (" · %s skipped" % str(skipped) if skipped != null else ""))
	return true


## Writable playlists as {...playlist, provider, provider_name, capabilities},
## and {new: true, ...} entries for providers that can create playlists.
static func collect_destinations() -> Array[Dictionary]:
	var destinations: Array[Dictionary] = []
	var providers := Store.providers.duplicate()
	for provider in providers:
		var key := Util.text(provider.get("key"))
		var caps: Variant
		if Store.supports("playlist.capabilities"):
			caps = await Store.run("playlist.capabilities", {"provider": key})
		elif key == "local":
			caps = {"add_many": true, "create": true, "prepend": true}
		else:
			caps = null
		if caps == null or caps.get("add_many") != true:
			continue
		var offset := 0
		while true:
			var list: Variant = await Store.run("provider.playlists", {"provider": key, "offset": offset, "limit": 200})
			if list == null:
				break
			var playlists := Util.objects(list.get("playlists"))
			if playlists.is_empty():
				break
			for playlist in playlists:
				if key == "local" and LibraryLogic.SYSTEM_PLAYLISTS.has(Util.text(playlist.get("id"))):
					continue
				if Store.supports("playlist.capabilities"):
					var target: Variant = await Store.run("playlist.capabilities", {"provider": key, "playlist": playlist.get("id")})
					if target != null and target.get("can_add") == false:
						continue
				var entry := playlist.duplicate()
				entry["provider"] = key
				entry["provider_name"] = provider.get("name")
				entry["capabilities"] = caps
				destinations.append(entry)
			offset += playlists.size()
			var total: Variant = list.get("total")
			if total is int or total is float:
				if offset >= int(total):
					break
			elif playlists.size() < 200:
				break
		if caps.get("create") == true:
			destinations.append({"new": true, "provider": key, "provider_name": provider.get("name"), "capabilities": caps})
	return destinations


## Shows the chooser. Returns {item, prepend}, or {} when cancelled.
static func _choose(host: Node, count: int, destinations: Array[Dictionary]) -> Dictionary:
	var state := {"item": {}, "prepend": false}
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(460, 360)
	var prepend := CheckButton.new()
	prepend.text = "Place at the beginning"
	prepend.tooltip_text = "Supported playlists move existing explicit tracks to the front."
	prepend.accessibility_name = "Place at the beginning"
	box.add_child(prepend)
	var hint := UiKit.label("Supported playlists move existing explicit tracks to the front.", 11, ThemeBuilder.palette.muted)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if destinations.is_empty():
		var none := UiKit.label("No writable playlist providers are available.", 13)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.size_flags_vertical = Control.SIZE_EXPAND_FILL
		none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		list.add_child(none)
	var buttons: Array[Button] = []
	for item in destinations:
		var is_new: bool = item.get("new") == true
		var title := "New playlist" if is_new else Util.text(item.get("name"))
		var b := UiKit.text_button("add" if is_new else "playlist_add",
			"%s  -  %s" % [title, Util.text(item.get("provider_name"))], Callable(), title)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.set_meta("supports_prepend", Util.object(item.get("capabilities")).get("prepend") == true)
		b.pressed.connect(func() -> void:
			state["item"] = item
			state["prepend"] = prepend.button_pressed
			UiKit.accept(box))
		list.add_child(b)
		buttons.append(b)
	prepend.toggled.connect(func(on: bool) -> void:
		for b in buttons:
			b.disabled = on and not b.get_meta("supports_prepend"))
	box.tree_entered.connect(func() -> void:
		var w := box.get_window()
		if w is AcceptDialog:
			(w as AcceptDialog).get_ok_button().hide())
	var title_text := "Save %d %s to playlist" % [count, "track" if count == 1 else "tracks"]
	await Dialogs.open(host, title_text, box, ["Select", "Cancel"], Vector2i(500, 420))
	return state if not Util.object(state["item"]).is_empty() else {}
