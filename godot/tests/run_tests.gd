extends Node
## Headless unit tests for core/ logic. Exits non-zero on any failure.
## Run: godot --headless --path godot res://tests/run_tests.tscn
## (A temporary stand-in until the project migrates to GdUnit4.)

var _failures := 0
var _checks := 0


func _ready() -> void:
	_test_schema_normalize()
	_test_dirty_and_changed()
	_test_validation()
	_test_groups_filter()
	_test_secret()
	_test_plugin_logic()
	print("tests: %d check(s), %d failure(s)" % [_checks, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual != expected:
		_failures += 1
		printerr("FAIL: %s: expected %s, got %s" % [what, str(expected), str(actual)])


func _schema() -> SchemaForm:
	var f := SchemaForm.new()
	f.load_fields([
		{"key": "volume", "label": "Volume", "group": "Playback", "type": "number", "value": "-5", "min": -90, "max": 6},
		{"key": "repeat", "label": "Repeat", "group": "Playback", "type": "string", "value": "off", "options": ["off", "all", "one"]},
		{"key": "mono", "label": "Mono", "group": "Playback", "type": "bool", "value": "false"},
		{"key": "seek_large_step_sec", "label": "Seek large step sec", "group": "Playback", "type": "integer", "value": "30", "min": 6, "max": 600},
		{"key": "plugins.disabled", "label": "Disabled", "group": "Plugins", "type": "list", "value": "[\"a\"]"},
		{"key": "eq", "label": "Eq", "group": "Audio", "type": "equalizer", "value": "[0,0,0,0,0,0,0,0,0,0]"},
		{"key": "theme", "label": "Theme", "group": "Appearance", "type": "string", "value": "nord"},
		{"key": "", "label": "no key"},
		{"key": "volume", "label": "duplicate"},
		"not a dictionary",
	])
	return f


func _test_schema_normalize() -> void:
	var f := _schema()
	_eq(f.fields.size(), 7, "skips keyless, duplicate and non-dictionary fields")
	_eq(SchemaForm.kind_of(f.field("repeat")), SchemaForm.KIND_CHOICE, "options make a choice")
	_eq(SchemaForm.kind_of(f.field("mono")), SchemaForm.KIND_BOOL, "bool kind")
	_eq(SchemaForm.kind_of(f.field("volume")), SchemaForm.KIND_NUMBER, "number kind")
	_eq(SchemaForm.kind_of(f.field("plugins.disabled")), SchemaForm.KIND_LIST, "list kind")
	_eq(SchemaForm.kind_of(f.field("theme")), SchemaForm.KIND_TEXT, "text kind")
	_eq(SchemaForm.range_text(f.field("volume")), "Range: -90 to 6", "range text")
	_eq(SchemaForm.range_text(f.field("theme")), "", "no range")
	var n := SchemaForm.normalize_field({"key": "x", "value": 5, "min": 1})
	_eq(n["value"], "5", "numeric value stringified")
	_eq(n["min"], null, "min without max ignored")
	_eq(n["group"], "General", "default group")


func _test_dirty_and_changed() -> void:
	var f := _schema()
	_eq(f.is_dirty(), false, "clean after load")
	f.set_value("volume", "-10")
	_eq(f.is_dirty(), true, "dirty after edit")
	_eq(f.changed(), {"volume": "-10"}, "only changed values")
	f.set_value("volume", "-5")
	_eq(f.is_dirty(), false, "reverting clears dirty")
	f.set_value("theme", "dracula")
	f.mark_saved(f.changed())
	_eq(f.is_dirty(), false, "mark_saved sets baseline")
	_eq(f.initial("theme"), "dracula", "baseline updated")
	f.set_value("theme", "x")
	f.reset("theme")
	_eq(f.value("theme"), "dracula", "reset")
	f.set_value("unknown", "x")
	_eq(f.has_field("unknown"), false, "unknown key ignored")


func _test_validation() -> void:
	var f := _schema()
	f.set_value("volume", "abc")
	_eq(f.validate("volume") != "", true, "non-number rejected")
	f.set_value("volume", "7")
	_eq(f.validate("volume") != "", true, "above max rejected")
	f.set_value("volume", "-90")
	_eq(f.validate("volume"), "", "boundary accepted")
	f.set_value("seek_large_step_sec", "12.5")
	_eq(f.validate("seek_large_step_sec") != "", true, "fraction rejected for integer")
	f.set_value("seek_large_step_sec", "5")
	_eq(f.validate("seek_large_step_sec") != "", true, "below min rejected")
	f.set_value("seek_large_step_sec", "60")
	_eq(f.validate("seek_large_step_sec"), "", "integer accepted")
	f.set_value("repeat", "sometimes")
	_eq(f.validate("repeat") != "", true, "unsupported option rejected")
	f.set_value("repeat", "all")
	_eq(f.validate("repeat"), "", "supported option")
	f.set_value("mono", "maybe")
	_eq(f.validate("mono") != "", true, "bool must be true/false")
	f.set_value("plugins.disabled", "not json")
	_eq(f.validate("plugins.disabled") != "", true, "list needs JSON array")
	f.set_value("plugins.disabled", "[1]")
	_eq(f.validate("plugins.disabled") != "", true, "list needs strings")
	f.set_value("plugins.disabled", "[\"a\", \"b\"]")
	_eq(f.validate("plugins.disabled"), "", "valid list")
	f.set_value("eq", "[1,2,3]")
	_eq(f.validate("eq") != "", true, "equalizer needs ten gains")
	f.set_value("eq", "[13,0,0,0,0,0,0,0,0,0]")
	_eq(f.validate("eq") != "", true, "equalizer gain range")
	f.set_value("eq", "[1,2,3,4,5,6,7,8,9,10]")
	_eq(f.validate("eq"), "", "valid equalizer")
	f.set_value("theme", "a\nb")
	_eq(f.validate("theme") != "", true, "multiline rejected")
	f.set_value("theme", "ok")
	var errors := f.validate_changed()
	_eq(errors.has("theme"), false, "valid change not reported")
	_eq(errors.has("mono"), true, "invalid change reported")
	f.set_value("mono", "false")
	f.set_value("repeat", "off")
	f.set_value("volume", "-5")
	f.set_value("seek_large_step_sec", "30")
	f.set_value("plugins.disabled", "[\"a\"]")
	f.set_value("eq", "[0,0,0,0,0,0,0,0,0,0]")
	f.set_value("theme", "nord")
	_eq(f.validate_changed(), {}, "no errors when nothing changed")


func _test_groups_filter() -> void:
	var f := _schema()
	var all := f.groups("")
	_eq(all.size(), 4, "group count")
	_eq(all[0]["name"], "Playback", "schema order preserved")
	_eq((all[0]["fields"] as Array).size(), 4, "fields per group")
	var hit := f.groups("  SEEK ")
	_eq(hit.size(), 1, "filter by label, trimmed, case-insensitive")
	_eq((hit[0]["fields"] as Array)[0]["key"], "seek_large_step_sec", "filtered field")
	_eq(f.groups("appearance").size(), 1, "filter by group name")
	_eq((f.groups("appearance")[0]["fields"] as Array).size(), 1, "group filter keeps matching fields")
	_eq(f.groups("plugins.disabled").size(), 1, "filter by key")
	_eq(f.groups("zzz").size(), 0, "no match")


func _test_secret() -> void:
	var f := SchemaForm.new()
	f.add_field(SchemaForm.normalize_field({"key": "token", "type": "secret", "value": "should-not-leak"}))
	_eq(f.value("token"), "", "secret never carries a value")
	_eq(f.is_dirty(), false, "untouched secret is clean")
	_eq(f.changed(), {}, "untouched secret not sent")
	f.set_value("token", "")
	_eq(f.changed(), {"token": ""}, "explicit empty clears")
	f.set_value("token", "new")
	_eq(f.changed(), {"token": "new"}, "replacement sent")
	f.mark_saved(f.changed())
	_eq(f.value("token"), "", "value dropped after save")
	_eq(f.is_dirty(), false, "clean after save")
	_eq(f.add_field(SchemaForm.normalize_field({"key": "token"})), false, "duplicate add refused")


func _test_plugin_logic() -> void:
	var plugins := PluginLogic.parse_plugins({"plugins": [
		{"id": "a", "name": "Alpha", "version": "1.0", "type": "visualizer", "trust": "trusted", "permissions": ["control"], "enabled": true, "config_keys": ["api_key"]},
		{"id": "b"},
		"junk",
	]})
	_eq(plugins.size(), 2, "non-object plugins skipped")
	_eq(plugins[0]["permissions"], ["control"], "permissions parsed")
	_eq(plugins[1]["trust"], "untrusted", "default trust")
	_eq(plugins[1]["name"], "b", "name falls back to id")
	_eq(PluginLogic.subtitle(plugins[0]), "1.0  ·  visualizer  ·  trusted", "subtitle")
	_eq(PluginLogic.is_trusted(plugins[0]), true, "trusted")
	_eq(PluginLogic.config_key_error("api_key"), "", "valid key")
	for bad in ["", " ", "a b", "a.b", "a=b", "[x]", " lead"]:
		_eq(PluginLogic.config_key_error(bad) != "", true, "bad key '%s'" % bad)
	var review := {"token": "t", "source": "s", "sha256": "h", "name": "n", "code": "c", "action": "install", "permissions": ["control"]}
	_eq(PluginLogic.is_valid_review(review), true, "valid review")
	_eq(PluginLogic.is_valid_review({"token": "t"}), false, "incomplete review")
	_eq(PluginLogic.is_valid_review(null), false, "null review")
	var approval := PluginLogic.approval(review)
	_eq(approval["action"], "apply", "install approves with apply")
	_eq(approval["values"], {"token": "t", "source": "s", "sha256": "h", "permissions": ["control"]}, "approval echoes review")
	review["action"] = "trust"
	_eq(PluginLogic.approval(review)["action"], "trust", "trust review")
	_eq(PluginLogic.split_command("lyrics  sync"), PackedStringArray(["lyrics", "sync"]), "split command")
	_eq(PluginLogic.split_command(""), PackedStringArray(["", ""]), "split empty")
	_eq(PluginLogic.parse_args("[\"a\"]"), {"args": ["a"]}, "args ok")
	_eq(PluginLogic.parse_args("").has("args"), true, "empty args ok")
	_eq(PluginLogic.parse_args("[1]").has("error"), true, "non-string args")
	_eq(PluginLogic.parse_args("{}").has("error"), true, "non-array args")
