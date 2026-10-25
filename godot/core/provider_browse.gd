class_name ProviderBrowse
extends RefCounted
## Pure rules of the provider browser: which view each mode opens, which controls
## the provider's capability flags allow, how a search is routed and how a
## collection is filtered. Mirrors desktop/lib/src/provider_browser.dart.


## One browsable collection: the operation that loads it and the key of its rows
## in the response.
class View extends RefCounted:
	var operation := ""
	var kind := ""
	var title := ""
	var params: Dictionary = {}
	var open_in_playlist := false

	func _init(p_operation := "", p_kind := "", p_title := "", p_params := {}, p_open_in_playlist := false) -> void:
		operation = p_operation
		kind = p_kind
		title = p_title
		params = p_params
		open_in_playlist = p_open_in_playlist

	func with_params(p_params: Dictionary) -> View:
		return View.new(operation, kind, title, p_params, open_in_playlist)


## The view a browse mode opens. `entry` is a browse entry Dictionary or null.
static func mode_view(mode: String, entry: Variant, browse: Dictionary) -> View:
	var has_entry := entry is Dictionary
	var name := Util.text(entry.get("name")) if has_entry else ""
	var params := {}
	if has_entry:
		params["entry"] = entry.get("id")
	var in_playlist: bool = has_entry and entry.get("open_in_playlist") == true
	match mode:
		"albums":
			if browse.get("album_sort") != null:
				params["sort"] = browse["album_sort"]
			return View.new("provider.albums", "albums", name if not name.is_empty() else Util.text(browse.get("album_label"), "Album") + "s", params, in_playlist)
		"artists", "artist_albums":
			return View.new("provider.artists", "artists", name if not name.is_empty() else Util.text(browse.get("artist_label"), "Artist") + "s", params, in_playlist)
		"genres":
			return View.new("provider.genres", "genres", name if not name.is_empty() else Util.text(browse.get("genre_label"), "Genres"), params, in_playlist)
		"subscriptions":
			return View.new("provider.subscriptions", "subscriptions", "Subscriptions")
		"catalog":
			return View.new("provider.catalog", "playlists", "Catalog")
	return View.new("provider.playlists", "playlists", "Playlists")


static func route_icon(mode: String) -> String:
	match mode:
		"albums":
			return "album"
		"genres":
			return "public"
	return "person_outline"


## The mode chips under the search box. Each is {label, icon, mode, entry} where
## mode is a browse mode, "subscriptions", "catalog", or "location".
static func routes(browse: Dictionary, provider: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"label": "Playlists", "icon": "library_music", "mode": "playlists", "entry": null}]
	var entries := Util.objects(browse.get("entries"))
	for entry in entries:
		out.append({"label": Util.text(entry.get("name")), "icon": route_icon(Util.text(entry.get("mode"))), "mode": Util.text(entry.get("mode")), "entry": entry})
	var modes: Array = browse.get("modes") if browse.get("modes") is Array else []
	for m in modes:
		var mode := str(m)
		var covered := false
		for entry in entries:
			if str(entry.get("mode")) == mode:
				covered = true
				break
		if covered:
			continue
		var label := Util.text(browse.get("artist_label"), "Artist") + "s"
		if mode == "albums":
			label = Util.text(browse.get("album_label"), "Album") + "s"
		elif mode == "genres":
			label = Util.text(browse.get("genre_label"), "Genres")
		out.append({"label": label, "icon": route_icon(mode), "mode": mode, "entry": null})
	if browse.get("subscriptions") == true:
		out.append({"label": "Subscriptions", "icon": "subscriptions", "mode": "subscriptions", "entry": null})
	if provider.get("catalog") == true:
		out.append({"label": "Station catalog", "icon": "radio", "mode": "catalog", "entry": null})
	if Util.object(browse.get("location")).get("needed") == true:
		out.append({"label": "Local radio", "icon": "location_on", "mode": "location", "entry": null})
	return out


## How a submitted search is routed: "catalog", "clear", "genres", "search" or "filter".
static func search_plan(query: String, view: View, browse: Dictionary, response: Dictionary, provider: Dictionary) -> String:
	if browse.get("catalog_search") == true and view.kind == "playlists":
		return "catalog"
	if query.strip_edges().is_empty():
		return "clear"
	if view.kind == "genres" and response.get("searchable") == true:
		return "genres"
	if provider.get("searchable") == true and view.kind != "genres" and view.kind != "subscriptions":
		return "search"
	return "filter"


