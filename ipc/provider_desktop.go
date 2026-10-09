package ipc

// ProviderBrowseInfo describes the actual routes and actions of a configured
// provider. Clients use these capabilities instead of assuming music labels
// or treating browse and consent rows as playable playlists.
type ProviderBrowseInfo struct {
	Entries          []ProviderBrowseEntry `json:"entries"`
	Modes            []string              `json:"modes"`
	DefaultMode      string                `json:"default_mode,omitempty"`
	ArtistLabel      string                `json:"artist_label"`
	AlbumLabel       string                `json:"album_label"`
	GenreLabel       string                `json:"genre_label"`
	Refreshable      bool                  `json:"refreshable"`
	Subscriptions    bool                  `json:"subscriptions"`
	Shows            bool                  `json:"shows"`
	Related          bool                  `json:"related"`
	TrackArtist      bool                  `json:"track_artist"`
	CatalogSearch    bool                  `json:"catalog_search"`
	AlbumSortSavable bool                  `json:"album_sort_savable"`
	AlbumFavorite    bool                  `json:"album_favorite"`
	AlbumSort        string                `json:"album_sort,omitempty"`
	AlbumSorts       []SortInfo            `json:"album_sorts,omitempty"`
	Location         *ProviderLocationInfo `json:"location,omitempty"`
}

type ProviderBrowseEntry struct {
	ID             string `json:"id"`
	Name           string `json:"name"`
	Section        string `json:"section,omitempty"`
	Mode           string `json:"mode"`
	AfterID        string `json:"after_id,omitempty"`
	AfterSection   string `json:"after_section,omitempty"`
	OpenInPlaylist bool   `json:"open_in_playlist"`
}

type ProviderLocationInfo struct {
	Needed bool   `json:"needed"`
	ID     string `json:"id"`
	Prompt string `json:"prompt"`
}

type ProviderGenreInfo struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Group    string `json:"group,omitempty"`
	Favorite bool   `json:"favorite"`
}

type ProviderSubscriptionInfo struct {
	ID     string `json:"id"`
	Name   string `json:"name"`
	Author string `json:"author,omitempty"`
}

// ProviderListeningInfo is stored episode state. Absence means the provider
// has no locally known state for that track, rather than "not played".
type ProviderListeningInfo struct {
	Played   bool    `json:"played"`
	Position float64 `json:"position"`
}

type ProviderDesktopResponse struct {
	Response
	Provider      string                           `json:"provider,omitempty"`
	Browse        *ProviderBrowseInfo              `json:"browse,omitempty"`
	Genres        []ProviderGenreInfo              `json:"genres,omitempty"`
	GenreLabel    string                           `json:"genre_label,omitempty"`
	Favoritable   bool                             `json:"favoritable"`
	Searchable    bool                             `json:"searchable"`
	Favorite      *bool                            `json:"favorite,omitempty"`
	Location      *ProviderLocationInfo            `json:"location,omitempty"`
	Place         string                           `json:"place,omitempty"`
	Subscriptions []ProviderSubscriptionInfo       `json:"subscriptions,omitempty"`
	Failed        []string                         `json:"failed,omitempty"`
	Artist        *ArtistInfo                      `json:"artist,omitempty"`
	Listening     map[string]ProviderListeningInfo `json:"listening,omitempty"`
}

var providerDesktopOperations = []Operation{
	{Name: "provider.browse", Description: "describe provider routes, labels, and capabilities", Parameters: []string{"provider"}},
	{Name: "provider.refresh", Description: "refresh a provider or a stable provider playlist", Parameters: []string{"provider", "playlist", "offset", "limit"}},
	{Name: "provider.genres", Description: "browse or search routed genres and categories", Parameters: []string{"provider", "entry", "query", "offset", "limit"}},
	{Name: "provider.genre_tracks", Description: "list or load tracks in a routed genre or category", Parameters: []string{"provider", "entry", "genre", "sort", "offset", "limit", "mode", "if_revision"}},
	{Name: "provider.genre.favorite", Description: "toggle a routed genre favorite", Parameters: []string{"provider", "entry", "genre"}},
	{Name: "provider.location", Description: "read the provider's location consent prompt", Parameters: []string{"provider"}},
	{Name: "provider.location.consent", Description: "record an explicit location choice", Parameters: []string{"provider", "allowed"}},
	{Name: "provider.album_sort", Description: "persist an album sort preference", Parameters: []string{"provider", "sort"}},
	{Name: "provider.catalog.search", Description: "search or clear a provider catalog", Parameters: []string{"provider", "query", "offset", "limit"}},
	{Name: "provider.subscriptions", Description: "list subscribed shows", Parameters: []string{"provider", "offset", "limit"}},
	{Name: "provider.subscription.load", Description: "append, play, or queue a show or its newest episode", Parameters: []string{"provider", "playlist", "mode", "if_revision"}},
	{Name: "provider.subscriptions.newest", Description: "append or queue the newest episode of every subscription", Parameters: []string{"provider", "mode", "if_revision"}},
	{Name: "provider.related", Description: "find or load songs related to a track", Parameters: []string{"provider", "track", "limit", "mode", "if_revision"}},
	{Name: "provider.track_artist", Description: "resolve a track's artist and browse their albums", Parameters: []string{"provider", "track", "offset", "limit"}},
	{Name: "provider.playback_state", Description: "read locally known episode listening state", Parameters: []string{"provider", "tracks"}},
	{Name: "provider.collection", Description: "play or add a complete provider collection with optional filtering", Parameters: []string{"provider", "source", "playlist", "album", "genre", "entry", "sort", "query", "track", "filter", "mode", "selected_path", "if_revision"}},
}

func RegisterProviderDesktopOperations(registry *OperationRegistry) {
	for _, operation := range providerDesktopOperations {
		operation.Async = true
		registry.Register(operation)
	}
}

func IsProviderDesktopOperation(name string) bool {
	for _, operation := range providerDesktopOperations {
		if operation.Name == name {
			return true
		}
	}
	return false
}
