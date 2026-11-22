extends AuditKit
## Exercise every preference editor returned by this engine, including the
## repeated labels in different provider groups. Discard edits before restart.

func run() -> void:
	await set_size(1280, 800)
	await click_name("Settings")
	await wait(0.6)
	var view: SchemaFormView = find_all(func(c: Control) -> bool: return c is SchemaFormView)[0]
	var schema := await Backend.preferences_schema()
	var keys := {}
	for group in view.form.groups(""):
		var header := by_name(group["name"] + " group", view)
		var fields: Array = group["fields"]
		if _editor(view, fields[0]["key"]) == null:
			await click(header)
		for field in fields:
			var field_key: String = field["key"]
			var control := _editor(view, field_key)
			check(control != null, "preference editor " + field_key)
			if control == null:
				continue
			keys[field_key] = true
			if control is CheckButton:
				var before: bool = control.button_pressed
				await click(control)
				check(control.button_pressed != before, "toggle " + field_key)
			elif control is OptionButton:
				for i in control.item_count:
					await click(control)
					await pick_item(control.get_popup(), i)
					check(control.selected == i, "choice %s / %s" % [field_key, control.get_item_text(i)])
			elif control is LineEdit:
				await click(control)
				control.select_all()
				await type_text("8" if field["type"] in ["number", "integer"] else "Café")
				check(control.text == view.form.value(field_key), "edit " + field_key)
			else:
				var add := by_name("Add item to %s" % field["label"], control)
				if add != null:
					await click(add)
					var edits := find_all(func(c: Control) -> bool: return c is LineEdit, control)
					await click(edits.back())
					await type_text("Café")
					await click(by_name("Remove item", control))
				else:
					var edit: LineEdit = find_all(func(c: Control) -> bool: return c is LineEdit, control)[0]
					await click(edit)
					await type_text("example")
					await click(by_name("Clear " + field["label"], control))
					check(edit.text.is_empty(), "clear private replacement " + field_key)
	check(keys.size() == schema["fields"].size(), "all %d preference editors exercised" % keys.size())
	await click_name("Discard preference changes")
	await wait(0.5)
	check(not view.form.is_dirty(), "discard resets edits across groups")
	var search := by_name("Find a preference")
	await click(search)
	await type_text("zzqq")
	check(view.visible_field_count() == 0, "no matching preferences")
	await key(KEY_BACKSPACE)
	search.select_all()
	await key(KEY_BACKSPACE)
	await shot("preferences_discarded")


func _editor(view: SchemaFormView, key_name: String) -> Control:
	var hits := find_all(func(c: Control) -> bool: return c.get_meta("field_key", "") == key_name, view)
	return null if hits.is_empty() else hits[0] as Control
