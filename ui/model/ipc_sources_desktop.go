package model

import (
	"context"
	"fmt"
	"os"
	"strings"

	tea "charm.land/bubbletea/v2"
	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/resolve"
)

type ipcSourcesDesktopResult struct {
	jobs    *ipc.JobStore
	jobID   string
	request ipc.Request
	tracks  []playlist.Track
	err     error
}

// Resolve every selected source before editing the queue. Failed/canceled
// resolution or a concurrent queue edit leaves the current queue intact.
func (m *Model) handleV2DesktopSources(ctx context.Context, jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	if len(request.Args) == 0 || len(request.Args) > 1000 || (request.Name != "append" && request.Name != "replace") {
		m.failV2Job(jobs, jobID, v2InvalidParamsError())
		return nil
	}
	for _, path := range request.Args {
		if strings.TrimSpace(path) == "" {
			m.failV2Job(jobs, jobID, v2InvalidParamsError())
			return nil
		}
	}
	if request.Revision == 0 {
		request.Revision = m.playlist.Revision()
	}
	return func() tea.Msg {
		result := ipcSourcesDesktopResult{jobs: jobs, jobID: jobID, request: request}
		for _, path := range request.Args {
			if result.err = ctx.Err(); result.err != nil {
				return result
			}
			tracks, err := resolve.URLContext(ctx, path)
			if err != nil {
				result.err = err
				return result
			}
			for _, track := range tracks {
				if track.Stream || playlist.IsURL(track.Path) || strings.HasPrefix(track.Path, "ssh://") {
					continue
				}
				info, err := os.Stat(track.Path)
				if err != nil {
					result.err = fmt.Errorf("playlist entry is unavailable: %w", err)
					return result
				}
				if !info.Mode().IsRegular() {
					result.err = fmt.Errorf("playlist entry is not an audio file: %s", track.Path)
					return result
				}
			}
			result.tracks = append(result.tracks, tracks...)
		}
		return result
	}
}

func (m *Model) handleIPCDesktopSources(result ipcSourcesDesktopResult) tea.Cmd {
	ctx, ok := result.jobs.Context(result.jobID)
	if !ok || ctx.Err() != nil {
		return nil
	}
	if result.err != nil {
		m.completeV2Job(result.jobs, result.jobID, ipc.Response{OK: false, Error: result.err.Error()})
		return nil
	}
	if result.request.Revision != m.playlist.Revision() {
		m.failV2Job(result.jobs, result.jobID, v2ConflictError())
		return nil
	}
	if len(result.tracks) == 0 {
		m.completeV2Job(result.jobs, result.jobID, ipc.Response{OK: false, Error: "no playable tracks found"})
		return nil
	}
	request := result.request
	request.Cmd = "tracks." + request.Name
	request.Tracks = ipcTrackInfos(result.tracks, func(playlist.Track) bool { return false })
	return m.applyV2ResolvedTracksBatch(result.jobs, result.jobID, request)
}
