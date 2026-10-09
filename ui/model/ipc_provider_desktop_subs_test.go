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

func TestProviderDesktopSubscriptionsList(t *testing.T) {
	source := &subProv{subs: []provider.SubscriptionInfo{
		{ID: "a", Name: "First", Author: "Alice"},
		{ID: "b", Name: "Second", Author: "Bob"},
		{ID: "c", Name: "Third", Author: "Carol"},
	}}
	active := &albumOnlyProv{}
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{
		{Key: "other", Name: "Other", Provider: active},
		{Key: "podcasts", Name: "Podcasts", Provider: source},
	}, playlist.Track{Path: "/existing.flac", Title: "Existing"})
	m.provider = active
	m.playlist.Queue(0)
	before := m.playlist.Snapshot()
	response := runProviderDesktopV2(t, &m, "provider.subscriptions", map[string]any{
		"provider": "podcasts", "offset": 1, "limit": 1,
	})
	want := []ipc.ProviderSubscriptionInfo{{ID: "b", Name: "Second", Author: "Bob"}}
	if response.Provider != "podcasts" || response.Total != 3 || !reflect.DeepEqual(response.Subscriptions, want) {
		t.Fatalf("subscriptions = %+v; want provider podcasts, total 3, and %+v", response, want)
	}
	if m.provider != active || !reflect.DeepEqual(m.playlist.Snapshot(), before) {
		t.Fatal("listing another provider's subscriptions changed the active provider or playlist")
	}
}

func TestProviderDesktopSubscriptionLoadModes(t *testing.T) {
	episodes := make([]playlist.Track, 205)
	for i := range episodes {
		episodes[i] = published(fmt.Sprintf("episode-%03d", i), "2026-01-01")
	}
	// A provider can list oldest-first. Only the newest modes select by date;
	// all-episode actions preserve the feed's own order.
	episodes[202] = published("newest", "2026-09-01")
	source := &subProv{
		subs:     []provider.SubscriptionInfo{{ID: "show", Name: "A show"}},
		episodes: map[string][]playlist.Track{"show": episodes},
	}
	for _, mode := range []string{"", "append", "play", "next", "newest", "newest_next"} {
		t.Run("mode="+mode, func(t *testing.T) {
			original := []playlist.Track{{Path: "/current.flac", Title: "Current"}, {Path: "/queued.flac", Title: "Queued"}}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{
				{Key: "podcasts", Name: "Podcasts", Provider: source},
			}, original...)
			m.playlist.Queue(1)
			response := runProviderDesktopV2(t, &m, "provider.subscription.load", map[string]any{
				"provider": "podcasts", "playlist": "show", "mode": mode,
			})
			added := episodes
			if mode == "newest" || mode == "newest_next" {
				added = episodes[202:203]
			}
			wantTracks := append(append([]playlist.Track(nil), original...), added...)
			if got := m.playlist.Tracks(); !reflect.DeepEqual(got, wantTracks) {
				t.Fatalf("playlist has %d tracks; want all %d tracks in original then feed order", len(got), len(wantTracks))
			}
			if response.Total != len(added) || len(response.Tracks) != min(len(added), 200) {
				t.Fatalf("response has total=%d, rows=%d; want total=%d and paged rows=%d", response.Total, len(response.Tracks), len(added), min(len(added), 200))
			}
			for i, track := range response.Tracks {
				if track.Path != added[i].Path {
					t.Fatalf("response track %d = %q, want %q", i, track.Path, added[i].Path)
				}
			}
			wantQueue := []playlist.Track{original[1]}
			if mode == "next" || mode == "newest_next" {
				wantQueue = append(wantQueue, added...)
			}
			if got := m.playlist.QueueTracks(); !reflect.DeepEqual(got, wantQueue) {
				t.Fatalf("play-next queue has %d tracks; want %d in existing then feed order", len(got), len(wantQueue))
			}
			wantIndex := 0
			if mode == "play" {
				wantIndex = len(original)
			}
			if m.playlist.Index() != wantIndex {
				t.Fatalf("playing index = %d, want %d", m.playlist.Index(), wantIndex)
			}
		})
	}
}

