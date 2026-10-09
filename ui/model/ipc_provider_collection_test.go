package model

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
)

type ipcCollectionProvider struct {
	plainProv
	albumContext bool
	searchLimit  int
	relatedLimit int
	genreSort    string
}

func (p *ipcCollectionProvider) AlbumTracks(string) ([]playlist.Track, error) {
	return p.tracks, nil
}
func (p *ipcCollectionProvider) AlbumTracksContext(ctx context.Context, _ string) ([]playlist.Track, error) {
	p.albumContext = true
	return p.tracks, ctx.Err()
}
func (*ipcCollectionProvider) Genres() ([]provider.GenreInfo, error) { return nil, nil }
func (*ipcCollectionProvider) GenreSortTypes() []provider.SortType {
	return []provider.SortType{{ID: "popular", Label: "Popular"}}
}
func (p *ipcCollectionProvider) GenreTracks(_, sort string) ([]playlist.Track, error) {
	p.genreSort = sort
	return p.tracks, nil
}
func (p *ipcCollectionProvider) SearchTracks(ctx context.Context, _ string, limit int) ([]playlist.Track, error) {
	p.searchLimit = limit
	return p.tracks[:min(limit, len(p.tracks))], ctx.Err()
}
func (*ipcCollectionProvider) CanRelate(track playlist.Track) bool { return track.Path == "seed" }
func (p *ipcCollectionProvider) RelatedTracks(ctx context.Context, _ playlist.Track, limit int) ([]playlist.Track, error) {
	p.relatedLimit = limit
	return p.tracks[:min(limit, len(p.tracks))], ctx.Err()
}

type ipcCollectionPager struct {
	plainProv
	offsets []int
	load    func(context.Context, int) ([]playlist.Track, int, error)
}

func (*ipcCollectionPager) Tracks(string) ([]playlist.Track, error) {
	return nil, errors.New("full Tracks must not bypass the paging contract")
}
func (*ipcCollectionPager) TracksPage(string, int) ([]playlist.Track, int, error) {
	return nil, 0, errors.New("contextual paging must be preferred")
}
func (p *ipcCollectionPager) TracksPageContext(ctx context.Context, _ string, offset int) ([]playlist.Track, int, error) {
	p.offsets = append(p.offsets, offset)
	return p.load(ctx, offset)
}

func collectionTracks(count int) []playlist.Track {
	tracks := make([]playlist.Track, count)
	for i := range tracks {
		tracks[i] = playlist.Track{Path: fmt.Sprintf("/collection/%04d.flac", i), Title: fmt.Sprintf("Song %04d", i)}
	}
	return tracks
}

