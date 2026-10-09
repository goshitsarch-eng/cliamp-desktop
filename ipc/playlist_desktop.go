package ipc

// RegisterDesktopPlaylistOperations adds the graphical playlist tools. Existing
// playlist write operations keep their names and gain shared undo capture.
func RegisterDesktopPlaylistOperations(registry *OperationRegistry) {
	for _, op := range []Operation{
		{Name: "playlist.capabilities", Description: "read supported playlist writes", Parameters: []string{"provider", "playlist"}},
		{Name: "playlist.dirs.list", Description: "list saved playlist directory sources", Parameters: []string{"provider", "playlist"}},
		{Name: "playlist.dirs.add", Description: "add a saved playlist directory source", Parameters: []string{"provider", "playlist", "path"}},
		{Name: "playlist.dirs.remove", Description: "remove a saved playlist directory source", Parameters: []string{"provider", "playlist", "path"}},
		{Name: "playlist.dirs.recursive", Description: "set a directory source recursive mode", Parameters: []string{"provider", "playlist", "path", "name"}},
		{Name: "playlist.prepend", Description: "prepend tracks, moving existing explicit tracks to the front", Parameters: []string{"provider", "playlist", "tracks"}},
		{Name: "playlist.undo", Description: "undo the last saved playlist edit if unchanged since", Parameters: []string{"provider", "playlist"}},
		{Name: "playlist.remove_many", Description: "remove saved tracks in one edit after verifying their paths", Parameters: []string{"provider", "playlist", "indexes", "tracks"}},
		{Name: "playlist.sort", Description: "sort an entire saved playlist", Parameters: []string{"provider", "playlist", "sort"}},
		{Name: "playlist.move", Description: "move a saved playlist track", Parameters: []string{"provider", "playlist", "index", "to", "track"}},
		{Name: "playlist.save_queue", Description: "create a new saved playlist from the complete current live playlist", Parameters: []string{"provider", "playlist", "if_revision"}},
		{Name: "playlist.import", Description: "resolve files and playlists and append their tracks to a saved playlist", Parameters: []string{"provider", "playlist", "args"}},
		{Name: "queue.undo", Description: "undo the latest live playlist or play-next edit", Parameters: []string{"if_revision"}},
		{Name: "queue.remove_many", Description: "remove live tracks in one undoable edit", Parameters: []string{"indexes", "if_revision"}},
		{Name: "playnext.remove_many", Description: "remove play-next entries in one undoable edit", Parameters: []string{"indexes", "if_revision"}},
		{Name: "tracks.append", Description: "append complete track records to the live playlist", Parameters: []string{"tracks", "play", "index", "if_revision"}},
		{Name: "tracks.replace", Description: "replace the live playlist with complete track records", Parameters: []string{"tracks", "play", "index", "if_revision"}},
		{Name: "tracks.enqueue", Description: "append and queue complete tracks next in input order", Parameters: []string{"tracks", "play", "index", "if_revision"}},
	} {
		op.Async = true
		registry.Register(op)
	}
}
