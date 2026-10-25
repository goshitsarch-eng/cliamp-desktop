class_name SchemaForm
extends RefCounted
## Model of a schema-driven settings form: field list, current values, dirty
## tracking, validation and group filtering. No nodes, so it is unit tested.
##
## Field shape (cmd/preferences_desktop.go): key, label, group, type (string,
## number, integer, bool, list, equalizer, secret), value, help, options, min, max.
## Values are always Strings, as the engine stores them.
##
## Secret fields never carry a value: they start empty and count as changed
## only once touched, so an untouched secret is never sent and an explicit
## empty value clears the stored setting.

const KIND_TEXT := "text"
const KIND_NUMBER := "number"
const KIND_BOOL := "bool"
const KIND_CHOICE := "choice"
const KIND_LIST := "list"
const KIND_SECRET := "secret"

var fields: Array[Dictionary] = []
var _initial: Dictionary = {}
var _values: Dictionary = {}
var _touched: Dictionary = {}


## Normalizes one raw schema field. Missing or mistyped properties get defaults.
static func normalize_field(raw: Dictionary) -> Dictionary:
	var key := Util.text(raw.get("key"))
	var options: Array[String] = []
	var raw_options: Variant = raw.get("options")
	if raw_options is Array:
		for o in raw_options:
			options.append(str(o))
	var field := {
		"key": key,
		"label": Util.text(raw.get("label"), key),
		"group": Util.text(raw.get("group"), "General"),
		"type": Util.text(raw.get("type"), "string"),
		"value": "" if raw.get("value") == null else str(raw.get("value")),
		"help": Util.text(raw.get("help")),
		"options": options,
		"min": null,
		"max": null,
	}
	var lo: Variant = raw.get("min")
	var hi: Variant = raw.get("max")
	if (lo is float or lo is int) and (hi is float or hi is int):
		field["min"] = float(lo)
		field["max"] = float(hi)
	return field


## Parsed JSON, or null when `text` is not valid JSON (no engine error output).
static func parse_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func kind_of(field: Dictionary) -> String:
	var type := str(field.get("type", "string"))
	if type == "secret":
		return KIND_SECRET
	if type == "bool":
		return KIND_BOOL
	if not (field.get("options") as Array).is_empty():
		return KIND_CHOICE
	if type == "list":
		return KIND_LIST
	if type == "number" or type == "integer":
		return KIND_NUMBER
	return KIND_TEXT


## Replaces the fields from a schema's `fields` array. Entries without a key or
## with a repeated key are dropped.
func load_fields(raw_fields: Variant) -> void:
	fields.clear()
	_initial.clear()
	_values.clear()
	_touched.clear()
	if raw_fields is Array:
		for raw in raw_fields:
			if raw is Dictionary:
				add_field(normalize_field(raw))


## Adds one normalized field, for forms that grow at runtime.
func add_field(field: Dictionary) -> bool:
	var key := str(field.get("key", ""))
	if key.is_empty() or _initial.has(key):
		return false
	fields.append(field)
	var value := "" if kind_of(field) == KIND_SECRET else str(field.get("value", ""))
	_initial[key] = value
	_values[key] = value
	return true


func has_field(key: String) -> bool:
	return _initial.has(key)


func field(key: String) -> Dictionary:
	for f in fields:
		if f["key"] == key:
			return f
	return {}


func value(key: String) -> String:
	return _values.get(key, "")


func initial(key: String) -> String:
	return _initial.get(key, "")


func set_value(key: String, new_value: String) -> void:
	if not _values.has(key):
		return
	_values[key] = new_value
	if kind_of(field(key)) == KIND_SECRET:
		_touched[key] = true


func is_changed(key: String) -> bool:
	if not _values.has(key):
		return false
	if kind_of(field(key)) == KIND_SECRET:
		return _touched.get(key, false)
	return _values[key] != _initial[key]


func is_dirty() -> bool:
	for key in _values:
		if is_changed(key):
			return true
	return false