func TestIPCProviderCollectionFullModes(t *testing.T) {
	tracks := collectionTracks(1237)
	for _, sourceKind := range []string{"playlist", "album", "genre"} {
		for _, mode := range []string{"", "play", "replace", "append", "next"} {
			t.Run(sourceKind+"/"+mode, func(t *testing.T) {
				p := &ipcCollectionProvider{plainProv: plainProv{tracks: tracks}}
				engine := &headlessEngine{}
				engine.playing = true
				original := playlist.Track{Path: "/original.flac", Title: "Original"}
				m := newHeadlessModel(t, engine, []provider.Entry{{Key: "collection", Provider: p}}, original)
				m.setPlaybackTrack(original)
				m.playlist.Queue(0)
				m.tracksPaging = true
				generation := m.requests.tracks
				response := runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
					"provider": "collection", "source": sourceKind, "playlist": "all", "album": "album", "genre": "genre",
					"mode": mode, "selected_path": tracks[1111].Path,
				})
				want := tracks
				if mode == "append" || mode == "next" {
					want = append([]playlist.Track{original}, tracks...)
				}
				if !reflect.DeepEqual(m.playlist.Tracks(), want) || response.Total != len(tracks) || len(response.Tracks) != 200 {
					t.Fatalf("collection=%d, total=%d, rows=%d; want %d/%d/200", m.playlist.Len(), response.Total, len(response.Tracks), len(want), len(tracks))
				}
				if sourceKind == "album" && !p.albumContext {
					t.Fatal("album collection did not use AlbumTracksContext")
				}
				if sourceKind == "genre" && p.genreSort != "popular" {
					t.Fatalf("genre sort = %q, want provider default", p.genreSort)
				}
				switch mode {
				case "", "play":
					if m.playlist.Index() != 1111 || response.Index != 1111 || m.playbackDetached || m.playlist.QueueLen() != 0 {
						t.Fatalf("selection=%d, response=%d, detached=%v, queued=%d; want 1111/1111/false/0", m.playlist.Index(), response.Index, m.playbackDetached, m.playlist.QueueLen())
					}
				case "replace":
					playing, _ := m.currentPlaybackTrack()
					if !m.playbackDetached || playing.Path != original.Path || !engine.playing || m.playlist.QueueLen() != 0 {
						t.Fatal("replace did not preserve detached playback while replacing both queues")
					}
				case "append":
					if m.playlist.Index() != 0 || !reflect.DeepEqual(m.playlist.QueueTracks(), []playlist.Track{original}) {
						t.Fatal("append changed current selection or existing play-next queue")
					}
				case "next":
					if m.playlist.Index() != 0 || !reflect.DeepEqual(m.playlist.QueueTracks(), want) {
						t.Fatal("next omitted collection tracks or changed the existing queue order")
					}
				}
				if mode != "append" && mode != "next" {
					if m.tracksPaging || m.requests.tracks == generation {
						t.Fatal("replacement retained an old incremental fetch")
					}
					before := m.playlist.Snapshot()
					updated, _ := m.Update(tracksLoadedMsg{gen: generation, providerName: p.Name(), offset: 300, tracks: collectionTracks(1)})
					m = updated.(Model)
					if !reflect.DeepEqual(m.playlist.Snapshot(), before) {
						t.Fatal("an old page appended to the replaced collection")
					}
				}
			})
		}
	}
}

func TestIPCProviderCollectionPagesWithoutCap(t *testing.T) {
	tracks := collectionTracks(1301)
	p := &ipcCollectionPager{load: func(ctx context.Context, offset int) ([]playlist.Track, int, error) {
		end := min(offset+300, len(tracks))
		next := end
		if end == len(tracks) {
			next = 0
		}
		return tracks[offset:end], next, ctx.Err()
	}}
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "paged", Provider: p}})
	response := runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
		"provider": "paged", "source": "playlist", "playlist": "all", "selected_path": tracks[1299].Path,
	})
	if !reflect.DeepEqual(p.offsets, []int{0, 300, 600, 900, 1200}) || !reflect.DeepEqual(m.playlist.Tracks(), tracks) || response.Total != 1301 || m.playlist.Index() != 1299 {
		t.Fatalf("pages=%v, tracks=%d, total=%d, index=%d; want all pages and selected row 1299", p.offsets, m.playlist.Len(), response.Total, m.playlist.Index())
	}
}

func TestIPCProviderCollectionPagingFailures(t *testing.T) {
	for _, kind := range []string{"repeated", "negative", "page error", "canceled"} {
		t.Run(kind, func(t *testing.T) {
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			p := &ipcCollectionPager{load: func(_ context.Context, offset int) ([]playlist.Track, int, error) {
				if offset == 0 {
					return collectionTracks(1), 1, nil
				}
				switch kind {
				case "repeated":
					return collectionTracks(1), 1, nil
				case "negative":
					return nil, -1, nil
				case "page error":
					return nil, 0, playlist.ErrListChanged
				default:
					cancel()
					return collectionTracks(1), 0, nil
				}
			}}
			tracks, exact, err := ipcCollectionPlaylistTracks(ctx, p, "all")
			if err == nil || len(tracks) != 0 || exact || !reflect.DeepEqual(p.offsets, []int{0, 1}) {
				t.Fatalf("tracks=%v, exact=%v, err=%v, pages=%v; want failure without partial tracks", tracks, exact, err, p.offsets)
			}
			if kind == "canceled" && !errors.Is(err, context.Canceled) {
				t.Fatalf("error = %v, want context.Canceled", err)
			}
		})
	}
}

