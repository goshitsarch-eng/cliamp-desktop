package model

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"reflect"
	"testing"

	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
)

type ipcAlbumCollectionProvider struct {
	plainProv
	results []playlist.Track
	albums  map[string][]playlist.Track
	calls   []string
}

func (p *ipcAlbumCollectionProvider) SearchTracks(ctx context.Context, _ string, _ int) ([]playlist.Track, error) {
	return p.results, ctx.Err()
}
func (*ipcAlbumCollectionProvider) AlbumTracks(string) ([]playlist.Track, error) {
	return nil, errors.New("album expansion must use its context-aware loader")
}
func (p *ipcAlbumCollectionProvider) AlbumTracksContext(ctx context.Context, id string) ([]playlist.Track, error) {
	p.calls = append(p.calls, id)
	return p.albums[id], ctx.Err()
}

func ipcCollectionAlbum(id string) playlist.Track {
	return playlist.Track{
		Path: "catalog:album:" + id, Title: "Needle album " + id,
		ProviderMeta: map[string]string{playlist.MetaKind: playlist.MetaKindAlbum, playlist.MetaAlbumID: id},
	}
}

func TestIPCProviderCollectionSearchExcludesAlbumSiblings(t *testing.T) {
	songs := []playlist.Track{{Path: "/first.flac", Title: "First"}, {Path: "/second.flac", Title: "Second"}}
	for _, mode := range []string{"", "play", "append", "next", "replace"} {
		t.Run("mode="+mode, func(t *testing.T) {
			p := &ipcAlbumCollectionProvider{results: []playlist.Track{
				ipcCollectionAlbum("one"), songs[0], ipcCollectionAlbum("two"), songs[1],
			}}
			before := cloneTracks(p.results)
			original := playlist.Track{Path: "/existing.flac"}
			engine := &headlessEngine{}
			engine.playing = true
			m := newHeadlessModel(t, engine, []provider.Entry{{Key: "catalog", Provider: p}}, original)
			m.setPlaybackTrack(original)
			m.playlist.Queue(0)
			response := runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
				"provider": "catalog", "source": "search", "query": "Needle", "selected_path": songs[1].Path, "mode": mode,
			})
			wantTracks := songs
			wantQueue := []playlist.Track{}
			if mode == "append" || mode == "next" {
				wantTracks = append([]playlist.Track{original}, songs...)
				wantQueue = []playlist.Track{original}
				if mode == "next" {
					wantQueue = append(wantQueue, songs...)
				}
			}
			if !reflect.DeepEqual(m.playlist.Tracks(), wantTracks) || !reflect.DeepEqual(m.playlist.QueueTracks(), wantQueue) {
				t.Fatalf("tracks/queue = %+v/%+v; want playable songs without album siblings", m.playlist.Tracks(), m.playlist.QueueTracks())
			}
			if response.Total != len(songs) || len(response.Tracks) != len(songs) || len(p.calls) != 0 {
				t.Fatalf("total/rows/album loads = %d/%d/%v; want 2/2/none", response.Total, len(response.Tracks), p.calls)
			}
			if (mode == "" || mode == "play") && m.playlist.Index() != 1 {
				t.Fatalf("selected index = %d, want second playable result", m.playlist.Index())
			}
			if !reflect.DeepEqual(p.results, before) {
				t.Fatal("removing album siblings mutated the provider's cached result slice")
			}
		})
	}
}

