package model

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
)

type ipcProviderDesktopParams struct {
	ipc.Request
	Entry        string `json:"entry"`
	Genre        string `json:"genre"`
	Mode         string `json:"mode"`
	Allowed      *bool  `json:"allowed"`
	Source       string `json:"source"`
	Filter       string `json:"filter"`
	SelectedPath string `json:"selected_path"`
}

type ipcProviderDesktopResult struct {
	jobs     *ipc.JobStore
	jobID    string
	op       string
	params   ipcProviderDesktopParams
	response ipc.ProviderDesktopResponse
	tracks   []playlist.Track
	album    *playlist.Track
	source   playlist.Provider
	name     string
	err      error
}

// handleV2ProviderDesktop captures owner state before any provider work. Slow
// operations return a typed message; only the owner commits queue changes.
func (m *Model) handleV2ProviderDesktop(ctx context.Context, msg V2RequestMsg) tea.Cmd {
	var params ipcProviderDesktopParams
	if err := json.Unmarshal(msg.Request.Params, &params); err != nil || params.Offset < 0 || params.Limit < 0 || params.Limit > 200 {
		m.failV2Job(msg.Jobs, msg.JobID, v2InvalidParamsError())
		return nil
	}
	op := strings.ToLower(strings.TrimSpace(msg.Request.Operation))
	if params.Revision != 0 && providerDesktopMutates(op, params.Mode) && params.Revision != m.playlist.Revision() {
		m.failV2Job(msg.Jobs, msg.JobID, v2ConflictError())
		return nil
	}
	var entry provider.Entry
	var ok bool
	if params.Provider != "" {
		entry, ok = m.ipcProvider(params.Provider)
		if !ok || entry.Provider == nil {
			m.failV2Job(msg.Jobs, msg.JobID, v2NotFoundError())
			return nil
		}
	} else if op != "provider.related" && op != "provider.track_artist" && op != "provider.playback_state" && !(op == "provider.collection" && params.Source == "related") {
		m.failV2Job(msg.Jobs, msg.JobID, v2InvalidParamsError())
		return nil
	}
	candidates := append([]provider.Entry(nil), m.providers...)
	candidates = slices.DeleteFunc(candidates, func(entry provider.Entry) bool { return entry.Provider == nil })
	if entry.Provider != nil {
		candidates = []provider.Entry{entry}
	} else if m.provider != nil {
		// Match the TUI's preference for the active provider when several
		// services recognize a track.
		slices.SortStableFunc(candidates, func(a, b provider.Entry) int {
			activeA, activeB := a.Provider.Name() == m.provider.Name(), b.Provider.Name() == m.provider.Name()
			if activeA && !activeB {
				return -1
			}
			if activeB && !activeA {
				return 1
			}
			return 0
		})
	}
	favorite := m.trackFavoriteLookup(false)
	return func() tea.Msg {
		result := ipcProviderDesktopResult{jobs: msg.Jobs, jobID: msg.JobID, op: op, params: params, source: entry.Provider}
		result.response = ipc.ProviderDesktopResponse{Response: ipc.Response{OK: true}, Provider: entry.Key}
		if err := ctx.Err(); err != nil {
			result.err = err
			return result
		}
		result.err = runIPCProviderDesktop(ctx, &result, candidates, favorite)
		if err := ctx.Err(); err != nil {
			result.err = err
		}
		return result
	}
}

func providerDesktopMutates(op, mode string) bool {
	return op == "provider.collection" || op == "provider.subscription.load" || op == "provider.subscriptions.newest" || ((op == "provider.related" || op == "provider.genre_tracks") && mode != "" && mode != "read")
}