func TestIPCProviderCollectionFilterAndLocalBinding(t *testing.T) {
	tracks := []playlist.Track{
		{Path: "/unmatched.flac", Title: "Other"},
		{Path: "/loosely.flac", Title: "Some Outer New Groove"},
		{Path: "/best.flac", Title: "song"},
		{Path: "/tied.flac", Title: "song"},
	}
	for _, filter := range []string{"", "song"} {
		t.Run("filter="+filter, func(t *testing.T) {
			p := &plainProv{tracks: tracks}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "local", Provider: p}})
			m.localProvider = p
			response := runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
				"provider": "local", "source": "playlist", "playlist": "Saved", "filter": filter, "selected_path": "/tied.flac",
			})
			// Compute expected order through the existing TUI search.
			want := tracks
			if filter != "" {
				view := Model{playlist: playlist.New()}
				view.playlist.Add(tracks...)
				view.search.query = filter
				view.updateSearch()
				want = nil
				for _, index := range view.search.results {
					want = append(want, tracks[index])
				}
			}
			if !reflect.DeepEqual(m.playlist.Tracks(), want) || response.Total != len(want) {
				t.Fatalf("filtered tracks = %+v; want TUI order %+v", m.playlist.Tracks(), want)
			}
			wantIndex := slices.IndexFunc(want, func(track playlist.Track) bool { return track.Path == "/tied.flac" })
			if m.playlist.Index() != wantIndex {
				t.Fatalf("selection = %d; want selected path at filtered index %d", m.playlist.Index(), wantIndex)
			}
			if filter == "" && (m.loadedPlaylist != "Saved" || m.activeProviderPlaylistID != "Saved") {
				t.Fatal("exact local collection lost its saved playlist binding")
			}
			if filter != "" && (m.loadedPlaylist != "" || m.playlistSource != "local:Saved") {
				t.Fatal("filtered collection retained writable saved binding or lost provider source")
			}
		})
	}
}

func TestIPCProviderCollectionRejectsMissingFilteredSelection(t *testing.T) {
	p := &plainProv{tracks: []playlist.Track{{Path: "/jazz.flac", Title: "Jazz"}, {Path: "/rock.flac", Title: "Rock"}}}
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "local", Provider: p}}, playlist.Track{Path: "/existing.flac"})
	before := m.playlist.Snapshot()
	job := runProviderDesktopJob(t, &m, "provider.collection", map[string]any{
		"provider": "local", "source": "playlist", "playlist": "Saved", "filter": "jazz", "selected_path": "/rock.flac",
	})
	if job.State != ipc.JobFailed || job.Error == nil || job.Error.Code != ipc.V2ErrorCodeNotFound || !reflect.DeepEqual(m.playlist.Snapshot(), before) {
		t.Fatalf("job=%+v; want missing selected track failure with unchanged queue", job)
	}
}

func TestIPCProviderCollectionWrapperDropsLocalBinding(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		io.WriteString(w, "#EXTM3U\nhttps://example.test/audio.mp3\n")
	}))
	defer server.Close()
	p := &plainProv{tracks: []playlist.Track{{Path: server.URL + "/station.m3u", Title: "Station"}}}
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "local", Provider: p}})
	m.localProvider = p
	runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
		"provider": "local", "source": "playlist", "playlist": "Radio", "mode": "replace",
	})
	if m.loadedPlaylist != "" || m.playlistSource != "local:Radio" || m.playlist.Len() != 1 || m.playlist.Tracks()[0].Path != "https://example.test/audio.mp3" {
		t.Fatalf("expanded collection=%+v, saved=%q, source=%q; want resolved stream without saved file binding", m.playlist.Tracks(), m.loadedPlaylist, m.playlistSource)
	}
}

