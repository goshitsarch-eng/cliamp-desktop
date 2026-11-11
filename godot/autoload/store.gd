extends Node
## Shared UI state: the engine snapshot, capabilities, providers, and the one
## place that runs engine operations. Pages read from here and call run(); they
## never talk to Backend for playback or queue operations directly.

signal state_changed(state: Dictionary)
signal connection_changed
signal pending_changed(count: int)
signal bands_changed(bands: PackedFloat32Array)
## A message for the shell to show as a toast.
signal notice(message: String, is_error: bool)
## A queue or play-next edit lost a revision race; visible lists should reload.
signal lists_stale
signal plugin_bindings_changed
signal filter_changed(text: String)
signal search_submitted(text: String)
signal focus_search_requested
signal navigate_requested(page_id: String)

var state: Dictionary = {}
var operations: Array[Dictionary] = []
var providers: Array[Dictionary] = []
var plugin_bindings: Array[Dictionary] = []
var bands := PackedFloat32Array()
var connected := false
var connecting := true
var connection_error := ""
var pending := 0
## Lowercased text of the top bar search box.
var filter := ""
var current_page := "queue"
## Selected provider key on the Providers and Playlists pages.
var provider := "local"
## Set before navigating to "providers" to open a track's related items or artist.
var provider_seed: Dictionary = {}
var provider_action := ""

var _theme_key := ""
var _snapshot_key := ""
var _bands_silent := false
var _state_at_ms := 0
var _refreshing := false


func _ready() -> void:
	Backend.event_received.connect(_on_event)
	Backend.spectrum_received.connect(_on_spectrum)
	Backend.connection_lost.connect(_on_connection_lost)


## Connects to the engine and loads the shared state. Safe to call again as retry.
func start() -> void:
	connecting = true
	connection_error = ""
	connection_changed.emit()
	var c := await Backend.connect_engine()
	if Backend.failed(c):
		_fail_connection(c["error"]["message"])
		return
	var snap := await Backend.snapshot()
	var caps := await Backend.capabilities()
	var provs := await Backend.call_op("provider.list")
	for r in [snap, caps, provs]:
		if Backend.failed(r):
			_fail_connection(r["error"]["message"])
			return
	operations = Util.objects(caps.get("operations"))
	providers = Util.objects(provs.get("providers"))
	connected = true
	connecting = false
	accept_state(snap)
	if supports("plugin.keys"):
		var keys := await Backend.call_op("plugin.keys")
		if not Backend.failed(keys):
			plugin_bindings = Util.objects(keys.get("bindings"))
			plugin_bindings_changed.emit()
	connection_changed.emit()


func _fail_connection(message: String) -> void:
	connection_error = message
	connected = false
	connecting = false
	connection_changed.emit()


func supports(operation: String) -> bool:
	for o in operations:
		if o.get("name") == operation:
			return true
	return false


func track() -> Dictionary:
	return Util.object(state.get("track"))


func is_playing() -> bool:
	return state.get("state") == "playing"


## Playback position, extrapolated between snapshots while playing.
func position() -> float:
	var base := Util.number(state.get("position"))
	if not is_playing() or state.get("seekable") != true or state.get("buffering") == true:
		return base
	var duration := Util.number(state.get("duration"))
	var advanced := base + (Time.get_ticks_msec() - _state_at_ms) / 1000.0 * Util.number(state.get("speed"), 1.0)
	return clampf(advanced, 0.0, duration) if duration > 0.0 else advanced


func title() -> String:
	var t := track()
	return Util.single_line(t.get("title"), "Make room for your music." if t.is_empty() else Util.single_line(Util.basename(Util.text(t.get("path"))), "Untitled track"))


## Revision guard for queue and play-next edits.
func revision(list_revision: Variant = null) -> Dictionary:
	return {"if_revision": list_revision if list_revision != null else state.get("playlist_revision", 0)}


func playlist_revision() -> Variant:
	return state.get("playlist_revision")


func set_filter(text: String) -> void:
	filter = text.to_lower()
	filter_changed.emit(filter)


func navigate(page_id: String) -> void:
	navigate_requested.emit(page_id)


func notify(message: String, is_error := false) -> void:
	notice.emit(message, is_error)


## Runs an engine operation. Returns its result Dictionary, or null after
## showing the error. A revision conflict also refreshes state and lists.
func run(operation: String, params := {}, message := "") -> Variant:
	if not connected:
		return null
	pending += 1
	pending_changed.emit(pending)
	var result := await Backend.call_op(operation, params)
	var out: Variant = null
	if Backend.failed(result):
		notify(result["error"]["message"], true)
		if result["error"]["code"] == "conflict":
			await refresh_state()
			lists_stale.emit()
	elif result.get("ok") == false:
		notify(Util.text(result.get("error"), "The operation could not be completed."), true)
	else:
		await refresh_state()
		if not message.is_empty():
			notify(message)
		out = result
	pending -= 1
	pending_changed.emit(pending)
	return out


func refresh_state() -> void:
	if not connected or _refreshing:
		return
	_refreshing = true
	var snap := await Backend.snapshot()
	_refreshing = false
	if Backend.failed(snap):
		connection_error = snap["error"]["message"]
		connected = false
		connection_changed.emit()
		return
	accept_state(snap)


func accept_state(new_state: Dictionary) -> void:
	if new_state.is_empty():
		return
	var text := Util.text(new_state.get("notice"))
	if not text.is_empty() and new_state.get("notice") != state.get("notice"):
		notify(text, new_state.get("notice_error") == true)
	var snap_key := JSON.stringify(new_state)
	state = new_state
	_state_at_ms = Time.get_ticks_msec()
	connected = true
	connection_error = ""
	var colors := Util.object(new_state.get("theme"))
	var key := JSON.stringify(colors)
	if key != _theme_key:
		_theme_key = key
		ThemeBuilder.apply_engine_theme(colors)
	if snap_key == _snapshot_key and new_state.get("state") != "playing":
		return
	_snapshot_key = snap_key
	state_changed.emit(state)


func _on_event(envelope: Dictionary) -> void:
	if envelope.get("event") == "runtime.state" or envelope.get("topic") == "runtime.state":
		var data := Util.object(envelope.get("data"))
		accept_state(Util.object(data.get("snapshot")) if data.has("snapshot") else data)


func _on_spectrum(values: PackedFloat32Array) -> void:
	var silent := true
	for v in values:
		if v > 0.0005:
			silent = false
			break
	bands = values
	if silent and _bands_silent and not values.is_empty():
		return
	_bands_silent = silent
	bands_changed.emit(values)


func _on_connection_lost(error: Dictionary) -> void:
	connection_error = error.get("message", "Connection lost.")
	connected = false
	connection_changed.emit()
