package model

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
)

func TestDesktopSourcesResolveBeforeReplacing(t *testing.T) {
	for _, scenario := range []string{"success", "missing source", "broken m3u entry", "canceled", "queue changed"} {
		t.Run(scenario, func(t *testing.T) {
			m := newHeadlessModel(t, &headlessEngine{}, nil)
			m.playlist.Add(playlist.Track{Path: "old.mp3", Title: "Old"})
			dir := t.TempDir()
			path := filepath.Join(dir, "new.mp3")
			if err := os.WriteFile(path, []byte("fixture"), 0600); err != nil {
				t.Fatal(err)
			}
			args := []string{path}
			switch scenario {
			case "missing source":
				args = append(args, path+".missing")
			case "broken m3u entry":
				m3u := filepath.Join(dir, "broken.m3u")
				if err := os.WriteFile(m3u, []byte("missing-track.mp3\n"), 0600); err != nil {
					t.Fatal(err)
				}
				args = []string{m3u}
			}
			msg := v2Request(t, "sources.load", ipc.Request{Args: args, Name: "replace", Revision: m.playlist.Revision()})
			next, cmd := m.Update(msg)
			m = next.(Model)
			if cmd == nil {
				t.Fatal("expected source resolution")
			}
			if scenario == "canceled" {
				if err := msg.Jobs.Cancel(msg.JobID); err != nil {
					t.Fatal(err)
				}
			}
			resolved := cmd()
			if scenario == "queue changed" {
				m.playlist.Add(playlist.Track{Path: "concurrent.mp3"})
			}
			next, _ = m.Update(resolved)
			m = next.(Model)
			tracks := m.playlist.Tracks()
			if scenario == "success" {
				if len(tracks) != 1 || tracks[0].Path != path {
					t.Fatalf("resolved tracks: %+v", tracks)
				}
				if !m.playlistUndo.active {
					t.Fatal("replacement cannot be undone")
				}
			} else if len(tracks) == 0 || tracks[0].Path != "old.mp3" {
				t.Fatalf("changed queue on %s: %+v", scenario, tracks)
			}
		})
	}
}