func TestIPCProviderCollectionProviderLimitsAndResume(t *testing.T) {
	for _, source := range []string{"search", "related"} {
		t.Run(source, func(t *testing.T) {
			p := &ipcCollectionProvider{plainProv: plainProv{tracks: collectionTracks(500)}}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "catalog", Provider: p}})
			params := map[string]any{"source": source, "query": "Song", "track": ipc.TrackInfo{Path: "seed"}, "mode": "append"}
			if source == "search" {
				params["provider"] = "catalog"
			}
			response := runProviderDesktopV2(t, &m, "provider.collection", params)
			wantLimit := 25
			if source == "search" {
				wantLimit = 100
				if p.searchLimit != wantLimit {
					t.Fatalf("search limit = %d, want %d", p.searchLimit, wantLimit)
				}
			} else if p.relatedLimit != wantLimit {
				t.Fatalf("related limit = %d, want %d", p.relatedLimit, wantLimit)
			}
			if response.Provider != "catalog" || response.Total != wantLimit || m.playlist.Len() != wantLimit {
				t.Fatalf("provider=%q, total=%d, tracks=%d; want source provider and its %d returned tracks", response.Provider, response.Total, m.playlist.Len(), wantLimit)
			}
		})
	}
	t.Run("playlist resume", func(t *testing.T) {
		p := &resumeProv{tracks: stubTracks(), idx: 1, offset: 90 * time.Second}
		m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "books", Provider: p}})
		response := runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
			"provider": "books", "source": "playlist", "playlist": "book",
		})
		if response.Index != 1 || response.Position != 90 || m.playlist.Index() != 1 || m.resume.path != p.tracks[1].Path || m.resume.secs != 90 {
			t.Fatalf("response index/position=%d/%g, selection=%d, resume=%+v; want provider resume target", response.Index, response.Position, m.playlist.Index(), m.resume)
		}
	})
}

func TestIPCProviderCollectionCommitGuards(t *testing.T) {
	for _, kind := range []string{"cancel", "revision", "completed"} {
		t.Run(kind, func(t *testing.T) {
			p := &plainProv{tracks: collectionTracks(1203)}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "catalog", Provider: p}}, playlist.Track{Path: "/existing.flac"})
			params := ipcProviderDesktopParams{Request: ipc.Request{Provider: "catalog", Playlist: "all", Revision: m.playlist.Revision()}, Source: "playlist", Mode: "replace"}
			request := v2Request(t, "provider.collection", params.Request)
			var err error
			request.Request.Params, err = json.Marshal(params)
			if err != nil {
				t.Fatal(err)
			}
			updated, cmd := m.Update(request)
			m = updated.(Model)
			if cmd == nil {
				t.Fatal("collection fetch did not start")
			}
			result := cmd().(ipcProviderDesktopResult)
			if result.err != nil {
				t.Fatal(result.err)
			}
			switch kind {
			case "cancel":
				if err := request.Jobs.Cancel(request.JobID); err != nil {
					t.Fatal(err)
				}
			case "revision":
				m.playlist.Queue(0)
			case "completed":
				updated, _ = m.Update(result)
				m = updated.(Model)
			}
			before, revision := m.playlist.Snapshot(), m.playlist.Revision()
			updated, cmd = m.Update(result)
			m = updated.(Model)
			if cmd != nil || !reflect.DeepEqual(m.playlist.Snapshot(), before) || m.playlist.Revision() != revision {
				t.Fatal("canceled, stale, or replayed collection changed the playlist")
			}
			job, _ := request.Jobs.Get(request.JobID)
			if kind == "revision" && (job.Error == nil || job.Error.Code != ipc.V2ErrorCodeConflict) {
				t.Fatalf("job=%+v, want conflict", job)
			}
		})
	}
}

func TestIPCProviderCollectionRejectsUIOnlyPlaylist(t *testing.T) {
	p := &desktopBrowseProvider{}
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "catalog", Provider: p}})
	job := runProviderDesktopJob(t, &m, "provider.collection", map[string]any{
		"provider": "catalog", "source": "playlist", "playlist": "genres",
	})
	if job.State != ipc.JobFailed || job.Error == nil || !strings.Contains(job.Error.Detail, "not a playable playlist") || len(p.trackRequests) != 0 {
		t.Fatalf("job=%+v, track requests=%v; want browse row rejected before fetching", job, p.trackRequests)
	}
}
