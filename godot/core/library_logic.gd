class_name LibraryLogic
extends RefCounted
## Pure list logic for the library pages: filtering, selection ranges and the
## text shown in rows. No nodes, so it can be tested headless.

const SEARCH_KEYS: PackedStringArray = ["title", "name", "artist", "album", "path", "station", "genre"]
const SYSTEM_PLAYLISTS: PackedStringArray = ["Favorites", "Recently Played"]


## History items wrap the track as {track, played_at}; everything else is a track.
static func track_of(item: Dictionary, kind: String) -> Dictionary:
	return Util.object(item.get("track")) if kind == "history" else item


static func search_text(item: Dictionary, kind: String) -> String:
	var track := track_of(item, kind)
	var parts := PackedStringArray()
	for key in SEARCH_KEYS:
		parts.append(Util.text(track.get(key)))
	return " ".join(parts)


## Positions in `items` that match `filter`, best match first, ties in source order.
static func visible_tracks(items: Array[Dictionary], filter: String, kind: String) -> PackedInt32Array:
	if filter.is_empty():
		var all := PackedInt32Array()
		all.resize(items.size())
		for i in items.size():
			all[i] = i
		return all
	return Fuzzy.rank(filter, items, func(item: Dictionary) -> String: return search_text(item, kind))


## Positions in `items` that match `filter`, in source order (collection grids).
static func visible_collection(items: Array[Dictionary], filter: String, kind: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in items.size():
		if filter.is_empty() or Fuzzy.score(filter, search_text(items[i], kind)) >= 0:
			out.append(i)
	return out


## Shift-click range: the items between `anchor` and `position` as they are
## ordered in `visible` (positions into the item list), both ends included.
static func shift_range(visible: PackedInt32Array, anchor: int, position: int) -> PackedInt32Array:
	var from := visible.find(anchor)
	var to := visible.find(position)
	if from < 0 or to < 0:
		return PackedInt32Array()
	return visible.slice(mini(from, to), maxi(from, to) + 1)


## "Select visible": clears the visible positions when all are marked, else
## marks them all. `marked` maps position -> true; returns the new mapping.
static func toggle_visible(visible: PackedInt32Array, marked: Dictionary) -> Dictionary:
	var out := marked.duplicate()
	var all := true
	for p in visible:
		if not out.has(p):
			all = false
			break
	for p in visible:
		if all:
			out.erase(p)
		else:
			out[p] = true
	return out


static func title_of(track: Dictionary) -> String:
	return Util.single_line(track.get("title"), Util.single_line(Util.basename(Util.text(track.get("path"), "Untitled track")), "Untitled track"))


static func artist_of(track: Dictionary) -> String:
	return Util.single_line(track.get("artist"), Util.single_line(track.get("station"), "Live stream" if track.get("stream") == true else "Unknown artist"))


## "Played", "Continue at 1:02" or "" for a provider playback_state entry.
static func listening_text(entry: Dictionary) -> String:
	if entry.get("played") == true:
		return "Played"
	var resume := Util.number(entry.get("position"))
	if resume > 0.0:
		return "Continue at %s" % Util.duration(resume)
	return ""


## Collection card subtitle: artist, track count, album count, section or provider.
static func collection_subtitle(item: Dictionary, provider: String) -> String:
	var artist := Util.text(item.get("artist"))
	if not artist.is_empty():
		return artist
	if item.get("track_count") != null:
		return Util.count_of(item["track_count"], "track")
	if item.get("album_count") != null:
		return Util.count_of(item["album_count"], "album")
	return Util.text(item.get("section"), provider)


## Unix seconds of an RFC 3339 time (UTC adjusted), or null when it does not parse.
## `has_zone` is set in the second element when the text carried an offset.
static func parse_iso(value: String) -> Variant:
	var re := RegEx.create_from_string("^(\\d{4})-(\\d{2})-(\\d{2})[T ](\\d{2}):(\\d{2})(?::(\\d{2}))?(?:\\.\\d+)?(Z|[+-]\\d{2}(?::?\\d{2})?)?$")
	var m := re.search(value.strip_edges())
	if m == null:
		return null
	var unix := Time.get_unix_time_from_datetime_dict({
		"year": int(m.get_string(1)), "month": int(m.get_string(2)), "day": int(m.get_string(3)),
		"hour": int(m.get_string(4)), "minute": int(m.get_string(5)), "second": int(m.get_string(6)),
	})
	var zone := m.get_string(7)
	if zone.is_empty():
		return [unix, false]
	if zone != "Z":
		var digits := zone.substr(1).replace(":", "")
		var offset := int(digits.substr(0, 2)) * 3600 + int(digits.substr(2, 2)) * 60
		unix -= offset if zone[0] == "+" else -offset
	return [unix, true]


## "2026-03-04 18:05" in local time, or "" when the value is not a time.
static func history_date(value: Variant, bias_minutes: Variant = null) -> String:
	var parsed: Variant = parse_iso(Util.text(value))
	if parsed == null:
		return ""
	var unix: int = parsed[0]
	if parsed[1]:
		var bias: int = int(bias_minutes) if bias_minutes != null else int(Time.get_time_zone_from_system().get("bias", 0))
		unix += bias * 60
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d %02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"]]


## Why a local playlist name cannot be used, "" when it can. Mirrors the engine
## (external/local validateNewName) so the dialog explains it before a round trip.
static func playlist_name_error(name: String) -> String:
	var trimmed := name.strip_edges()
	if trimmed.is_empty():
		return "Enter a value to continue."
	if trimmed == "." or trimmed == "..":
		return "A playlist cannot be named \".\" or \"..\"."
	for ch in ["/", "\\", ":", "<", ">", "\"", "|", "?", "*"]:
		if name.contains(ch):
			return "Playlist names cannot contain any of: / \\ : < > \" | ? *"
	return ""


## The count line of a page header: "1 track in queue", "5 playlists", "1 play".
static func count_line(queue: bool, kind: String, total: int, queued: float) -> String:
	if queue:
		return "%s in queue" % Util.count_of(queued, "track")
	match kind:
		"history":
			return Util.count_of(total, "play")
		"tracks", "playlists", "albums", "artists":
			return Util.count_of(total, kind.trim_suffix("s"))
	return "%d %s" % [total, kind]


## "Title · Artist", or just the title when the artist is unknown.
static func title_with_artist(title: String, artist: String) -> String:
	return title if artist.strip_edges().is_empty() else "%s · %s" % [title, artist]
