extends Page
## Explore providers: the provider toolbar (provider dropdown, Connect service,
## Sign in) over the capability-driven ProviderBrowser. Like the Flutter app,
## every visit starts a fresh browser for Store.provider, seeded by
## Store.provider_seed and Store.provider_action when a track opened this page.

const SETUP_DIALOG := "res://ui/dialogs/provider_setup_dialog.gd"
const SIGN_IN_DIALOG := "res://ui/dialogs/provider_sign_in_dialog.gd"
const SAVE_DIALOG := "res://ui/dialogs/save_to_playlist_dialog.gd"

var _active := false
var _dropdown: OptionButton
var _sign_in: Button
var _connect: Button
var _notice: Label
var _browser: ProviderBrowser
var _populated_keys: Array[String] = []


func _init() -> void:
	super()
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(column)

	var toolbar_pad := MarginContainer.new()
	toolbar_pad.add_theme_constant_override("margin_left", 32)
	toolbar_pad.add_theme_constant_override("margin_right", 32)
	toolbar_pad.add_theme_constant_override("margin_bottom", 12)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 48)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_dropdown = OptionButton.new()
	_dropdown.accessibility_name = "Provider"
	_dropdown.custom_minimum_size = Vector2(180, 0)
	_dropdown.item_selected.connect(_on_provider_selected)
	row.add_child(_dropdown)
	_connect = Button.new()
	_connect.text = "Connect service"
	_connect.accessibility_name = "Connect service"
	_connect.pressed.connect(_configure_provider)
	row.add_child(_connect)
	_sign_in = Button.new()
	_sign_in.text = "Sign in"
	_sign_in.accessibility_name = "Sign in"
	_sign_in.pressed.connect(_authenticate)
	row.add_child(_sign_in)
	scroll.add_child(row)
	toolbar_pad.add_child(scroll)
	column.add_child(toolbar_pad)

	_notice = Label.new()
	_notice.text = "This player does not support provider browsing. Update cliamp to explore providers here."
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.hide()
	column.add_child(_notice)

	_browser = ProviderBrowser.new()
	_browser.on_play_track = _play_track
	_browser.on_queue_track = _queue_track
	_browser.on_add_to_playlist = _add_to_playlist
	_browser.on_toggle_favorite = _toggle_favorite
	_browser.on_queue_loaded = _queue_loaded
	column.add_child(_browser)

	Store.filter_changed.connect(_on_filter_changed)
	Store.search_submitted.connect(_on_search_submitted)
	Store.focus_search_requested.connect(_on_focus_search)


func activate() -> void:
	_active = true
	_populate()
	if not Store.supports("provider.browse"):
		_browser.hide()
		_notice.show()
		return
	_notice.hide()
	_browser.show()
	var seed := Store.provider_seed
	var action := Store.provider_action
	Store.provider_seed = {}
	Store.provider_action = ""
	_load_browser(seed, action)


func deactivate() -> void:
	_active = false


func refresh() -> void:
	if _active and Store.supports("provider.browse"):
		_browser.reload()


func handles_escape() -> bool:
	return _active and _browser.visible and _browser.handles_escape()


func _provider_entry() -> Dictionary:
	for p in Store.providers:
		if p.get("key") == Store.provider:
			return p
	return {}


func _populate() -> void:
	if not Store.providers.is_empty():
		var found := false
		for p in Store.providers:
			if p.get("key") == Store.provider:
				found = true
		if not found:
			Store.provider = Util.text(Store.providers[0].get("key"))
	_dropdown.clear()
	_populated_keys.clear()
	var selected := -1
	for i in Store.providers.size():
		var p := Store.providers[i]
		_dropdown.add_item(Util.text(p.get("name")), i)
		_populated_keys.append(Util.text(p.get("key")))
		if _populated_keys[i] == Store.provider:
			selected = i
	_dropdown.select(selected)
	_update_toolbar()


func _update_toolbar() -> void:
	_sign_in.visible = _provider_entry().get("authenticatable") == true and Store.supports("provider.auth")


func _load_browser(seed := {}, action := "") -> void:
	_update_toolbar()
	_browser.configure(_provider_entry(), seed, action)


func _on_provider_selected(index: int) -> void:
	if index < 0 or index >= _populated_keys.size():
		return
	Store.provider = _populated_keys[index]
	_load_browser()


# Shell search box

func _on_filter_changed(text: String) -> void:
	if _active and Store.supports("provider.browse"):
		_browser.set_filter(text)


func _on_search_submitted(text: String) -> void:
	if _active and Store.supports("provider.browse"):
		_browser.submit_search(text)


func _on_focus_search() -> void:
	if _active and Store.supports("provider.browse"):
		_browser.focus_search()


# Account flows

func _configure_provider() -> void:
	var restarted: bool = await load(SETUP_DIALOG).open(self)
	if restarted:
		Store.start()


func _authenticate() -> void:
	var entry := _provider_entry()
	var name := Util.text(entry.get("name"))
	var connected: bool = await load(SIGN_IN_DIALOG).open(self, Util.text(entry.get("key")), name)
	if connected and _active:
		Store.notify("Connected to " + name)
		_load_browser()


# Browser callbacks

func _play_track(track: Dictionary) -> void:
	var params := {"track": track}
	params.merge(Store.revision())
	await Store.run("track.play", params)


func _queue_track(track: Dictionary) -> void:
	var params := {"track": track}
	params.merge(Store.revision())
	await Store.run("track.queue", params)


func _add_to_playlist(track: Dictionary) -> void:
	if not ResourceLoader.exists(SAVE_DIALOG):
		Store.notify("Saving to a playlist is not available yet.", true)
		return
	var dialog: GDScript = load(SAVE_DIALOG)
	if dialog == null:
		Store.notify("Saving to a playlist is not available yet.", true)
		return
	await dialog.save(self, [track])


func _toggle_favorite(track: Dictionary) -> void:
	await Store.run("playlist.bookmark", {"provider": "local", "track": track})


func _queue_loaded() -> void:
	Store.refresh_state()
	Store.navigate("queue")