## Only the changed entries, which is all the engine needs; unrelated
## configuration is therefore never rewritten.
func changed() -> Dictionary:
	var out := {}
	for f in fields:
		if is_changed(f["key"]):
			out[f["key"]] = _values[f["key"]]
	return out


## Records `saved` (a result of changed()) as the new baseline.
func mark_saved(saved: Dictionary) -> void:
	for key in saved:
		if _values.has(key):
			_initial[key] = saved[key]
			_touched.erase(key)
			if kind_of(field(key)) == KIND_SECRET:
				_values[key] = ""
				_initial[key] = ""


## Reverts one field to its baseline.
func reset(key: String) -> void:
	if _values.has(key):
		_values[key] = _initial[key]
		_touched.erase(key)


## Error text for the current value of one field, or "" when valid. Mirrors the
## engine's encodePreference so that mistakes surface before saving.
func validate(key: String) -> String:
	if not _values.has(key):
		return "Unknown setting."
	var f := field(key)
	var v: String = _values[key]
	if v.contains("\n") or v.contains("\r"):
		return "Use a single-line value."
	var options: Array = f["options"]
	match kind_of(f):
		KIND_BOOL:
			if v != "true" and v != "false":
				return "Must be true or false."
		KIND_CHOICE:
			if not options.has(v):
				return "Choose a supported option."
		KIND_NUMBER:
			return _validate_number(f, v)
		KIND_LIST:
			return _validate_list(v)
	if str(f["type"]) == "equalizer":
		return _validate_equalizer(v)
	return ""


static func _validate_number(f: Dictionary, v: String) -> String:
	var text := v.strip_edges()
	if not text.is_valid_float():
		return "Enter a number."
	var n := text.to_float()
	if is_inf(n) or is_nan(n):
		return "Enter a finite number."
	if str(f["type"]) == "integer" and n != floorf(n):
		return "Enter a whole number."
	if f["min"] != null and (n < f["min"] or n > f["max"]):
		return "Outside the supported range (%s to %s)." % [_num(f["min"]), _num(f["max"])]
	return ""


static func _validate_list(v: String) -> String:
	var parsed: Variant = SchemaForm.parse_json(v)
	if not (parsed is Array):
		return "Provide a JSON array of names."
	for item in parsed:
		if not (item is String):
			return "Provide a JSON array of names."
		if item.contains("\n") or item.contains("\r"):
			return "Names must be single-line."
	return ""


static func _validate_equalizer(v: String) -> String:
	var parsed: Variant = SchemaForm.parse_json(v)
	if not (parsed is Array) or parsed.size() != 10:
		return "Provide ten equalizer gains."
	for gain in parsed:
		if not (gain is float or gain is int):
			return "Provide ten equalizer gains."
		if gain < -12 or gain > 12:
			return "Equalizer gains must be between -12 and 12."
	return ""


## Errors for every changed field: {key: message}. Empty means safe to save.
func validate_changed() -> Dictionary:
	var out := {}
	for f in fields:
		var key: String = f["key"]
		if is_changed(key):
			var e := validate(key)
			if not e.is_empty():
				out[key] = e
	return out


## Fields matching `filter` (case-insensitive substring of group, label and
## key) as [{name, fields}] in schema order. An empty filter matches all.
func groups(filter := "") -> Array[Dictionary]:
	var needle := filter.strip_edges().to_lower()
	var out: Array[Dictionary] = []
	var index := {}
	for f in fields:
		if not needle.is_empty() and not ("%s %s %s" % [f["group"], f["label"], f["key"]]).to_lower().contains(needle):
			continue
		var name: String = f["group"]
		if not index.has(name):
			index[name] = out.size()
			out.append({"name": name, "fields": [] as Array[Dictionary]})
		(out[index[name]]["fields"] as Array[Dictionary]).append(f)
	return out


## "Range: -90 to 6" or "" when the field has no bounds.
static func range_text(f: Dictionary) -> String:
	if f.get("min") == null or f.get("max") == null:
		return ""
	return "Range: %s to %s" % [_num(f["min"]), _num(f["max"])]


static func _num(n: float) -> String:
	return str(int(n)) if n == floorf(n) else str(n)
