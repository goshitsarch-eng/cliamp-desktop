class_name LyricsLogic
extends RefCounted
## Pure lyric timing rules from lyrics.dart.

const MAX_OFFSET_MS := 10000
const STEP_MS := 250


static func start_of(line: Dictionary) -> float:
	return Util.number(line.get("start"))


## Untimed lyrics and live streams have no reliable playback timebase.
static func is_synced(lines: Array, realtime: bool) -> bool:
	if realtime:
		return false
	for line in lines:
		if line is Dictionary and start_of(line) > 0.0:
			return true
	return false


## Index of the last line that has started, or -1. Mirrors the Dart loop, which
## keeps the last match rather than stopping at the first miss.
static func active_index(lines: Array, position: float, offset_ms: int) -> int:
	var active := -1
	var at := position + offset_ms / 1000.0
	for i in lines.size():
		if lines[i] is Dictionary and start_of(lines[i]) <= at:
			active = i
	return active


static func seek_target(line: Dictionary, offset_ms: int) -> float:
	return maxf(0.0, start_of(line) - offset_ms / 1000.0)


static func clamp_offset(ms: int) -> int:
	return clampi(ms, -MAX_OFFSET_MS, MAX_OFFSET_MS)


static func offset_text(ms: int) -> String:
	return "%s%d ms" % ["+" if ms >= 0 else "", ms]


## Same identity test as the Dart trackChanged check.
static func track_changed(a: Dictionary, b: Dictionary) -> bool:
	for field in ["path", "title", "artist"]:
		if a.get(field) != b.get(field):
			return true
	return false
