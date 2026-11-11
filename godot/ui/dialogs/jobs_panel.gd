class_name JobsPanel
extends VBoxContainer
## Active engine operations with real job cancellation and elapsed time.
## Progress is indeterminate: the engine does not report byte percentages.

var _list: VBoxContainer
var _summary: Label
var _error: Label
var _timer: Timer


static func open(host: Node) -> void:
	await Dialogs.open(host, "Background activity", JobsPanel.new(), ["Close"], Vector2i(520, 0))


static func label_for(operation: String) -> String:
	match operation:
		"provider.auth": return "Provider sign-in"
		"provider.load": return "Load provider playlist"
		"provider.load_album": return "Load provider album"
		"provider.search": return "Search provider"
		"save": return "Download track"
		"url.load": return "Load URL"
		"load": return "Load music"
		"lyrics": return "Find lyrics"
		"plugin.call": return "Run plugin command"
	return operation.replace(".", " / ").replace("_", " ")


func _init() -> void:
	custom_minimum_size = Vector2(500, 0)
	_summary = Label.new()
	add_child(_summary)
	_error = DialogUtil.error_label()
	_error.hide()
	add_child(_error)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 280)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)


func _ready() -> void:
	Backend.jobs_changed.connect(_rebuild)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	_rebuild(Backend.current_jobs())


func _tick() -> void:
	for job: BackendJob in Backend.current_jobs():
		if job.is_active():
			_rebuild(Backend.current_jobs())
			return


func _rebuild(jobs: Array) -> void:
	var sorted := jobs.duplicate()
	sorted.sort_custom(func(a: BackendJob, b: BackendJob) -> bool:
		if a.is_active() != b.is_active():
			return a.is_active()
		return a.created_at > b.created_at)
	var active := 0
	for job: BackendJob in sorted:
		if job.is_active():
			active += 1
	_summary.text = "No operations running" if active == 0 else "%d running" % active
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()
	if sorted.is_empty():
		var empty := Label.new()
		empty.text = "Provider loading, downloads, and sign-in will appear here."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 460
		_list.add_child(empty)
		return
	for job: BackendJob in sorted:
		_list.add_child(HSeparator.new())
		_list.add_child(_tile(job))


func _tile(job: BackendJob) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var icon_name := "hourglass_top"
	var state_text := "Interrupted"
	match job.state:
		"succeeded":
			icon_name = "check_circle_outline"
			state_text = "Completed"
		"canceled":
			icon_name = "cancel"
			state_text = "Canceled"
		"failed":
			icon_name = "error_outline"
			state_text = "Failed"
		"queued":
			state_text = "Queued"
		"running":
			state_text = "Running"
	row.add_child(Icons.label(icon_name, 22, ThemeBuilder.palette.muted))
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(body)
	var title := Label.new()
	title.text = label_for(job.operation)
	body.add_child(title)
	var end := job.finished_at if job.finished_at > 0.0 else Time.get_unix_time_from_system()
	var seconds := clampi(int(end - job.created_at), 0, 999999)
	var elapsed := "%ds" % seconds if seconds < 60 else "%dm %ds" % [seconds / 60, seconds % 60]
	var sub := Label.new()
	sub.text = "%s - %s" % ["Canceling" if job.cancellation_requested else state_text, elapsed]
	sub.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
	sub.add_theme_font_size_override("font_size", 12)
	body.add_child(sub)
	if job.is_active():
		var bar := ProgressBar.new()
		bar.indeterminate = true
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 4)
		body.add_child(bar)
		if not job.cancellable:
			var note := Label.new()
			note.text = "This provider cannot cancel its sign-in flow."
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			note.custom_minimum_size.x = 380
			note.add_theme_font_size_override("font_size", 12)
			body.add_child(note)
		var cancel := Icons.button("close", "Cancel operation", _cancel.bind(job.id))
		cancel.disabled = not job.cancellable or job.cancellation_requested
		row.add_child(cancel)
	return row


func _cancel(job_id: String) -> void:
	_error.hide()
	var result := await Backend.cancel_job(job_id)
	if is_instance_valid(self) and Backend.failed(result):
		_error.text = "The operation could not be canceled. Check its current state before trying again."
		_error.show()
