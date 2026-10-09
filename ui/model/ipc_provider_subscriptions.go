package model

import (
	"context"
	"fmt"
	"sync"

	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
)

// ipcSubscriptionInfos takes an owned snapshot of one provider's local
// subscriptions. Looking at subscriptions must not depend on the active TUI
// pane or start a feed fetch.
func ipcSubscriptionInfos(source playlist.Provider) ([]provider.SubscriptionInfo, error) {
	lister, ok := source.(provider.SubscriptionLister)
	if !ok {
		return nil, fmt.Errorf("provider does not support subscriptions")
	}
	return append([]provider.SubscriptionInfo(nil), lister.Subscriptions()...), nil
}

// ipcSubscriptionTracks fetches a subscribed or browsed show through the
// provider that owns its ID. The caller applies playback and queue actions in
// the model update loop, after checking cancellation and playlist revisions.
func ipcSubscriptionTracks(ctx context.Context, source playlist.Provider, id string, newestOnly bool) ([]playlist.Track, string, error) {
	ctx = requestContext(ctx)
	if err := ctx.Err(); err != nil {
		return nil, "", err
	}
	if id == "" {
		return nil, "", fmt.Errorf("show ID is required")
	}
	loader, ok := source.(provider.AlbumTrackLoader)
	if !ok {
		return nil, "", fmt.Errorf("provider does not support episode loading")
	}
	name, known := id, false
	if lister, ok := source.(provider.SubscriptionLister); ok {
		for _, show := range lister.Subscriptions() {
			if show.ID == id {
				known = true
				if show.Name != "" {
					name = show.Name
				}
				break
			}
		}
	}
	if shows, ok := source.(provider.ShowLister); ok && shows.IsShowID(id) {
		known = true
	}
	if !known {
		return nil, "", fmt.Errorf("provider does not recognize show %q", id)
	}
	tracks, err := ipcSubscriptionAlbumTracks(ctx, loader, id)
	if err != nil {
		return nil, name, fmt.Errorf("load %s: %w", name, err)
	}
	if newestOnly {
		if latest, ok := latestEpisode(tracks); ok {
			tracks = []playlist.Track{latest}
		} else {
			tracks = nil
		}
	}
	return tracks, name, nil
}

// ipcNewestSubscriptions returns the newest episode of each subscribed show
// in subscription order, with failed or empty shows named separately. Workers
// only fetch tracks; all are joined before results reach the model owner.
func ipcNewestSubscriptions(ctx context.Context, source playlist.Provider) ([]playlist.Track, []string, error) {
	ctx = requestContext(ctx)
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	shows, err := ipcSubscriptionInfos(source)
	if err != nil {
		return nil, nil, err
	}
	loader, ok := source.(provider.AlbumTrackLoader)
	if !ok {
		return nil, nil, fmt.Errorf("provider does not support episode loading")
	}
	latest := make([]*playlist.Track, len(shows))
	failed := make([]string, len(shows))
	jobs := make(chan int)
	var workers sync.WaitGroup
	for range min(len(shows), subsLatestWorkers) {
		workers.Go(func() {
			for i := range jobs {
				if ctx.Err() != nil {
					continue
				}
				tracks, err := ipcSubscriptionAlbumTracks(ctx, loader, shows[i].ID)
				if track, ok := latestEpisode(tracks); err == nil && ok {
					latest[i] = &track
				} else {
					failed[i] = shows[i].Name
					if failed[i] == "" {
						failed[i] = shows[i].ID
					}
				}
			}
		})
	}
dispatch:
	for i := range shows {
		select {
		case jobs <- i:
		case <-ctx.Done():
			break dispatch
		}
	}
	close(jobs)
	workers.Wait()
	if err := ctx.Err(); err != nil {
		return nil, nil, err
	}
	var tracks []playlist.Track
	var failures []string
	for i := range shows {
		if latest[i] != nil {
			tracks = append(tracks, *latest[i])
		}
		if failed[i] != "" {
			failures = append(failures, failed[i])
		}
	}
	return tracks, failures, nil
}

// Podcasts implement AlbumTracksContext, allowing a canceled desktop job to
// cancel its HTTP request too. Other providers retain their existing loader;
// cancellation still prevents their completed result from being applied.
func ipcSubscriptionAlbumTracks(ctx context.Context, loader provider.AlbumTrackLoader, id string) ([]playlist.Track, error) {
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	var tracks []playlist.Track
	var err error
	if contextual, ok := loader.(interface {
		AlbumTracksContext(context.Context, string) ([]playlist.Track, error)
	}); ok {
		tracks, err = contextual.AlbumTracksContext(ctx, id)
	} else {
		tracks, err = loader.AlbumTracks(id)
	}
	if contextErr := ctx.Err(); contextErr != nil {
		return nil, contextErr
	}
	return tracks, err
}