func runIPCProviderDesktop(ctx context.Context, result *ipcProviderDesktopResult, candidates []provider.Entry, favorite func(playlist.Track) bool) error {
	p, request, response := result.source, result.params, &result.response
	setTracks := func(tracks []playlist.Track) {
		page, total := ipcPage(tracks, request.Offset, request.Limit, 200)
		response.Tracks = ipcTrackInfos(page, favorite)
		response.Total = total
		response.Listening = ipcProviderListening(candidates, page)
	}
	switch result.op {
	case "provider.collection":
		return runIPCProviderCollection(ctx, result, candidates, favorite)
	case "provider.browse":
		response.Browse = ipcProviderBrowse(p)
	case "provider.refresh":
		stable, inPlace := p.(playlist.RefreshablePlaylist)
		inPlace = inPlace && request.Playlist != "" && stable.CanRefreshPlaylist(request.Playlist)
		if refresher, ok := p.(playlist.Refresher); ok {
			refresher.Refresh()
		}
		if inPlace {
			tracks, err := p.Tracks(request.Playlist)
			if err != nil {
				return err
			}
			setTracks(tracks)
			response.Playlist = request.Playlist
		} else {
			items, err := ipcProviderPlaylistInfos(provider.Entry{Key: response.Provider, Provider: p})
			if err != nil {
				return err
			}
			response.Playlists, response.Total = ipcPage(items, request.Offset, request.Limit, 200)
		}
	case "provider.genres", "provider.genre_tracks", "provider.genre.favorite":
		browser, err := ipcProviderGenreBrowser(p, request.Entry)
		if err != nil {
			return err
		}
		response.GenreLabel = "Genres"
		if labeler, ok := browser.(provider.GenreLabeler); ok && labeler.GenreLabel() != "" {
			response.GenreLabel = labeler.GenreLabel()
		}
		_, response.Favoritable = browser.(provider.GenreFavoriteToggler)
		searcher, searchable := browser.(provider.GenreSearcher)
		response.Searchable = searchable
		response.Sorts = ipcProviderSorts(browser.GenreSortTypes())
		switch result.op {
		case "provider.genres":
			var genres []provider.GenreInfo
			if request.Query != "" {
				if !searchable {
					return v2UnavailableError()
				}
				searchCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
				defer cancel()
				limit := request.Limit
				if limit == 0 {
					limit = 100
				}
				genres, err = searcher.SearchGenres(searchCtx, request.Query, min(200, request.Offset+limit))
			} else {
				genres, err = browser.Genres()
			}
			if err != nil {
				return err
			}
			page, total := ipcPage(genres, request.Offset, request.Limit, 200)
			response.Total = total
			for _, genre := range page {
				response.Genres = append(response.Genres, ipc.ProviderGenreInfo{ID: genre.ID, Name: genre.Name, Group: genre.Group, Favorite: genre.Favorite})
			}
		case "provider.genre_tracks":
			if request.Genre == "" {
				return v2InvalidParamsError()
			}
			if !slices.Contains([]string{"", "read", "load", "play", "append", "next"}, request.Mode) {
				return v2InvalidParamsError()
			}
			sort := request.Sort
			if sort == "" && len(response.Sorts) > 0 {
				sort = response.Sorts[0].ID
			}
			if len(response.Sorts) > 0 && !slices.ContainsFunc(response.Sorts, func(s ipc.SortInfo) bool { return s.ID == sort }) {
				return v2InvalidParamsError()
			}
			tracks, err := browser.GenreTracks(request.Genre, sort)
			if err != nil {
				return err
			}
			result.tracks, result.name = tracks, request.Genre
			setTracks(tracks)
		case "provider.genre.favorite":
			if request.Genre == "" {
				return v2InvalidParamsError()
			}
			toggler, ok := browser.(provider.GenreFavoriteToggler)
			if !ok {
				return v2UnavailableError()
			}
			value, err := toggler.ToggleGenreFavorite(request.Genre)
			if err != nil {
				return err
			}
			response.Favorite = &value
		}
	case "provider.location", "provider.location.consent":
		consenter, ok := p.(provider.LocationConsenter)
		if !ok {
			return v2UnavailableError()
		}
		if result.op == "provider.location.consent" {
			if request.Allowed == nil {
				return v2InvalidParamsError()
			}
			place, err := consenter.SetLocationConsent(*request.Allowed)
			if err != nil {
				return err
			}
			response.Place = place
			items, err := ipcProviderPlaylistInfos(provider.Entry{Key: response.Provider, Provider: p})
			if err != nil {
				return err
			}
			response.Playlists, response.Total = ipcPage(items, request.Offset, request.Limit, 200)
		}
		response.Location = ipcProviderLocation(consenter)
	case "provider.album_sort":
		browser, browsable := p.(provider.AlbumBrowser)
		saver, savable := p.(provider.AlbumSortSaver)
		if !browsable || !savable {
			return v2UnavailableError()
		}
		sorts := browser.AlbumSortTypes()
		if !slices.ContainsFunc(sorts, func(sort provider.SortType) bool { return sort.ID == request.Sort }) {
			return v2InvalidParamsError()
		}
		if err := saver.SaveAlbumSort(request.Sort); err != nil {
			return err
		}
		response.Sorts = ipcProviderSorts(sorts)
		response.Browse = ipcProviderBrowse(p)
	case "provider.catalog.search":
		searcher, ok := p.(provider.CatalogSearcher)
		if !ok {
			return v2UnavailableError()
		}
		if request.Query == "" {
			searcher.ClearSearch()
		} else if _, err := searcher.SearchCatalog(request.Query); err != nil {
			return err
		}
		items, err := ipcProviderPlaylistInfos(provider.Entry{Key: response.Provider, Provider: p})
		if err != nil {
			return err
		}
		response.Playlists, response.Total = ipcPage(items, request.Offset, request.Limit, 200)
	case "provider.subscriptions":
		shows, err := ipcSubscriptionInfos(p)
		if err != nil {
			return err
		}
		page, total := ipcPage(shows, request.Offset, request.Limit, 200)
		response.Total = total
		for _, show := range page {
			response.Subscriptions = append(response.Subscriptions, ipc.ProviderSubscriptionInfo{ID: show.ID, Name: show.Name, Author: show.Author})
		}
	case "provider.subscription.load", "provider.subscriptions.newest":
		if request.Mode != "" && !slices.Contains([]string{"append", "play", "next", "newest", "newest_next"}, request.Mode) {
			return v2InvalidParamsError()
		}
		var err error
		if result.op == "provider.subscription.load" {
			result.tracks, result.name, err = ipcSubscriptionTracks(ctx, p, request.Playlist, request.Mode == "newest" || request.Mode == "newest_next")
		} else {
			if request.Mode == "newest" || request.Mode == "newest_next" {
				return v2InvalidParamsError()
			}
			result.tracks, response.Failed, err = ipcNewestSubscriptions(ctx, p)
			result.name = "subscriptions"
		}
		if err != nil {
			return err
		}
		setTracks(result.tracks)
	case "provider.related", "provider.track_artist":
		if request.Track == nil || request.Track.Path == "" {
			return v2InvalidParamsError()
		}
		seed := ipcTrackFromInfo(*request.Track)
		for _, entry := range candidates {
			if result.op == "provider.related" {
				if !slices.Contains([]string{"", "read", "append", "next", "play"}, request.Mode) {
					return v2InvalidParamsError()
				}
				relater, ok := entry.Provider.(provider.Relater)
				if !ok || !relater.CanRelate(seed) {
					continue
				}
				limit := request.Limit
				if limit == 0 {
					limit = 25
				}
				lookupCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
				defer cancel()
				tracks, err := relater.RelatedTracks(lookupCtx, seed, limit)
				if err != nil {
					return err
				}
				result.tracks, result.name, result.source = tracks, "related songs", entry.Provider
				response.Provider = entry.Key
				setTracks(tracks)
				return nil
			}
			resolver, ok := entry.Provider.(provider.TrackArtistResolver)
			if !ok {
				continue
			}
			artist, recognized := resolver.ArtistForTrack(seed)
			browser, browsable := entry.Provider.(provider.ArtistBrowser)
			if !recognized || !browsable {
				continue
			}
			albums, err := browser.ArtistAlbums(artist.ID)
			if err != nil {
				return err
			}
			response.Provider = entry.Key
			response.Artist = &ipc.ArtistInfo{ID: artist.ID, Name: artist.Name, AlbumCount: artist.AlbumCount}
			page, total := ipcPage(albums, request.Offset, request.Limit, 200)
			response.Albums, response.Total = ipcProviderAlbumInfos(entry.Provider, page), total
			return nil
		}
		return v2UnavailableError()
	case "provider.playback_state":
		if len(request.Tracks) > 200 {
			return v2InvalidParamsError()
		}
		tracks := make([]playlist.Track, len(request.Tracks))
		for i, info := range request.Tracks {
			tracks[i] = ipcTrackFromInfo(info)
		}
		response.Listening = ipcProviderListening(candidates, tracks)
	default:
		return v2UnavailableError()
	}
	return nil
}

