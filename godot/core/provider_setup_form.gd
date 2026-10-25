class_name ProviderSetupForm
extends RefCounted
## Pure helpers of the provider setup form, from provider_setup.dart. Values are
## always Strings keyed by schema field key.


static func intro_text(intro: Variant) -> String:
	if intro is Array:
		var lines := PackedStringArray()
		for line in intro:
			lines.append(str(line))
		return "\n".join(lines)
	return Util.text(intro)


## Adds schema defaults for keys the user has not set.
static func merge_defaults(values: Dictionary, defaults: Variant) -> void:
	if defaults is Dictionary:
		for key in defaults:
			if not values.has(str(key)):
				values[str(key)] = str(defaults[key])


static func field_label(field: Dictionary) -> String:
	return Util.text(field.get("label")) + (" *" if field.get("required") == true else "")


## Keys of required fields whose value is blank.
static func missing_required(fields: Array, values: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for field in fields:
		if field is Dictionary and field.get("required") == true:
			if str(values.get(str(field.get("key")), "")).strip_edges().is_empty():
				out.append(str(field.get("key")))
	return out


## Index of `value` among picker options, 0 (the first option) when absent.
static func option_index(options: Array, value: String) -> int:
	for i in options.size():
		if options[i] is Dictionary and str(options[i].get("value")) == value:
			return i
	return 0
