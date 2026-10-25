class_name ProviderSignInDialog
extends RefCounted
## Browser sign-in for a provider: starts provider.auth, polls provider.auth.status
## and shows the sign-in link the provider supplies. Closing the dialog leaves
## the attempt running, as in provider_sign_in.dart. The link is only shown here
## and opened on request; it is never logged or toasted.

signal finished(connected: bool)

var _provider := ""
var _name := ""
var _dialog: AcceptDialog
var _body: VBoxContainer
var _timer: Timer
var _polling := false
var _closed := false
var _flow: Dictionary = ProviderAuth.initial()
var _job: BackendJob
var _previous_jobs: Dictionary = {}


## Resolves true when the account connected.
static func open(host: Node, provider_key: String, provider_name: String) -> bool:
	var flow := ProviderSignInDialog.new()
	return await flow._run(host, provider_key, provider_name)


func _run(host: Node, provider_key: String, provider_name: String) -> bool:
	_provider = provider_key
	_name = provider_name
	_dialog = AcceptDialog.new()
	_dialog.title = "Connect " + _name
	_dialog.exclusive = true
	_dialog.min_size = Vector2i(Vector2(470, 0) * Prefs.ui_scale)
	_dialog.get_ok_button().hide()
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(450, 0)
	_dialog.add_child(_body)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_status)
	_dialog.add_child(_timer)
	_dialog.close_requested.connect(_close)
	_dialog.canceled.connect(_close)
	Util.host(host).add_child(_dialog)
	Backend.jobs_changed.connect(_on_jobs)
	Backend.event_received.connect(_on_event)
	_render()
	_dialog.popup_centered()
	_sign_in()
	var connected: bool = await finished
	return connected


func _close() -> void:
	if _closed:
		return
	_closed = true
	_timer.stop()
	if Backend.jobs_changed.is_connected(_on_jobs):
		Backend.jobs_changed.disconnect(_on_jobs)
	if Backend.event_received.is_connected(_on_event):
		Backend.event_received.disconnect(_on_event)
	var connected: bool = _flow["state"] == "authenticated"
	_dialog.queue_free()
	finished.emit(connected)


func _sign_in() -> void:
	_flow = ProviderAuth.initial()
	_job = null
	_previous_jobs = {}
	for job: BackendJob in Backend.current_jobs():
		_previous_jobs[job.id] = true
	_timer.start()
	_render()
	_status()
	var result := await Backend.call_op("provider.auth", {"provider": _provider})
	if _closed:
		return
	if Backend.failed(result):
		var code: String = result["error"]["code"]
		if code == "canceled":
			_flow["state"] = "canceling"
			_flow["cancel_requested"] = true
			_flow["url"] = ""
			_render()
			await _status()
			return
		_timer.stop()
		_flow["state"] = "failed"
		_flow["error"] = "A sign-in flow is already running for this provider." if code == "conflict" else "Check the provider configuration and try again."
		_render()
		return
	_flow["state"] = "authenticated"
	_timer.stop()
	_render()


func _on_jobs(jobs: Array) -> void:
	for job: BackendJob in jobs:
		if job.operation == "provider.auth" and job.provider == _provider and not _previous_jobs.has(job.id):
			_job = job
			_render()
			return


## The provider.auth topic carries the same object as provider.auth.status.
func _on_event(envelope: Dictionary) -> void:
	if envelope.get("event") != "provider.auth":
		return
	var auth := Util.object(Util.object(envelope.get("data")).get("auth"))
	if auth.get("provider") == _provider:
		_apply(auth)


func _status() -> void:
	if _polling or _closed:
		return
	_polling = true
	var result := await Backend.call_op("provider.auth.status", {"provider": _provider})
	_polling = false
	if _closed:
		return
	if Backend.failed(result):
		_flow["error"] = "Could not read the provider sign-in state."
		_render()
		return
	if result.get("auth") is Dictionary:
		_apply(result["auth"])


func _apply(auth: Dictionary) -> void:
	_flow = ProviderAuth.reduce(_flow, auth)
	if ProviderAuth.is_terminal(_flow["state"]):
		_timer.stop()
	_render()


func _cancel() -> void:
	if _job == null or not _job.cancellable or not _flow["cancellable"]:
		return
	_flow["cancel_requested"] = true
	_flow["state"] = "canceling"
	_flow["url"] = ""
	_flow["error"] = ""
	_render()
	var response := await Backend.cancel_job(_job.id)
	if _closed:
		return
	if Backend.failed(response):
		_flow["cancel_requested"] = false
		_flow["state"] = "authenticating"
		_flow["error"] = "Sign-in could not be canceled. Check its current state before trying again."
		_render()
		return
	await _status()


func _open_browser() -> void:
	var url: String = _flow["url"]
	if not ProviderAuth.is_http_url(url):
		_flow["error"] = "This provider did not return a valid HTTP sign-in URL."
		_render()
		return
	if OS.shell_open(url) != OK:
		_flow["error"] = "Unable to open the browser. Copy the link and open it manually."
		_render()


func _copy_link() -> void:
	DisplayServer.clipboard_set(_flow["url"])


func _render() -> void:
	if _closed:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var state: String = _flow["state"]
	var url: String = _flow["url"]
	if state in ["authenticating", "idle", "canceling"]:
		var bar := ProgressBar.new()
		bar.indeterminate = true
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		_body.add_child(bar)
	_body.add_child(_spacer(14))
	_body.add_child(_label(ProviderAuth.message(state, url)))
	if not url.is_empty() and state == "authenticating":
		_body.add_child(_spacer(12))
		var link := RichTextLabel.new()
		link.fit_content = true
		link.selection_enabled = true
		link.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		link.bbcode_enabled = false
		link.text = url
		link.add_theme_font_size_override("normal_font_size", 12)
		link.accessibility_name = "Sign-in link"
		_body.add_child(link)
		_body.add_child(_spacer(8))
		var row := HBoxContainer.new()
		var open := Button.new()
		open.text = "Open sign-in page"
		open.accessibility_name = "Open sign-in page"
		open.pressed.connect(_open_browser)
		row.add_child(open)
		row.add_child(Icons.button("content_copy", "Copy sign-in link", _copy_link, 18))
		_body.add_child(row)
	if not String(_flow["error"]).is_empty():
		_body.add_child(_spacer(12))
		var err := _label(_flow["error"])
		err.add_theme_color_override("font_color", Color("ff8a80"))
		_body.add_child(err)
	if state == "authenticating":
		_body.add_child(_spacer(12))
		var hint := _label("Closing this dialog leaves the provider sign-in attempt running.")
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
		_body.add_child(hint)
	_body.add_child(_spacer(14))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	if state == "authenticating" and _flow["cancellable"] and _job != null and _job.cancellable:
		buttons.add_child(_button("Cancel sign-in", _cancel))
	if state == "failed" or state == "canceled":
		buttons.add_child(_button("Try again", _sign_in))
	buttons.add_child(_button("Done" if state == "authenticated" else "Close", _close))
	_body.add_child(buttons)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _spacer(height: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.accessibility_name = text
	b.pressed.connect(callback)
	return b
