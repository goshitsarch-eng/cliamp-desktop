class_name PluginReviewDialog
extends RefCounted
## Shows a plugin review (source, SHA-256, permissions, full code) and returns
## true only when the user ticks the exact-content approval and confirms.


static func open(host: Node, review: Dictionary) -> bool:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(740, 460)
	box.add_theme_constant_override("separation", 8)

	var permissions: Array[String] = []
	if review.get("permissions") is Array:
		for p in review["permissions"]:
			permissions.append(str(p))
	var info := Label.new()
	info.text = "Source: %s\nSHA-256: %s" % [review.get("source", ""), review.get("sha256", "")]
	info.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	info.custom_minimum_size.x = 100
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(info)
	var perms := Label.new()
	perms.text = "Declared permissions: %s" % (", ".join(permissions) if not permissions.is_empty() else "none")
	box.add_child(perms)
	var implicit := FormKit.muted(str(review.get("implicit_access", "")), 12)
	box.add_child(implicit)

	var code := TextEdit.new()
	code.text = str(review.get("code", ""))
	code.editable = false
	code.size_flags_vertical = Control.SIZE_EXPAND_FILL
	code.custom_minimum_size.y = 220
	code.accessibility_name = "Plugin source code"
	box.add_child(code)

	var approve := CheckBox.new()
	approve.text = "I approve this exact source, SHA-256 and permissions."
	approve.accessibility_name = "Approve exact source, hash and permissions"
	box.add_child(approve)

	var installing: bool = review.get("action") == "install"
	var dialog := FormKit.make_dialog("Review %s" % review.get("name", "plugin"), box,
		"Trust and install" if installing else "Trust this content", "Cancel", Vector2i(780, 0))
	dialog.get_ok_button().disabled = true
	approve.toggled.connect(func(on: bool) -> void: dialog.get_ok_button().disabled = not on)
	return await FormKit.run(host, dialog)
