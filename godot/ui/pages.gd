class_name Pages
extends RefCounted
## The navigation table. `script` is created lazily by the shell and must extend
## Page. `title` heads the page, `label` is the sidebar text.

const LIST: Array[Dictionary] = [
	{"id": "queue", "title": "Your queue", "label": "Queue", "icon": "queue_music", "script": "res://ui/pages/queue_page.gd"},
	{"id": "next", "title": "Play next", "label": "Play next", "icon": "playlist_play", "script": "res://ui/pages/next_page.gd"},
	{"id": "providers", "title": "Explore providers", "label": "Providers", "icon": "explore", "script": "res://ui/pages/providers_page.gd"},
	{"id": "playlists", "title": "Your playlists", "label": "Playlists", "icon": "library_music", "script": "res://ui/pages/playlists_page.gd"},
	{"id": "favorites", "title": "Favorites", "label": "Favorites", "icon": "favorite", "script": "res://ui/pages/favorites_page.gd"},
	{"id": "history", "title": "Recently played", "label": "History", "icon": "history", "script": "res://ui/pages/history_page.gd"},
	{"id": "lyrics", "title": "Lyrics", "label": "Lyrics", "icon": "lyrics", "script": "res://ui/pages/lyrics_page.gd"},
	{"id": "visualizer", "title": "Visualizer", "label": "Visualizer", "icon": "graphic_eq", "script": "res://ui/pages/visualizer_page.gd"},
	{"id": "equalizer", "title": "Equalizer", "label": "Equalizer", "icon": "equalizer", "script": "res://ui/pages/equalizer_page.gd"},
	{"id": "plugins", "title": "Plugins", "label": "Plugins", "icon": "extension", "script": "res://ui/pages/plugins_page.gd"},
	{"id": "settings", "title": "Settings", "label": "Settings", "icon": "tune", "script": "res://ui/pages/settings_page.gd"},
]


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return -1
