class_name Fuzzy
extends RefCounted
## Same subsequence ranking used by the engine's local playlist/file filters.
## -1 means no match; stable callers preserve source order for equal scores.

const SEPARATORS := " -_/\\.:()[]"


static func score(query: String, target: String) -> int:
	var q := query.to_lower()
	if q.is_empty():
		return 0
	var text := target.to_lower()
	var qi := 0
	var last := -2
	var total := 0
	for i in text.length():
		if text[i] != q[qi]:
			continue
		total += 1
		if i == 0:
			total += 6
		elif SEPARATORS.contains(text[i - 1]):
			total += 4
		if i == last + 1:
			total += 4
		last = i
		qi += 1
		if qi == q.length():
			return total
	return -1


## Indexes of `items` matching `query`, best score first, ties in source order.
## `key` maps an item to the text searched.
static func rank(query: String, items: Array, key: Callable) -> PackedInt32Array:
	var scored: Array = []
	for i in items.size():
		var s := score(query, key.call(items[i]))
		if s >= 0:
			scored.append([i, s])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] if a[1] == b[1] else a[1] > b[1])
	var out := PackedInt32Array()
	for entry: Array in scored:
		out.append(entry[0])
	return out
