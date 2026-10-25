extends Node
## Plugin install flow against a real engine: prepare, review dialog with its
## exact-content approval, apply, list, configure dialog, remove. PLUGIN_URL is
## the address of a plugin served over HTTP (a name.lua file).
##   godot --headless --path godot res://tests/engine_plugins.tscn

var _failures := 0
var _checks := 0


func ok(cond: bool, what: String) -> void:
	_checks += 1
	if cond:
		print("ok   ", what)
	else:
		_failures += 1
		printerr("FAIL ", what)


func _dialog() -> AcceptDialog:
	for i in 200:
		for c in get_tree().root.get_children():
			if c is AcceptDialog and c.visible:
				return c
		await get_tree().create_timer(0.05).timeout
	return null


func _find_all(node: Node, pred: Callable, out: Array) -> void:
	if pred.call(node):
		out.append(node)
	for c in node.get_children():
		_find_all(c, pred, out)


func _ready() -> void:
	var url := OS.get_environment("PLUGIN_URL")
	await Store.start()
	ok(Store.connected, "connected")
	var review := await Backend.plugin_action("prepare", {"source": url})
	ok(not Backend.failed(review), "prepare returns a review (%s)" % str(review).left(120))
	var r: Dictionary = Util.object(review.get("review"))
	ok(PluginLogic.is_valid_review(r), "review has token, source, digest and permissions")
	ok(str(r.get("code", "")).contains("plugin.register"), "review shows the exact source code")

	# Declining must not install anything.
	var answer := [null]
	var run := func() -> void:
		answer[0] = await PluginReviewDialog.open(self, r)
	run.call()
	var d := await _dialog()
	ok(d != null and d.get_ok_button().disabled, "approve is disabled until the exact content is ticked")
	d.canceled.emit()
	for i in 40:
		if answer[0] != null:
			break
		await get_tree().create_timer(0.05).timeout
	ok(answer[0] == false, "cancel does not approve")
	var listed := PluginLogic.parse_plugins(await Backend.plugin_action("list"))
	ok(listed.is_empty(), "nothing is installed after declining")

	# Approve with the checkbox, then apply exactly what was reviewed.
	answer[0] = null
	run.call()
	d = await _dialog()
	var boxes: Array = []
	_find_all(d, func(n: Node) -> bool: return n is CheckBox, boxes)
	ok(boxes.size() == 1, "one approval checkbox")
	(boxes[0] as CheckBox).button_pressed = true
	ok(not d.get_ok_button().disabled, "ticking enables approval")
	d.get_ok_button().pressed.emit()
	for i in 40:
		if answer[0] != null:
			break
		await get_tree().create_timer(0.05).timeout
	ok(answer[0] == true, "approval returned")
	var payload := PluginLogic.approval(r)
	var applied := await Backend.plugin_action(payload["action"], payload["values"])
	ok(not Backend.failed(applied), "apply installs the reviewed content (%s)" % str(applied).left(100))
	listed = PluginLogic.parse_plugins(await Backend.plugin_action("list"))
	ok(listed.size() == 1, "plugin is listed after install")

	# The configuration dialog opens for the installed plugin and cancels cleanly.
	if not listed.is_empty():
		var cfg := [null]
		var run_cfg := func() -> void:
			cfg[0] = await PluginConfigDialog.open(self, listed[0])
		run_cfg.call()
		d = await _dialog()
		ok(d != null, "configuration dialog opens")
		d.canceled.emit()
		for i in 40:
			if cfg[0] != null:
				break
			await get_tree().create_timer(0.05).timeout
		var cfg_value: Variant = cfg[0]
		ok(cfg_value == null or cfg_value is Dictionary, "configuration cancel returns without values")

	var removed := await Backend.plugin_action("remove", {"name": listed[0].get("id") if not listed.is_empty() else ""})
	ok(not Backend.failed(removed), "remove uninstalls it (%s; plugin=%s)" % [str(removed), str(listed[0]) if not listed.is_empty() else ""])
	ok(PluginLogic.parse_plugins(await Backend.plugin_action("list")).is_empty(), "list is empty again")
	print("engine_plugins: %d checks, %d failure(s)" % [_checks, _failures])
	await Backend.close()
	get_tree().quit(1 if _failures > 0 else 0)