func (m *Model) handleIPCProviderDesktopResult(result ipcProviderDesktopResult) tea.Cmd {
	ctx, ok := result.jobs.Context(result.jobID)
	if !ok || ctx.Err() != nil {
		return nil
	}
	if result.err != nil {
		var protocolErr *ipc.V2Error
		if !errors.As(result.err, &protocolErr) {
			protocolErr = v2InternalError()
			protocolErr.Detail = result.err.Error()
		}
		m.failV2Job(result.jobs, result.jobID, protocolErr)
		return nil
	}
	var cmd tea.Cmd
	if providerDesktopMutates(result.op, result.params.Mode) {
		if result.params.Revision != 0 && result.params.Revision != m.playlist.Revision() {
			m.failV2Job(result.jobs, result.jobID, v2ConflictError())
			return nil
		}
		if result.op == "provider.collection" {
			cmd = m.applyIPCProviderCollection(result)
		} else if result.op == "provider.genre_tracks" && (result.params.Mode == "load" || result.params.Mode == "play") {
			m.retireTracksPaging()
			m.replacePlayerPlaylist(result.tracks)
			m.clearLoadedPlaylist()
			m.playlistSource = result.response.Provider + ":" + result.params.Genre
			m.setHeaderStateFromTracks(result.tracks)
			m.plCursor = 0
			if result.params.Mode == "play" && len(result.tracks) > 0 {
				m.playlist.SetIndex(0)
				cmd = m.playCurrentTrack()
			}
		} else {
			mode := subsLoadAppend
			switch result.params.Mode {
			case "play":
				mode = subsLoadPlay
			case "next":
				mode = subsLoadQueue
			case "newest_next":
				mode = subsLoadLatest
			}
			cmd = m.appendSubscriptionTracks(result.tracks, mode, result.name)
		}
	}
	m.completeV2Job(result.jobs, result.jobID, result.response)
	return cmd
}