func TestProviderDesktopSubscriptionsNewestModes(t *testing.T) {
	source := &ipcContextSubscriptionProvider{
		load: func(_ context.Context, id string) ([]playlist.Track, error) {
			if id == "show-041" {
				return nil, nil
			}
			if id == "show-084" {
				return nil, errors.New("feed unavailable")
			}
			return []playlist.Track{published(id+"-old", "2026-01-01"), published(id+"-new", "2026-09-01")}, nil
		},
	}
	var latest []playlist.Track
	for i := range 205 {
		id := fmt.Sprintf("show-%03d", i)
		source.subs = append(source.subs, provider.SubscriptionInfo{ID: id, Name: fmt.Sprintf("Show %d", i)})
		if i != 41 && i != 84 {
			latest = append(latest, published(id+"-new", "2026-09-01"))
		}
	}
	for _, mode := range []string{"", "append", "next", "play"} {
		t.Run("mode="+mode, func(t *testing.T) {
			original := playlist.Track{Path: "/existing.flac", Title: "Existing"}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{
				{Key: "podcasts", Name: "Podcasts", Provider: source},
			}, original)
			m.playlist.Queue(0)
			response := runProviderDesktopV2(t, &m, "provider.subscriptions.newest", map[string]any{
				"provider": "podcasts", "mode": mode,
			})
			wantTracks := append([]playlist.Track{original}, latest...)
			if !reflect.DeepEqual(m.playlist.Tracks(), wantTracks) {
				t.Fatalf("playlist has %d tracks; want all %d ordered tracks beyond the response page", m.playlist.Len(), len(wantTracks))
			}
			if response.Total != len(latest) || len(response.Tracks) != 200 || !reflect.DeepEqual(response.Failed, []string{"Show 41", "Show 84"}) {
				t.Fatalf("response total/rows/failed = %d/%d/%v; want %d/200/[Show 41 Show 84]", response.Total, len(response.Tracks), response.Failed, len(latest))
			}
			wantQueue := []playlist.Track{original}
			if mode == "next" {
				wantQueue = append(wantQueue, latest...)
			}
			if !reflect.DeepEqual(m.playlist.QueueTracks(), wantQueue) {
				t.Fatal("newest sweep lost existing queue entries or subscription order")
			}
			wantIndex := 0
			if mode == "play" {
				wantIndex = 1
			}
			if m.playlist.Index() != wantIndex {
				t.Fatalf("playing index = %d, want %d", m.playlist.Index(), wantIndex)
			}
		})
	}
}

func TestProviderDesktopSubscriptionsCommitGuards(t *testing.T) {
	source := &subProv{
		subs:     []provider.SubscriptionInfo{{ID: "show", Name: "A show"}},
		episodes: map[string][]playlist.Track{"show": {published("episode", "2026-09-01")}},
	}
	for _, operation := range []string{"provider.subscription.load", "provider.subscriptions.newest"} {
		for _, stage := range []string{"cancel", "playlist conflict", "queue conflict", "success"} {
			t.Run(operation+"/"+stage, func(t *testing.T) {
				engine := &headlessEngine{}
				m := newHeadlessModel(t, engine, []provider.Entry{
					{Key: "podcasts", Name: "Podcasts", Provider: source},
				}, playlist.Track{Path: "/existing.flac", Title: "Existing"})
				params := ipcProviderDesktopParams{
					Request: ipc.Request{Provider: "podcasts", Playlist: "show", Revision: m.playlist.Revision()},
					Mode:    "next",
				}
				request := v2Request(t, operation, params.Request)
				var err error
				request.Request.Params, err = json.Marshal(params)
				if err != nil {
					t.Fatal(err)
				}
				updated, cmd := m.Update(request)
				m = updated.(Model)
				if cmd == nil {
					t.Fatal("subscription fetch did not start")
				}
				result, ok := cmd().(ipcProviderDesktopResult)
				if !ok || result.err != nil || len(result.tracks) != 1 {
					t.Fatalf("fetch result = %+v; want one episode", result)
				}
				switch stage {
				case "cancel":
					if err := request.Jobs.Cancel(request.JobID); err != nil {
						t.Fatal(err)
					}
				case "playlist conflict":
					m.playlist.Add(playlist.Track{Path: "/new.flac", Title: "Added during fetch"})
				case "queue conflict":
					m.playlist.Queue(0)
				}
				before, revision, engineBefore := m.playlist.Snapshot(), m.playlist.Revision(), *engine
				updated, cmd = m.Update(result)
				m = updated.(Model)
				job, _ := request.Jobs.Get(request.JobID)
				if stage == "success" {
					if job.State != ipc.JobSucceeded || job.Snapshot == nil || !reflect.DeepEqual(*job.Snapshot, m.runtimeSnapshot()) || m.playlist.Len() != 2 || m.playlist.QueueLen() != 1 {
						t.Fatalf("committed job = %+v; want successful job with its own queue snapshot", job)
					}
					committed, committedRevision := m.playlist.Snapshot(), m.playlist.Revision()
					updated, cmd = m.Update(result)
					m = updated.(Model)
					if cmd != nil || m.playlist.Revision() != committedRevision || !reflect.DeepEqual(m.playlist.Snapshot(), committed) {
						t.Fatal("replaying a completed result appended episodes again")
					}
					return
				}
				wantState, wantCode := ipc.JobFailed, ipc.V2ErrorCodeConflict
				if stage == "cancel" {
					wantState, wantCode = ipc.JobCanceled, ipc.V2ErrorCodeCanceled
				}
				if job.State != wantState || job.Error == nil || job.Error.Code != wantCode || job.Snapshot != nil {
					t.Fatalf("job = %+v; want %s/%s without a snapshot", job, wantState, wantCode)
				}
				if cmd != nil || !reflect.DeepEqual(m.playlist.Snapshot(), before) || m.playlist.Revision() != revision || !reflect.DeepEqual(*engine, engineBefore) {
					t.Fatal("canceled or stale subscription result changed playback or its queues")
				}
			})
		}
	}
}
