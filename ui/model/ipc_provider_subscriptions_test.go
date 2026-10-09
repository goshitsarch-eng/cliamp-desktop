package model

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
)

type ipcContextSubscriptionProvider struct {
	subProv
	load func(context.Context, string) ([]playlist.Track, error)
}

func (p *ipcContextSubscriptionProvider) AlbumTracksContext(ctx context.Context, id string) ([]playlist.Track, error) {
	return p.load(ctx, id)
}

type ipcSubscriptionListOnly struct {
	plainProv
}

func (*ipcSubscriptionListOnly) Subscriptions() []provider.SubscriptionInfo {
	return []provider.SubscriptionInfo{{ID: "show", Name: "A show"}}
}

type ipcSubscriptionLoaderFunc func(string) ([]playlist.Track, error)

func (load ipcSubscriptionLoaderFunc) AlbumTracks(id string) ([]playlist.Track, error) {
	return load(id)
}

func TestIPCSubscriptionInfosSnapshot(t *testing.T) {
	source := &subProv{subs: []provider.SubscriptionInfo{{ID: "feed", Name: "First", Author: "Author"}}}
	shows, err := ipcSubscriptionInfos(source)
	if err != nil || !reflect.DeepEqual(shows, source.subs) {
		t.Fatalf("subscriptions = %+v, %v; want %+v", shows, err, source.subs)
	}
	shows[0].Name = "Changed by client"
	if source.subs[0].Name != "First" {
		t.Fatal("subscription result aliases the provider's list")
	}
	if _, err := ipcSubscriptionInfos(&plainProv{}); err == nil {
		t.Fatal("provider without subscriptions was accepted")
	}
}

func TestIPCSubscriptionTracks(t *testing.T) {
	episodes := []playlist.Track{published("older", "2026-01-01"), published("newer", "2026-09-01")}
	source := &sectionedSubProv{
		subProv: subProv{
			subs: []provider.SubscriptionInfo{{ID: "feed", Name: "Subscribed show"}},
			episodes: map[string][]playlist.Track{
				"feed": episodes, "discovered": episodes, "empty": nil,
			},
		},
		favoritable: map[string]bool{"discovered": true, "empty": true},
	}
	for _, tc := range []struct {
		name, id, wantName string
		newest             bool
		want               []playlist.Track
	}{
		{name: "all episodes keep feed order", id: "feed", wantName: "Subscribed show", want: episodes},
		{name: "newest uses publication date", id: "feed", newest: true, wantName: "Subscribed show", want: episodes[1:]},
		{name: "unsubscribed show", id: "discovered", newest: true, wantName: "discovered", want: episodes[1:]},
		{name: "empty feed", id: "empty", newest: true, wantName: "empty"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tracks, name, err := ipcSubscriptionTracks(t.Context(), source, tc.id, tc.newest)
			if err != nil || name != tc.wantName || !reflect.DeepEqual(tracks, tc.want) {
				t.Fatalf("load = %+v, %q, %v; want %+v, %q", tracks, name, err, tc.want, tc.wantName)
			}
		})
	}
	for _, tc := range []struct {
		name   string
		source playlist.Provider
		id     string
		want   string
	}{
		{name: "empty ID", source: source, want: "show ID is required"},
		{name: "unknown ID", source: source, id: "unknown", want: "does not recognize show"},
		{name: "album is not a show", source: &albumOnlyProv{}, id: "album", want: "does not recognize show"},
		{name: "no loader", source: &ipcSubscriptionListOnly{}, id: "show", want: "does not support episode loading"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tracks, _, err := ipcSubscriptionTracks(t.Context(), tc.source, tc.id, true)
			if len(tracks) != 0 || err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("load = %+v, %v; want error containing %q", tracks, err, tc.want)
			}
		})
	}
}

func TestIPCSubscriptionTracksContextAndFailure(t *testing.T) {
	wantErr := errors.New("feed unavailable")
	for _, tc := range []struct {
		name       string
		cancelWhen string
		want       error
	}{
		{name: "canceled before fetch", cancelWhen: "before", want: context.Canceled},
		{name: "canceled during fetch", cancelWhen: "during", want: context.Canceled},
		{name: "provider failure", want: wantErr},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			calls := 0
			source := &ipcContextSubscriptionProvider{
				subProv: subProv{subs: []provider.SubscriptionInfo{{ID: "show", Name: "Show"}}},
				load: func(got context.Context, id string) ([]playlist.Track, error) {
					calls++
					if got != ctx || id != "show" {
						t.Errorf("loader context/ID = %v, %q; want caller context and show", got, id)
					}
					if tc.cancelWhen == "during" {
						cancel()
						return []playlist.Track{{Title: "Discard after cancellation"}}, nil
					}
					return nil, wantErr
				},
			}
			if tc.cancelWhen == "before" {
				cancel()
			}
			tracks, _, err := ipcSubscriptionTracks(ctx, source, "show", false)
			if len(tracks) != 0 || !errors.Is(err, tc.want) {
				t.Fatalf("load = %+v, %v; want no tracks and %v", tracks, err, tc.want)
			}
			if tc.cancelWhen == "before" && calls != 0 {
				t.Fatal("canceled request reached provider")
			}
		})
	}
}

func TestIPCSubscriptionLegacyLoaderCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(t.Context())
	defer cancel()
	loader := ipcSubscriptionLoaderFunc(func(string) ([]playlist.Track, error) {
		cancel()
		return []playlist.Track{{Title: "Result arrived after cancellation"}}, nil
	})
	tracks, err := ipcSubscriptionAlbumTracks(ctx, loader, "show")
	if len(tracks) != 0 || !errors.Is(err, context.Canceled) {
		t.Fatalf("legacy load = %+v, %v; want no tracks and context.Canceled", tracks, err)
	}
}