func ipcProviderBrowse(p playlist.Provider) *ipc.ProviderBrowseInfo {
	view := Model{}
	view.navBrowser.prov = p
	labels := view.navLabels()
	info := &ipc.ProviderBrowseInfo{Entries: []ipc.ProviderBrowseEntry{}, Modes: []string{}, ArtistLabel: labels.artist, AlbumLabel: labels.album, GenreLabel: labels.genre, Refreshable: true}
	for _, mode := range view.navMenuItems() {
		info.Modes = append(info.Modes, ipcBrowseMode(mode.mode))
	}
	if preferred, ok := p.(provider.DefaultBrowseModeProvider); ok {
		info.DefaultMode = ipcBrowseMode(preferred.DefaultBrowseMode())
	}
	if entries, ok := p.(provider.BrowseEntryProvider); ok {
		seen := map[string]bool{}
		for _, entry := range entries.BrowseEntries() {
			mode := ipcBrowseMode(entry.Mode)
			if entry.ID == "" || entry.Name == "" || mode == "" || seen[entry.ID] {
				continue
			}
			seen[entry.ID] = true
			info.Entries = append(info.Entries, ipc.ProviderBrowseEntry{ID: entry.ID, Name: entry.Name, Section: entry.Section, Mode: mode, AfterID: entry.AfterID, AfterSection: entry.AfterSection, OpenInPlaylist: entry.OpenInPlaylist})
		}
	}
	_, info.Subscriptions = p.(provider.SubscriptionLister)
	_, info.Shows = p.(provider.ShowLister)
	_, info.Related = p.(provider.Relater)
	_, artistResolver := p.(provider.TrackArtistResolver)
	_, artistBrowser := p.(provider.ArtistBrowser)
	info.TrackArtist = artistResolver && artistBrowser
	_, info.CatalogSearch = p.(provider.CatalogSearcher)
	_, info.AlbumSortSavable = p.(provider.AlbumSortSaver)
	_, info.AlbumFavorite = p.(provider.FavoriteToggler)
	if browser, ok := p.(provider.AlbumBrowser); ok {
		info.AlbumSort = browser.DefaultAlbumSort()
		info.AlbumSorts = ipcProviderSorts(browser.AlbumSortTypes())
	}
	if consenter, ok := p.(provider.LocationConsenter); ok {
		info.Location = ipcProviderLocation(consenter)
	}
	return info
}