func TestIPCProviderCollectionSearchSelectedAlbum(t *testing.T) {
	for _, feed := range []bool{false, true} {
		for _, mode := range []string{"", "play", "append", "next"} {
			t.Run(fmt.Sprintf("feed=%t/mode=%s", feed, mode), func(t *testing.T) {
				album := ipcCollectionAlbum("selected")
				album.Feed = feed
				tracks := collectionTracks(213)
				// An album loader's malformed container row must be removed
				// without changing the returned slice owned by that provider.
				expanded := append([]playlist.Track{ipcCollectionAlbum("nested")}, tracks...)
				p := &ipcAlbumCollectionProvider{
					results: []playlist.Track{ipcCollectionAlbum("other"), {Path: "/sibling.flac", Title: "Needle song"}, album},
					albums:  map[string][]playlist.Track{"selected": expanded},
				}
				searchBefore, albumBefore := cloneTracks(p.results), cloneTracks(expanded)
				original := playlist.Track{Path: "/existing.flac"}
				engine := &headlessEngine{}
				engine.playing = true
				m := newHeadlessModel(t, engine, []provider.Entry{{Key: "catalog", Provider: p}}, original)
				m.setPlaybackTrack(original)
				m.playlist.Queue(0)
				response := runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
					"provider": "catalog", "source": "search", "query": "Needle", "filter": "needle",
					"selected_path": album.Path, "mode": mode,
				})
				want := append([]playlist.Track{original}, tracks...)
				wantQueue := []playlist.Track{original}
				if mode == "next" {
					wantQueue = append(wantQueue, tracks...)
				}
				if !reflect.DeepEqual(m.playlist.Tracks(), want) || !reflect.DeepEqual(m.playlist.QueueTracks(), wantQueue) {
					t.Fatal("selected album lost the existing queue, included siblings, or filtered expanded tracks by the album search text")
				}
				if !reflect.DeepEqual(p.calls, []string{"selected"}) || response.Total != len(tracks) || len(response.Tracks) != 200 {
					t.Fatalf("album loads/total/rows = %v/%d/%d; want selected album only with 213/200", p.calls, response.Total, len(response.Tracks))
				}
				wantIndex := 0
				if mode == "" || mode == "play" {
					wantIndex = 1
				}
				if m.playlist.Index() != wantIndex {
					t.Fatalf("playing index = %d, want %d", m.playlist.Index(), wantIndex)
				}
				if !reflect.DeepEqual(p.results, searchBefore) || !reflect.DeepEqual(p.albums["selected"], albumBefore) {
					t.Fatal("album expansion modified provider-owned search or album rows")
				}
			})
		}
	}
}

func TestIPCProviderCollectionExplicitAlbumMatchesTUI(t *testing.T) {
	album, tracks := ipcCollectionAlbum("selected"), collectionTracks(3)
	info := ipcTrackInfo(album, 0, 0, false)
	for _, playing := range []bool{false, true} {
		for _, mode := range []string{"", "play", "append", "next"} {
			t.Run(fmt.Sprintf("playing=%t/mode=%s", playing, mode), func(t *testing.T) {
				p := &ipcAlbumCollectionProvider{albums: map[string][]playlist.Track{"selected": tracks}}
				original := []playlist.Track{{Path: "/current.flac"}, {Path: "/queued.flac"}}
				engine, expectedEngine := &headlessEngine{}, &headlessEngine{}
				engine.playing, expectedEngine.playing = playing, playing
				m := newHeadlessModel(t, engine, []provider.Entry{{Key: "catalog", Provider: p}}, original...)
				expected := newHeadlessModel(t, expectedEngine, nil, original...)
				m.playlist.Queue(1)
				expected.playlist.Queue(1)
				if playing {
					m.setPlaybackTrack(original[0])
					expected.setPlaybackTrack(original[0])
				}
				switch mode {
				case "append":
					expected.appendAlbum(album, tracks)
				case "next":
					expected.queueAlbumNext(album, tracks)
				default:
					expected.playAlbumImmediate(album, tracks)
				}
				runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
					"provider": "catalog", "source": "album", "album": "selected", "track": info, "mode": mode,
				})
				if !reflect.DeepEqual(m.playlist.Snapshot(), expected.playlist.Snapshot()) || !reflect.DeepEqual(engine.playCalls, expectedEngine.playCalls) || engine.playing != expectedEngine.playing {
					t.Fatalf("desktop album state = %+v, calls=%v, playing=%v; want established TUI state %+v, calls=%v, playing=%v",
						m.playlist.Snapshot(), engine.playCalls, engine.playing, expected.playlist.Snapshot(), expectedEngine.playCalls, expectedEngine.playing)
				}
				if !reflect.DeepEqual(p.calls, []string{"selected"}) {
					t.Fatalf("album loads = %v, want selected only", p.calls)
				}
			})
		}
	}
}

func TestIPCProviderCollectionAlbumRejectsInvalidAndEmpty(t *testing.T) {
	for _, kind := range []string{"mismatched ID", "missing ID", "not album", "empty expansion", "only placeholders"} {
		t.Run(kind, func(t *testing.T) {
			album := ipcCollectionAlbum("selected")
			expanded := collectionTracks(1)
			switch kind {
			case "mismatched ID":
				album.ProviderMeta[playlist.MetaAlbumID] = "other"
			case "missing ID":
				delete(album.ProviderMeta, playlist.MetaAlbumID)
			case "not album":
				album.ProviderMeta = nil
			case "empty expansion":
				expanded = nil
			case "only placeholders":
				expanded = []playlist.Track{ipcCollectionAlbum("nested")}
			}
			p := &ipcAlbumCollectionProvider{albums: map[string][]playlist.Track{"selected": expanded}}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "catalog", Provider: p}}, playlist.Track{Path: "/existing.flac"})
			before := m.playlist.Snapshot()
			wantCode, wantCalls := ipc.V2ErrorCodeInvalidParams, 0
			if kind == "empty expansion" || kind == "only placeholders" {
				wantCode, wantCalls = ipc.V2ErrorCodeNotFound, 1
			}
			job := runProviderDesktopJob(t, &m, "provider.collection", map[string]any{
				"provider": "catalog", "source": "album", "album": "selected", "track": ipcTrackInfo(album, 0, 0, false), "mode": "append",
			})
			if job.State != ipc.JobFailed || job.Error == nil || job.Error.Code != wantCode || len(p.calls) != wantCalls || !reflect.DeepEqual(m.playlist.Snapshot(), before) {
				t.Fatalf("job=%+v, album loads=%v; want %s and unchanged queue", job, p.calls, wantCode)
			}
		})
	}
}

