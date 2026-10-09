package model

import (
	"context"
	"fmt"
	"slices"
	"sort"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/bjarneo/cliamp/internal/fuzzy"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
)

// runIPCProviderCollection loads and filters the collection before the owner
// changes playback. Only the response is paged; result.tracks is complete.
func runIPCProviderCollection(ctx context.Context, result *ipcProviderDesktopResult, candidates []provider.Entry, favorite func(playlist.Track) bool) error {
	ctx = requestContext(ctx)
	if err := ctx.Err(); err != nil {
		return err
	}
	request := result.params
	if !slices.Contains([]string{"", "play", "append", "next", "replace"}, request.Mode) {
		return v2InvalidParamsError()
	}
	var tracks []playlist.Track
	var err error
	exactPlaylist := false
	switch request.Source {
	case "playlist":
		if err := ipcProviderPlayable(result.source, request.Playlist); err != nil {
			return err
		}
		tracks, exactPlaylist, err = ipcCollectionPlaylistTracks(ctx, result.source, request.Playlist)
		result.response.Playlist = request.Playlist
		if exactPlaylist {
			// A nonempty name marks an exact source playlist. Wrapper
			// expansion or filtering must not bind queue edits to that file.
			result.name = request.Playlist
		}
	case "album":
		if request.Album == "" {
			return v2InvalidParamsError()
		}
		if request.Track != nil {
			album := ipcTrackFromInfo(*request.Track)
			if !album.IsAlbum() || album.AlbumID() != request.Album {
				return v2InvalidParamsError()
			}
			result.album = &album
		}
		loader, ok := result.source.(provider.AlbumTrackLoader)
		if !ok {
			return v2UnavailableError()
		}
		tracks, err = ipcSubscriptionAlbumTracks(ctx, loader, request.Album)
	case "genre":
		if request.Genre == "" {
			return v2InvalidParamsError()
		}
		browser, browseErr := ipcProviderGenreBrowser(result.source, request.Entry)
		if browseErr != nil {
			return browseErr
		}
		sorts := browser.GenreSortTypes()
		selectedSort := request.Sort
		if selectedSort == "" && len(sorts) > 0 {
			selectedSort = sorts[0].ID
		}
		if len(sorts) > 0 && !slices.ContainsFunc(sorts, func(item provider.SortType) bool { return item.ID == selectedSort }) {
			return v2InvalidParamsError()
		}
		tracks, err = browser.GenreTracks(request.Genre, selectedSort)
	case "search":
		if strings.TrimSpace(request.Query) == "" {
			return v2InvalidParamsError()
		}
		limit := request.Limit
		if limit == 0 {
			limit = 100
		}
		// Searcher exposes one bounded search, with no continuation API.
		// Preserve that provider contract instead of inventing pagination.
		tracks, err = ipcSearchProvider(ctx, result.source, request.Query, limit)
	case "related":
		if request.Track == nil || request.Track.Path == "" {
			return v2InvalidParamsError()
		}
		seed := ipcTrackFromInfo(*request.Track)
		limit := request.Limit
		if limit == 0 {
			limit = 25
		}
		found := false
		for _, entry := range candidates {
			relater, ok := entry.Provider.(provider.Relater)
			if !ok || !relater.CanRelate(seed) {
				continue
			}
			lookupCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
			tracks, err = relater.RelatedTracks(lookupCtx, seed, limit)
			cancel()
			result.source, result.response.Provider = entry.Provider, entry.Key
			found = true
			break
		}
		if !found {
			return v2UnavailableError()
		}
	default:
		return v2InvalidParamsError()
	}
	if err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	tracks = ipcFilterCollection(tracks, request.Filter)
	if request.Source == "search" && request.SelectedPath != "" {
		selected := slices.IndexFunc(tracks, func(track playlist.Track) bool { return track.Path == request.SelectedPath })
		if selected < 0 {
			err := v2NotFoundError()
			err.Detail = "selected track is not in the filtered collection"
			return err
		}
		if tracks[selected].IsAlbum() {
			// Search rows can represent albums. Choosing one expands only
			// that album, just as the TUI does, rather than treating its
			// placeholder URI as audio or expanding unrelated search hits.
			album := tracks[selected]
			if album.AlbumID() == "" {
				return v2InvalidParamsError()
			}
			loader, ok := result.source.(provider.AlbumTrackLoader)
			if !ok {
				return v2UnavailableError()
			}
			tracks, err = ipcSubscriptionAlbumTracks(ctx, loader, album.AlbumID())
			if err != nil {
				return err
			}
			result.album = &album
		}
	}
	// Album containers are navigation entries, never playable queue items.
	// Bulk search actions operate on songs; an album must be chosen explicitly.
	playable := ipcPlayableCollectionTracks(tracks)
	if len(playable) != len(tracks) {
		result.name = ""
	}
	tracks = playable
	if result.album != nil {
		if len(tracks) == 0 {
			err := v2NotFoundError()
			err.Detail = "that album has no tracks available here"
			return err
		}
		request.SelectedPath = ""
	}
	index := 0
	if request.Mode == "" || request.Mode == "play" {
		if request.SelectedPath != "" {
			index = slices.IndexFunc(tracks, func(track playlist.Track) bool { return track.Path == request.SelectedPath })
		}
		if len(tracks) == 0 || index < 0 {
			err := v2NotFoundError()
			err.Detail = "selected track is not in the filtered collection"
			return err
		}
	}
	// ResumeTarget may query a provider, so resolve it in the worker. The
	// response records the selected collection index and any resume position.
	if request.Source == "playlist" && request.Filter == "" && request.Mode != "append" && request.Mode != "next" {
		_, paged := result.source.(provider.TrackPager)
		if resume, ok := result.source.(provider.ResumeTarget); ok && !paged {
			resumeIndex, offset := resume.ResumeTarget(request.Playlist, tracks)
			if offset > 0 && resumeIndex >= 0 && resumeIndex < len(tracks) && (request.SelectedPath == "" || request.SelectedPath == tracks[resumeIndex].Path) {
				index, result.response.Position = resumeIndex, offset.Seconds()
			}
		}
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	result.tracks, result.response.Index = tracks, index
	page, total := ipcPage(tracks, request.Offset, request.Limit, 200)
	result.response.Tracks = ipcTrackInfos(page, favorite)
	result.response.Total = total
	result.response.Listening = ipcProviderListening(candidates, page)
	return nil
}

func ipcPlayableCollectionTracks(tracks []playlist.Track) []playlist.Track {
	firstAlbum := slices.IndexFunc(tracks, playlist.Track.IsAlbum)
	if firstAlbum < 0 {
		return tracks
	}
	playable := make([]playlist.Track, 0, len(tracks)-1)
	playable = append(playable, tracks[:firstAlbum]...)
	for _, track := range tracks[firstAlbum+1:] {
		if !track.IsAlbum() {
			playable = append(playable, track)
		}
	}
	return playable
}

// ipcCollectionPlaylistTracks consumes the entire provider paging contract,
// rejecting invalid continuations instead of hanging or committing a prefix.
func ipcCollectionPlaylistTracks(ctx context.Context, source playlist.Provider, id string) ([]playlist.Track, bool, error) {
	if pager, ok := source.(provider.TrackPager); ok {
		var tracks []playlist.Track
		for offset := 0; ; {
			if err := ctx.Err(); err != nil {
				return nil, false, err
			}
			var page []playlist.Track
			var next int
			var err error
			if contextual, ok := pager.(interface {
				TracksPageContext(context.Context, string, int) ([]playlist.Track, int, error)
			}); ok {
				page, next, err = contextual.TracksPageContext(ctx, id, offset)
			} else {
				page, next, err = pager.TracksPage(id, offset)
			}
			if contextErr := ctx.Err(); contextErr != nil {
				return nil, false, contextErr
			}
			if err != nil {
				return nil, false, err
			}
			tracks = append(tracks, page...)
			if next == 0 {
				return tracks, true, nil
			}
			if next <= offset {
				return nil, false, fmt.Errorf("playlist paging returned invalid continuation %d after %d", next, offset)
			}
			offset = next
		}
	}
	var tracks []playlist.Track
	var err error
	if contextual, ok := source.(interface {
		TracksContext(context.Context, string) ([]playlist.Track, error)
	}); ok {
		tracks, err = contextual.TracksContext(ctx, id)
	} else {
		tracks, err = source.Tracks(id)
	}
	if contextErr := ctx.Err(); contextErr != nil {
		return nil, false, contextErr
	}
	if err != nil {
		return nil, false, err
	}
	tracks, expanded := resolveWrapperURLs(tracks)
	if contextErr := ctx.Err(); contextErr != nil {
		return nil, false, contextErr
	}
	return tracks, !expanded, nil
}

// ipcFilterCollection follows the main playlist's fuzzy search ranking,
// including stable source order for equally ranked matches.
func ipcFilterCollection(tracks []playlist.Track, query string) []playlist.Track {
	if query == "" {
		return tracks
	}
	type match struct {
		track playlist.Track
		score int
	}
	var matches []match
	for _, track := range tracks {
		if score, ok := fuzzy.Match(query, track.DisplayName()); ok {
			matches = append(matches, match{track: track, score: score})
		}
	}
	sort.SliceStable(matches, func(a, b int) bool { return matches[a].score > matches[b].score })
	filtered := make([]playlist.Track, len(matches))
	for i, match := range matches {
		filtered[i] = match.track
	}
	return filtered
}

// applyIPCProviderCollection runs only in the model owner, after cancellation
// and revision checks. Every action uses the full filtered result.
func (m *Model) applyIPCProviderCollection(result ipcProviderDesktopResult) tea.Cmd {
	request, tracks := result.params, result.tracks
	if result.album != nil && request.Mode != "replace" {
		switch request.Mode {
		case "append":
			return m.appendAlbum(*result.album, tracks)
		case "next":
			return m.queueAlbumNext(*result.album, tracks)
		default:
			return m.playAlbumImmediate(*result.album, tracks)
		}
	}
	if request.Mode == "append" || request.Mode == "next" {
		if len(tracks) == 0 {
			return nil
		}
		start := m.appendTracks(tracks...)
		if request.Mode == "next" {
			for i := range tracks {
				m.playlist.Queue(start + i)
			}
		}
		m.normalizeQueueOverlay()
		m.status.Showf(statusTTLDefault, "Added %d tracks", len(tracks))
		return m.rearmStalePreload()
	}
	m.retireTracksPaging()
	m.replacePlayerPlaylist(tracks)
	m.activeProviderPlaylistID = ""
	if request.Source == "playlist" && request.Filter == "" && result.name == request.Playlist {
		m.setLoadedLocalPlaylist(result.source.Name(), request.Playlist)
		if m.isActiveProvider(result.source.Name()) {
			m.activeProviderPlaylistID = request.Playlist
		}
	}
	if m.loadedPlaylist == "" {
		id := request.Playlist
		switch request.Source {
		case "album":
			id = "album:" + request.Album
		case "genre":
			id = "genre:" + request.Genre
		case "search":
			id = "search:" + request.Query
		case "related":
			id = "related:" + request.Track.Path
		}
		m.playlistSource = result.response.Provider + ":" + id
	}
	m.applyTracksResume(tracksLoadedMsg{
		tracks: tracks, resumeIdx: result.response.Index,
		resumeOffset: time.Duration(result.response.Position * float64(time.Second)),
	})
	if request.Mode == "replace" {
		m.status.Successf(statusTTLDefault, "Replaced queue with %d tracks", len(tracks))
		return nil
	}
	m.playlist.SetIndex(result.response.Index)
	m.plCursor = result.response.Index
	m.adjustScroll()
	return m.playCurrentTrack()
}
