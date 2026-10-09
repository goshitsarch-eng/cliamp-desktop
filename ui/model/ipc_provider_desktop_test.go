package model

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
)

func runProviderDesktopV2(t *testing.T, m *Model, op string, params any) ipc.ProviderDesktopResponse {
	t.Helper()
	job := runProviderDesktopJob(t, m, op, params)
	if job.State != ipc.JobSucceeded {
		t.Fatalf("%s failed: state=%s error=%+v", op, job.State, job.Error)
	}
	var response ipc.ProviderDesktopResponse
	if err := json.Unmarshal(job.Result, &response); err != nil {
		t.Fatal(err)
	}
	return response
}

func runProviderDesktopJob(t *testing.T, m *Model, op string, params any) ipc.Job {
	t.Helper()
	request := v2Request(t, op, ipc.Request{})
	raw, err := json.Marshal(params)
	if err != nil {
		t.Fatal(err)
	}
	request.Request.Params = raw
	next, cmd := m.Update(request)
	*m = next.(Model)
	if cmd != nil {
		next, _ = m.Update(cmd())
		*m = next.(Model)
	}
	job, _ := request.Jobs.Get(request.JobID)
	return job
}

type desktopGenreRoute struct {
	genreBrowserProvider
	lastGenre, lastSort string
}

func (*desktopGenreRoute) GenreLabel() string { return "Tags" }
func (p *desktopGenreRoute) GenreTracks(genre, sort string) ([]playlist.Track, error) {
	p.lastGenre, p.lastSort = genre, sort
	return p.tracks, nil
}

type desktopBrowseProvider struct {
	genreBrowserProvider
	route         desktopGenreRoute
	refreshes     int
	listRequests  int
	trackRequests []string
	albumSort     string
	searchQuery   string
	listening     map[string]provider.PlaybackState
}

func (*desktopBrowseProvider) Name() string { return "Desktop catalog" }
func (p *desktopBrowseProvider) Playlists() ([]playlist.PlaylistInfo, error) {
	p.listRequests++
	return []playlist.PlaylistInfo{{ID: "stable", Name: "Stable list", Section: "Library"}}, nil
}
func (p *desktopBrowseProvider) Tracks(id string) ([]playlist.Track, error) {
	p.trackRequests = append(p.trackRequests, id)
	return p.tracks, nil
}
func (p *desktopBrowseProvider) Refresh()                        { p.refreshes++ }
func (*desktopBrowseProvider) CanRefreshPlaylist(id string) bool { return id == "stable" }
func (*desktopBrowseProvider) BrowseLabels() (string, string)    { return "Author", "Book" }
func (*desktopBrowseProvider) BrowseModes() []provider.BrowseMode {
	return []provider.BrowseMode{provider.BrowseGenres}
}
func (*desktopBrowseProvider) DefaultBrowseMode() provider.BrowseMode { return provider.BrowseGenres }
func (*desktopBrowseProvider) BrowseEntries() []provider.BrowseEntry {
	return []provider.BrowseEntry{
		{ID: "genres", Name: "Categories", Mode: provider.BrowseGenres, AfterSection: "Library", OpenInPlaylist: true},
		{ID: "tags", Name: "Tags", Mode: provider.BrowseGenres},
		{ID: "tags", Name: "Duplicate", Mode: provider.BrowseGenres},
		{ID: "", Name: "Invalid", Mode: provider.BrowseGenres},
	}
}
func (p *desktopBrowseProvider) GenreBrowserFor(id string) provider.GenreBrowser {
	if id == "tags" {
		return &p.route
	}
	return p
}
func (*desktopBrowseProvider) Artists() ([]provider.ArtistInfo, error) { return nil, nil }
func (*desktopBrowseProvider) ArtistAlbums(id string) ([]provider.AlbumInfo, error) {
	return []provider.AlbumInfo{{ID: "book", Name: id, Restricted: true}}, nil
}
func (*desktopBrowseProvider) AlbumList(string, int, int) ([]provider.AlbumInfo, error) {
	return nil, nil
}
func (*desktopBrowseProvider) AlbumSortTypes() []provider.SortType {
	return []provider.SortType{{ID: "recent", Label: "Recent"}, {ID: "name", Label: "Name"}}
}
func (p *desktopBrowseProvider) DefaultAlbumSort() string {
	if p.albumSort == "" {
		return "recent"
	}
	return p.albumSort
}
func (p *desktopBrowseProvider) SaveAlbumSort(sort string) error { p.albumSort = sort; return nil }
func (*desktopBrowseProvider) ArtistForTrack(track playlist.Track) (provider.ArtistInfo, bool) {
	return provider.ArtistInfo{ID: "author", Name: "An author"}, strings.HasPrefix(track.Path, "test:")
}
func (*desktopBrowseProvider) CanRelate(track playlist.Track) bool {
	return strings.HasPrefix(track.Path, "test:")
}
func (*desktopBrowseProvider) RelatedTracks(context.Context, playlist.Track, int) ([]playlist.Track, error) {
	return []playlist.Track{{Path: "test:related", Title: "Related", ProviderMeta: map[string]string{"provider.id": "related"}}}, nil
}
func (p *desktopBrowseProvider) SearchCatalog(query string) (int, error) {
	p.searchQuery = query
	return 1, nil
}
func (p *desktopBrowseProvider) ClearSearch()           { p.searchQuery = "" }
func (p *desktopBrowseProvider) IsSearching() bool      { return p.searchQuery != "" }
func (p *desktopBrowseProvider) HasPlaybackState() bool { return len(p.listening) > 0 }
func (p *desktopBrowseProvider) PlaybackState(track playlist.Track) (provider.PlaybackState, bool) {
	state, ok := p.listening[track.Path]
	return state, ok
}