func TestIPCProviderCollectionAlbumStaleSearchSelection(t *testing.T) {
	album := ipcCollectionAlbum("selected")
	for _, mode := range []string{"", "play", "append", "next", "replace"} {
		t.Run("mode="+mode, func(t *testing.T) {
			p := &ipcAlbumCollectionProvider{results: []playlist.Track{album, {Path: "/sibling.flac", Title: "Other"}}}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "catalog", Provider: p}}, playlist.Track{Path: "/existing.flac"})
			before := m.playlist.Snapshot()
			job := runProviderDesktopJob(t, &m, "provider.collection", map[string]any{
				"provider": "catalog", "source": "search", "query": "album", "filter": "Other", "selected_path": album.Path, "mode": mode,
			})
			if job.State != ipc.JobFailed || job.Error == nil || job.Error.Code != ipc.V2ErrorCodeNotFound || len(p.calls) != 0 || !reflect.DeepEqual(m.playlist.Snapshot(), before) {
				t.Fatalf("job=%+v; stale album selection must not load sibling tracks", job)
			}
		})
	}
}

func TestIPCProviderCollectionAlbumRemovalDropsLocalBinding(t *testing.T) {
	p := &plainProv{tracks: []playlist.Track{ipcCollectionAlbum("bookmark"), {Path: "/song.flac", Title: "Song"}}}
	before := cloneTracks(p.tracks)
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "local", Provider: p}})
	m.localProvider = p
	runProviderDesktopV2(t, &m, "provider.collection", map[string]any{
		"provider": "local", "source": "playlist", "playlist": "Saved", "mode": "replace",
	})
	if m.loadedPlaylist != "" || m.playlistSource != "local:Saved" || m.playlist.Len() != 1 || !reflect.DeepEqual(p.tracks, before) {
		t.Fatal("stripping a saved album container retained a writable binding or mutated the source playlist")
	}
}

func TestIPCProviderCollectionAlbumCommitGuards(t *testing.T) {
	album := ipcCollectionAlbum("selected")
	for _, kind := range []string{"canceled", "revision"} {
		t.Run(kind, func(t *testing.T) {
			p := &ipcAlbumCollectionProvider{albums: map[string][]playlist.Track{"selected": collectionTracks(3)}}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{{Key: "catalog", Provider: p}}, playlist.Track{Path: "/existing.flac"})
			info := ipcTrackInfo(album, 0, 0, false)
			params := ipcProviderDesktopParams{
				Request: ipc.Request{Provider: "catalog", Album: "selected", Track: &info, Revision: m.playlist.Revision()},
				Source:  "album", Mode: "play",
			}
			request := v2Request(t, "provider.collection", params.Request)
			var err error
			request.Request.Params, err = json.Marshal(params)
			if err != nil {
				t.Fatal(err)
			}
			updated, cmd := m.Update(request)
			m = updated.(Model)
			if cmd == nil {
				t.Fatal("album expansion did not start")
			}
			result := cmd().(ipcProviderDesktopResult)
			if result.err != nil || len(result.tracks) != 3 {
				t.Fatalf("expansion=%+v, want album tracks ready for owner commit", result)
			}
			wantState, wantCode := ipc.JobFailed, ipc.V2ErrorCodeConflict
			if kind == "canceled" {
				if err := request.Jobs.Cancel(request.JobID); err != nil {
					t.Fatal(err)
				}
				wantState, wantCode = ipc.JobCanceled, ipc.V2ErrorCodeCanceled
			} else {
				m.playlist.Queue(0)
			}
			before := m.playlist.Snapshot()
			updated, cmd = m.Update(result)
			m = updated.(Model)
			job, _ := request.Jobs.Get(request.JobID)
			if cmd != nil || !reflect.DeepEqual(m.playlist.Snapshot(), before) || job.State != wantState || job.Error == nil || job.Error.Code != wantCode {
				t.Fatalf("job=%+v; canceled/stale expanded album must not append or start playback", job)
			}
		})
	}
}
