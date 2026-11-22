class_name JobsPanel
extends VBoxContainer
## Active engine operations with real job cancellation and elapsed time.
## Progress is indeterminate: the engine does not report byte percentages.

var _list: VBoxContainer
var _summary: Label
var _error: Label
var _timer: Timer
var _empty: Label
var _rows: Dictionary[String, JobRow] = {}


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
	_empty = Label.new()
	_empty.text = "Provider loading, downloads, and sign-in will appear here."
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.custom_minimum_size.x = 460
	_list.add_child(_empty)


func _ready() -> void:
	Backend.jobs_changed.connect(_rebuild)
	_timer = Timer.new()
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	_rebuild(Backend.current_jobs())


func _tick() -> void:
	for row: JobRow in _rows.values():
		if row.job.is_active():
			row.update_elapsed()


func _rebuild(jobs: Array) -> void:
	var sorted := jobs.duplicate()
	sorted.sort_custom(func(a: BackendJob, b: BackendJob) -> bool:
		if a.is_active() != b.is_active():
			return a.is_active()
		return a.created_at > b.created_at)
	var active := 0
	var seen := {}
	for i in sorted.size():
		var job: BackendJob = sorted[i]
		seen[job.id] = true
		if job.is_active():
			active += 1
		var row: JobRow = _rows.get(job.id)
		if row == null:
			row = JobRow.new(_cancel.bind(job.id))
			_rows[job.id] = row
			_list.add_child(row)
		_list.move_child(row, i + 1)
		row.update_job(job)
	for id: String in _rows.keys():
		if not seen.has(id):
			var row: JobRow = _rows[id]
			_rows.erase(id)
			_list.remove_child(row)
			row.queue_free()
	_empty.visible = sorted.is_empty()
	_summary.text = "No operations running" if active == 0 else "%d running" % active


class JobRow extends VBoxContainer:
	var job: BackendJob
	var icon := Icons.label("hourglass_top", 22, ThemeBuilder.palette.muted)
	var title := Label.new()
	var status := Label.new()
	var progress := ProgressBar.new()
	var note := Label.new()
	var cancel: Button
	var state_text := ""

	func _init(on_cancel: Callable) -> void:
		add_child(HSeparator.new())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		add_child(row)
		row.add_child(icon)
		var body := VBoxContainer.new()
		body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(body)
		body.add_child(title)
		status.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
		status.add_theme_font_size_override("font_size", 12)
		body.add_child(status)
		progress.indeterminate = true
		progress.show_percentage = false
		progress.custom_minimum_size = Vector2(0, 4)
		body.add_child(progress)
		note.text = "This provider cannot cancel its sign-in flow."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size.x = 380
		note.add_theme_font_size_override("font_size", 12)
		body.add_child(note)
		cancel = Icons.button("close", "Cancel operation", on_cancel)
		row.add_child(cancel)

	func update_job(value: BackendJob) -> void:
		job = value
		title.text = JobsPanel.label_for(job.operation)
		var glyph := "hourglass_top"
		match job.state:
			"succeeded":
				glyph = "check_circle_outline"
				state_text = "Completed"
			"canceled":
				glyph = "cancel"
				state_text = "Canceled"
			"failed":
				glyph = "error_outline"
				state_text = "Failed"
			"queued": state_text = "Queued"
			"running": state_text = "Running"
			_: state_text = "Interrupted"
		icon.text = Icons.glyph(glyph)
		progress.visible = job.is_active()
		note.visible = job.is_active() and not job.cancellable
		cancel.visible = job.is_active()
		cancel.disabled = not job.cancellable or job.cancellation_requested
		update_elapsed()

	func update_elapsed() -> void:
		var end := job.finished_at if job.finished_at > 0.0 else Time.get_unix_time_from_system()
		var seconds := clampi(int(end - job.created_at), 0, 999999)
		var elapsed := "%ds" % seconds if seconds < 60 else "%dm %ds" % [seconds / 60, seconds % 60]
		status.text = "%s - %s" % ["Canceling" if job.cancellation_requested else state_text, elapsed]


func _cancel(job_id: String) -> void:
	_error.hide()
	var result := await Backend.cancel_job(job_id)
	if is_instance_valid(self) and Backend.failed(result):
		_error.text = "The operation could not be canceled. Check its current state before trying again."
		_error.show()