func newDesktopProviderModel(t *testing.T, p playlist.Provider) Model {
	t.Helper()
	return newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "catalog", Name: p.Name(), Provider: p}})
}

func TestProviderDesktopBrowseCapabilitiesAndRoutedGenres(t *testing.T) {
	p := &desktopBrowseProvider{}
	p.genres = []provider.GenreInfo{{ID: "books", Name: "Books"}}
	p.route.genres = []provider.GenreInfo{{ID: "jazz", Name: "Jazz", Group: "Music", Favorite: true}, {ID: "rock", Name: "Rock"}}
	p.route.search = []provider.GenreInfo{{ID: "ambient", Name: "Ambient"}}
	p.route.tracks = []playlist.Track{{Path: "test:one", Title: "One", ProviderMeta: map[string]string{"podcast.guid": "one"}}}
	p.listening = map[string]provider.PlaybackState{"test:one": {Position: 17 * time.Second}}
	m := newDesktopProviderModel(t, p)
	response := runProviderDesktopV2(t, &m, "provider.browse", map[string]any{"provider": "catalog"})
	browse := response.Browse
	if browse == nil || !reflect.DeepEqual(browse.Modes, []string{"genres"}) || browse.DefaultMode != "genres" || browse.ArtistLabel != "Author" || browse.AlbumLabel != "Book" || len(browse.Entries) != 2 || !browse.Entries[0].OpenInPlaylist || browse.Entries[0].AfterSection != "Library" {
		t.Fatalf("browse = %+v", browse)
	}
	if !browse.Related || !browse.TrackArtist || !browse.Refreshable || !browse.AlbumSortSavable || !browse.CatalogSearch || browse.Subscriptions || browse.Shows {
		t.Fatalf("capabilities = %+v", browse)
	}
	response = runProviderDesktopV2(t, &m, "provider.genres", map[string]any{"provider": "catalog", "entry": "tags", "offset": 1, "limit": 1})
	if response.Total != 2 || len(response.Genres) != 1 || response.Genres[0].ID != "rock" || response.GenreLabel != "Tags" || !response.Favoritable || !response.Searchable {
		t.Fatalf("genres = %+v", response)
	}
	response = runProviderDesktopV2(t, &m, "provider.genres", map[string]any{"provider": "catalog", "entry": "tags", "query": "ambient"})
	if len(response.Genres) != 1 || response.Genres[0].ID != "ambient" {
		t.Fatalf("genre search = %+v", response)
	}
	response = runProviderDesktopV2(t, &m, "provider.genre_tracks", map[string]any{"provider": "catalog", "entry": "tags", "genre": "jazz", "sort": "popular"})
	if response.Total != 1 || response.Tracks[0].ProviderMeta["podcast.guid"] != "one" || response.Listening["test:one"].Position != 17 || p.route.lastSort != "popular" || p.route.lastGenre != "jazz" {
		t.Fatalf("genre tracks = %+v", response)
	}
	response = runProviderDesktopV2(t, &m, "provider.genre.favorite", map[string]any{"provider": "catalog", "entry": "tags", "genre": "rock"})
	if response.Favorite == nil || !*response.Favorite || len(p.styles) != 0 || len(p.route.styles) != 1 {
		t.Fatalf("routed favorite = %+v", response)
	}
	for _, params := range []map[string]any{{"provider": "catalog", "entry": "missing"}, {"provider": "catalog", "entry": "tags", "genre": "jazz", "sort": "missing"}} {
		op := "provider.genres"
		if params["genre"] != nil {
			op = "provider.genre_tracks"
		}
		job := runProviderDesktopJob(t, &m, op, params)
		if job.State != ipc.JobFailed {
			t.Fatalf("invalid route/sort succeeded: %+v", job)
		}
	}
}