## The source name provider.collection takes for a track view, "" when none.
static func collection_source(operation: String) -> String:
	match operation:
		"provider.tracks":
			return "playlist"
		"provider.album_tracks":
			return "album"
		"provider.genre_tracks":
			return "genre"
		"provider.search":
			return "search"
		"provider.related":
			return "related"
	return ""


## Id of the album a search result stands for, "" for a plain track.
static func album_id(track: Dictionary) -> String:
	var meta := Util.object(track.get("provider_meta"))
	if meta.get("kind") != "album":
		return ""
	return Util.text(meta.get("albumID"))


## True when the operation edits the shared queue and so needs a revision guard.
static func changes_queue(operation: String, params: Dictionary) -> bool:
	if operation in ["provider.subscription.load", "provider.subscriptions.newest", "provider.collection", "tracks.append"]:
		return true
	return operation in ["provider.related", "provider.genre_tracks"] and params.get("mode") != null and params.get("mode") != "read"


## m:ss with no hours, as the Flutter list shows it.
static func time(value: Variant) -> String:
	var seconds := clampi(int(Util.number(value)), 0, 999999)
	return "%d:%02d" % [seconds / 60, seconds % 60]


static func count_noun(kind: String) -> String:
	match kind:
		"tracks":
			return "tracks"
		"genres":
			return "categories"
	return kind


static func filter_text(item: Dictionary) -> String:
	var parts := PackedStringArray()
	for key in ["name", "title", "artist", "author", "group"]:
		parts.append(Util.text(item.get(key)))
	return " ".join(parts)


## `items` that match `query` fuzzily, best first, ties in source order.
static func filtered(items: Array, query: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in Fuzzy.rank(query, items, filter_text):
		out.append(items[i])
	return out


## [title, body] of the empty state.
static func empty_text(narrowed: bool, filter: String, pinned_only: bool, subscriptions: bool) -> PackedStringArray:
	if narrowed:
		var body := "Try another search."
		if not filter.strip_edges().is_empty() and pinned_only:
			body = "Nothing in the pinned filter matches that search."
		elif pinned_only:
			body = "Turn off the pinned filter to see this collection."
		return PackedStringArray(["No matching items", body])
	if subscriptions:
		return PackedStringArray(["No subscribed shows yet", "Favorite a show to keep its episodes here."])
	return PackedStringArray(["This collection is empty", "Refresh or choose another collection."])


## The overflow menu of a track row: [{id, label, disabled}].
static func track_menu(track: Dictionary, browse: Dictionary, operations: Dictionary) -> Array[Dictionary]:
	var album := not album_id(track).is_empty()
	var out: Array[Dictionary] = []
	if album:
		out.append({"id": "open", "label": "Open album", "disabled": false})
		out.append({"id": "append", "label": "Add album to queue", "disabled": false})
		if browse.get("album_favorite") == true:
			out.append({"id": "album_favorite", "label": "Toggle album favorite", "disabled": false})
	out.append({"id": "next", "label": "Play next", "disabled": false})
	if not album:
		out.append({"id": "playlist", "label": "Add to playlist...", "disabled": false})
	if not album and track.get("feed") != true and operations.has("tracks.append"):
		out.append({"id": "append", "label": "Add to queue", "disabled": track.get("unplayable") == true})
	out.append({"id": "details", "label": "Track details", "disabled": false})
	if not album and browse.get("related") == true:
		out.append({"id": "related", "label": "Find related tracks", "disabled": false})
	if not album and browse.get("track_artist") == true:
		out.append({"id": "artist", "label": "Go to " + Util.text(browse.get("artist_label"), "artist").to_lower(), "disabled": false})
	return out


## Row icon of a collection item.
static func item_icon(kind: String) -> String:
	match kind:
		"genres":
			return "public"
		"subscriptions":
			return "podcasts"
		"artists":
			return "person_outline"
		"albums":
			return "album"
	return "queue_music"


## Second line of a collection row.
static func item_subtitle(item: Dictionary) -> String:
	var fallback := Util.text(item.get("section"))
	if item.get("album_count") != null:
		fallback = "%s albums" % item["album_count"]
	if item.get("track_count") != null:
		fallback = "%s tracks" % item["track_count"]
	return Util.text(item.get("author"), Util.text(item.get("artist"), fallback))


## "Section" header of an item, "" when it has none.
static func group_of(item: Dictionary) -> String:
	return Util.text(item.get("section"), Util.text(item.get("group")))