func ipcBrowseMode(mode provider.BrowseMode) string {
	switch mode {
	case provider.BrowseAlbums:
		return "albums"
	case provider.BrowseArtists:
		return "artists"
	case provider.BrowseArtistAlbums:
		return "artist_albums"
	case provider.BrowseGenres:
		return "genres"
	}
	return ""
}

func ipcProviderLocation(consenter provider.LocationConsenter) *ipc.ProviderLocationInfo {
	return &ipc.ProviderLocationInfo{Needed: consenter.NeedsLocationConsent(), ID: consenter.LocationConsentID(), Prompt: consenter.LocationPrompt()}
}

func ipcProviderGenreBrowser(p playlist.Provider, entryID string) (provider.GenreBrowser, error) {
	if entryID != "" {
		entry, ok := providerBrowseEntryForID(p, entryID)
		if !ok || entry.Mode != provider.BrowseGenres {
			return nil, v2NotFoundError()
		}
		if router, ok := p.(provider.GenreBrowseRouter); ok {
			if browser := router.GenreBrowserFor(entryID); browser != nil {
				return browser, nil
			}
			return nil, v2UnavailableError()
		}
	}
	if browser, ok := p.(provider.GenreBrowser); ok {
		return browser, nil
	}
	return nil, v2UnavailableError()
}

func ipcProviderSorts(sorts []provider.SortType) []ipc.SortInfo {
	items := make([]ipc.SortInfo, len(sorts))
	for i, sort := range sorts {
		items[i] = ipc.SortInfo{ID: sort.ID, Label: sort.Label}
	}
	return items
}

func ipcProviderListening(providers []provider.Entry, tracks []playlist.Track) map[string]ipc.ProviderListeningInfo {
	states := map[string]ipc.ProviderListeningInfo{}
	for _, track := range tracks {
		for _, entry := range providers {
			reporter, ok := entry.Provider.(provider.PlaybackStateReporter)
			if !ok {
				continue
			}
			if state, ok := reporter.PlaybackState(track); ok {
				states[track.Path] = ipc.ProviderListeningInfo{Played: state.Played, Position: state.Position.Seconds()}
				break
			}
		}
	}
	return states
}

// ipcProviderPlayable rejects UI-only rows before calling provider Tracks.
func ipcProviderPlayable(p playlist.Provider, id string) error {
	if consenter, ok := p.(provider.LocationConsenter); ok && consenter.LocationConsentID() != "" && id == consenter.LocationConsentID() {
		return fmt.Errorf("location consent required; read provider.location and answer provider.location.consent")
	}
	if _, browse := providerBrowseEntryForID(p, id); browse {
		return fmt.Errorf("browse entry is not a playable playlist; use provider.browse")
	}
	return nil
}
