class_name Util
extends RefCounted
## Helpers for the engine's untyped JSON: every value may be missing or have an
## unexpected type, so reads coerce instead of failing.


static func objects(value: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				out.append(item)
	return out


static func object(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


static func number(value: Variant, fallback := 0.0) -> float:
	return float(value) if value is float or value is int else fallback


static func text(value: Variant, fallback := "") -> String:
	if value == null:
		return fallback
	var s := str(value)
	return fallback if s.is_empty() else s


## Coerces untrusted metadata to one clean line so embedded newlines or control
## characters cannot stretch fixed-height row or transport labels.
static func single_line(value: Variant, fallback := "") -> String:
	if value == null:
		return fallback
	var raw := str(value)
	var out := ""
	var prev_space := false
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code < 32 or code == 127:
			if not prev_space and not out.is_empty():
				out += " "
				prev_space = true
		else:
			out += raw[i]
			prev_space = raw[i] == " "
	var cleaned := out.strip_edges()
	return fallback if cleaned.is_empty() else cleaned


## "1 track", "2 tracks". JSON numbers arrive as floats, so the count is rounded.
static func count_of(value: Variant, singular: String, plural := "") -> String:
	var n := roundi(number(value))
	return "%d %s" % [n, singular if n == 1 else (plural if not plural.is_empty() else singular + "s")]


## Like `duration`, but "--:--" when the length is not known yet.
static func duration_or_unknown(value: Variant) -> String:
	return "--:--" if number(value) <= 0.0 else duration(value)


## 3725 -> "1:02:05", 75 -> "1:15".
static func duration(value: Variant) -> String:
	var seconds := clampi(roundi(number(value)), 0, 999999)
	var minutes := seconds / 60
	var hours := minutes / 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes % 60, seconds % 60]
	return "%d:%02d" % [minutes, seconds % 60]


## File name of a path with either separator.
static func basename(path: String) -> String:
	return path.replace("\\", "/").get_file()


## Nearest ancestor of `node` that is a Window, for parenting dialogs.
static func host(node: Node) -> Node:
	return node.get_tree().root