func TestProviderDesktopRefreshSortAndCatalog(t *testing.T) {
	p := &desktopBrowseProvider{}
	p.tracks = []playlist.Track{{Path: "test:refreshed"}}
	m := newDesktopProviderModel(t, p)
	response := runProviderDesktopV2(t, &m, "provider.refresh", map[string]any{"provider": "catalog", "playlist": "stable"})
	if response.Playlist != "stable" || len(response.Tracks) != 1 || p.refreshes != 1 || p.listRequests != 0 {
		t.Fatalf("stable refresh=%+v provider=%+v", response, p)
	}
	response = runProviderDesktopV2(t, &m, "provider.refresh", map[string]any{"provider": "catalog", "playlist": "positional:1"})
	if len(response.Playlists) != 1 || p.refreshes != 2 || len(p.trackRequests) != 1 {
		t.Fatalf("unstable refresh=%+v provider=%+v", response, p)
	}
	response = runProviderDesktopV2(t, &m, "provider.album_sort", map[string]any{"provider": "catalog", "sort": "name"})
	if response.Browse.AlbumSort != "name" || p.albumSort != "name" {
		t.Fatalf("sort=%+v", response)
	}
	job := runProviderDesktopJob(t, &m, "provider.album_sort", map[string]any{"provider": "catalog", "sort": "invalid"})
	if job.State != ipc.JobFailed || p.albumSort != "name" {
		t.Fatalf("invalid sort=%+v", job)
	}
	for _, query := range []string{"jazz", ""} {
		response = runProviderDesktopV2(t, &m, "provider.catalog.search", map[string]any{"provider": "catalog", "query": query})
		if p.searchQuery != query || len(response.Playlists) != 1 {
			t.Fatalf("catalog query=%s response=%+v", p.searchQuery, response)
		}
	}
}

func TestProviderDesktopLocationRequiresExplicitAnswer(t *testing.T) {
	for _, allowed := range []bool{false, true} {
		t.Run(map[bool]string{false: "decline", true: "allow"}[allowed], func(t *testing.T) {
			p := &locationProvider{asking: true, detected: "Norway"}
			m := newDesktopProviderModel(t, p)
			response := runProviderDesktopV2(t, &m, "provider.location", map[string]any{"provider": "catalog"})
			if response.Location == nil || !response.Location.Needed || response.Location.ID != testConsentID || p.consent != nil {
				t.Fatalf("location read=%+v", response)
			}
			job := runProviderDesktopJob(t, &m, "provider.location.consent", map[string]any{"provider": "catalog"})
			if job.State != ipc.JobFailed || p.consent != nil {
				t.Fatal("missing choice supplied consent")
			}
			response = runProviderDesktopV2(t, &m, "provider.location.consent", map[string]any{"provider": "catalog", "allowed": allowed})
			if p.consent == nil || *p.consent != allowed || response.Location.Needed || (allowed && response.Place != "Norway") {
				t.Fatalf("consent=%+v", response)
			}
		})
	}
	p := &locationProvider{asking: true}
	m := newDesktopProviderModel(t, p)
	for _, op := range []string{"provider.tracks", "provider.load"} {
		response := runV2(t, &m, op, ipc.Request{Provider: "catalog", Playlist: testConsentID})
		if response.OK || !strings.Contains(response.Error, "consent") || p.consent != nil {
			t.Fatalf("consent row %s=%+v", op, response)
		}
	}
}