func TestIPCNewestSubscriptionsOrderAndFailures(t *testing.T) {
	source := &ipcContextSubscriptionProvider{
		subProv: subProv{subs: []provider.SubscriptionInfo{
			{ID: "a", Name: "A"}, {ID: "broken", Name: "Broken"},
			{ID: "b", Name: "B"}, {ID: "empty"},
		}},
		load: func(_ context.Context, id string) ([]playlist.Track, error) {
			switch id {
			case "broken":
				return nil, errors.New("provider is offline")
			case "empty":
				return nil, nil
			default:
				return []playlist.Track{published(id+"-old", "2026-01-01"), published(id+"-new", "2026-09-01")}, nil
			}
		},
	}
	tracks, failed, err := ipcNewestSubscriptions(t.Context(), source)
	want := []playlist.Track{published("a-new", "2026-09-01"), published("b-new", "2026-09-01")}
	if err != nil || !reflect.DeepEqual(tracks, want) || !reflect.DeepEqual(failed, []string{"Broken", "empty"}) {
		t.Fatalf("newest = %+v, %v, %v; want %+v and [Broken empty]", tracks, failed, err, want)
	}
}

func TestIPCNewestSubscriptionsEmptyAndUnsupported(t *testing.T) {
	for _, tc := range []struct {
		name   string
		source playlist.Provider
		want   string
	}{
		{name: "empty subscriptions", source: &subProv{}},
		{name: "no subscriptions", source: &plainProv{}, want: "does not support subscriptions"},
		{name: "no loader", source: &ipcSubscriptionListOnly{}, want: "does not support episode loading"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tracks, failed, err := ipcNewestSubscriptions(t.Context(), tc.source)
			if len(tracks) != 0 || len(failed) != 0 {
				t.Fatalf("newest = %+v, %v; want empty results", tracks, failed)
			}
			if tc.want == "" {
				if err != nil {
					t.Fatal(err)
				}
			} else if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("error = %v, want error containing %q", err, tc.want)
			}
		})
	}
}

func TestIPCNewestSubscriptionsBoundsWorkers(t *testing.T) {
	var running, peak atomic.Int32
	started := make(chan struct{}, 2*subsLatestWorkers)
	release := make(chan struct{})
	var releaseOnce sync.Once
	releaseWorkers := func() { releaseOnce.Do(func() { close(release) }) }
	defer releaseWorkers()
	source := &ipcContextSubscriptionProvider{
		load: func(ctx context.Context, id string) ([]playlist.Track, error) {
			current := running.Add(1)
			defer running.Add(-1)
			for previous := peak.Load(); current > previous && !peak.CompareAndSwap(previous, current); previous = peak.Load() {
			}
			started <- struct{}{}
			select {
			case <-release:
			case <-ctx.Done():
				return nil, ctx.Err()
			}
			return []playlist.Track{{Title: id}}, nil
		},
	}
	for i := range 2 * subsLatestWorkers {
		source.subs = append(source.subs, provider.SubscriptionInfo{ID: fmt.Sprint(i)})
	}
	finished := make(chan error, 1)
	go func() {
		tracks, failed, err := ipcNewestSubscriptions(t.Context(), source)
		if err == nil && (len(tracks) != len(source.subs) || len(failed) != 0) {
			err = fmt.Errorf("got %d tracks and %d failures", len(tracks), len(failed))
		}
		finished <- err
	}()
	for range subsLatestWorkers {
		select {
		case <-started:
		case <-time.After(5 * time.Second):
			t.Fatal("workers did not start")
		}
	}
	releaseWorkers()
	select {
	case err := <-finished:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("workers did not finish")
	}
	if peak.Load() != subsLatestWorkers || running.Load() != 0 {
		t.Fatalf("peak/running = %d/%d; want %d/0", peak.Load(), running.Load(), subsLatestWorkers)
	}
}

func TestIPCNewestSubscriptionsCancellationJoinsWorkers(t *testing.T) {
	for _, before := range []bool{true, false} {
		t.Run(fmt.Sprintf("before_fetch=%t", before), func(t *testing.T) {
			ctx, cancel := context.WithCancel(t.Context())
			defer cancel()
			var running atomic.Int32
			started := make(chan struct{}, 2*subsLatestWorkers)
			source := &ipcContextSubscriptionProvider{
				load: func(ctx context.Context, _ string) ([]playlist.Track, error) {
					running.Add(1)
					defer running.Add(-1)
					started <- struct{}{}
					<-ctx.Done()
					return nil, ctx.Err()
				},
			}
			for i := range 2 * subsLatestWorkers {
				source.subs = append(source.subs, provider.SubscriptionInfo{ID: fmt.Sprint(i)})
			}
			if before {
				cancel()
			}
			finished := make(chan error, 1)
			go func() {
				tracks, failed, err := ipcNewestSubscriptions(ctx, source)
				if len(tracks) != 0 || len(failed) != 0 {
					finished <- fmt.Errorf("canceled sweep returned %d tracks and %d failures", len(tracks), len(failed))
					return
				}
				finished <- err
			}()
			if !before {
				select {
				case <-started:
				case <-time.After(5 * time.Second):
					t.Fatal("fetch did not start")
				}
				cancel()
			}
			select {
			case err := <-finished:
				if !errors.Is(err, context.Canceled) {
					t.Fatalf("error = %v, want context.Canceled", err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("canceled fetch did not finish")
			}
			if running.Load() != 0 {
				t.Fatal("workers remained running after canceled sweep returned")
			}
			if before && len(started) != 0 {
				t.Fatal("already canceled sweep started a provider call")
			}
		})
	}
}