func TestProviderDesktopTrackArtistRelatedAndListening(t *testing.T) {
	p := &desktopBrowseProvider{listening: map[string]provider.PlaybackState{"test:seed": {Played: true}, "test:progress": {Position: 5 * time.Second}}}
	m := newDesktopProviderModel(t, p)
	track := ipc.TrackInfo{Path: "test:seed", ProviderMeta: map[string]string{"provider.id": "seed"}}
	response := runProviderDesktopV2(t, &m, "provider.track_artist", map[string]any{"track": track})
	if response.Provider != "catalog" || response.Artist == nil || response.Artist.ID != "author" || len(response.Albums) != 1 || !response.Albums[0].Restricted {
		t.Fatalf("track artist=%+v", response)
	}
	response = runProviderDesktopV2(t, &m, "provider.related", map[string]any{"track": track})
	if response.Provider != "catalog" || len(response.Tracks) != 1 || m.playlist.Len() != 0 {
		t.Fatalf("related read=%+v", response)
	}
	response = runProviderDesktopV2(t, &m, "provider.related", map[string]any{"track": track, "mode": "next"})
	if m.playlist.Len() != 1 || m.playlist.QueueLen() != 1 || response.Tracks[0].ProviderMeta["provider.id"] != "related" {
		t.Fatalf("related queue=%+v", response)
	}
	response = runProviderDesktopV2(t, &m, "provider.playback_state", map[string]any{"tracks": []ipc.TrackInfo{track, {Path: "test:progress"}, {Path: "test:unknown"}}})
	if len(response.Listening) != 2 || !response.Listening["test:seed"].Played || response.Listening["test:progress"].Position != 5 {
		t.Fatalf("listening=%+v", response.Listening)
	}
	job := runProviderDesktopJob(t, &m, "provider.track_artist", map[string]any{"track": ipc.TrackInfo{Path: "unknown:track"}})
	if job.State != ipc.JobFailed || job.Error.Code != ipc.V2ErrorCodeUnavailable {
		t.Fatalf("unrecognized artist=%+v", job)
	}
}

func TestProviderDesktopGenreActionsUseAllTracks(t *testing.T) {
	for _, mode := range []string{"read", "load", "play", "append", "next"} {
		t.Run(mode, func(t *testing.T) {
			p := &desktopBrowseProvider{}
			p.route.tracks = []playlist.Track{{Path: "test:one"}, {Path: "test:two"}, {Path: "test:three"}}
			m := newDesktopProviderModel(t, p)
			m.playlist.Add(playlist.Track{Path: "previous"})
			response := runProviderDesktopV2(t, &m, "provider.genre_tracks", map[string]any{"provider": "catalog", "entry": "tags", "genre": "jazz", "mode": mode, "limit": 1})
			wantLen := 4
			if mode == "read" {
				wantLen = 1
			}
			if mode == "load" || mode == "play" {
				wantLen = 3
			}
			if response.Total != 3 || len(response.Tracks) != 1 || m.playlist.Len() != wantLen {
				t.Fatalf("mode %s response=%+v queue=%+v", mode, response, m.playlist.Tracks())
			}
			if mode == "next" && m.playlist.QueueLen() != 3 {
				t.Fatal("category queue was truncated to response page")
			}
		})
	}
}

type desktopShowMetadataProvider struct{ desktopBrowseProvider }

func (*desktopShowMetadataProvider) AlbumTracks(string) ([]playlist.Track, error) { return nil, nil }
func (*desktopShowMetadataProvider) IsShowID(id string) bool                      { return id == "stable" || id == "book" }
func (*desktopShowMetadataProvider) Playlists() ([]playlist.PlaylistInfo, error) {
	return []playlist.PlaylistInfo{{ID: "stable", Name: "A show"}, {ID: "category", Name: "A category"}}, nil
}

func TestProviderDesktopShowMetadataDoesNotMarkCategories(t *testing.T) {
	p := &desktopShowMetadataProvider{}
	items, err := ipcProviderPlaylistInfos(provider.Entry{Key: "podcasts", Provider: p})
	if err != nil || len(items) != 2 || !items[0].Show || items[1].Show {
		t.Fatalf("playlist show metadata=%+v err=%v", items, err)
	}
	albums := ipcProviderAlbumInfos(p, []provider.AlbumInfo{{ID: "book", Restricted: true}, {ID: "category"}})
	if !albums[0].Show || !albums[0].Restricted || albums[1].Show {
		t.Fatalf("album show metadata=%+v", albums)
	}
}
