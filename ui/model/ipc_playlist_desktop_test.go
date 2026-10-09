package model

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"

	"github.com/bjarneo/cliamp/external/local"
	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
)

func desktopPlaylistTestModel(t *testing.T) (Model, *local.Provider) {
	t.Helper()
	m := newHeadlessModel(t, &headlessEngine{}, nil)
	p := local.New(nil, nil)
	m.localProvider = p
	m.providers = []provider.Entry{{Key: "local", Name: "Local", Provider: p}}
	return m, p
}

func TestDesktopSavedPlaylistUndoRestoresExactDocument(t *testing.T) {
	for _, operation := range []string{"playlist.prepend", "playlist.replace", "playlist.delete", "playlist.dirs.add", "playlist.dirs.remove", "playlist.dirs.recursive"} {
		t.Run(operation, func(t *testing.T) {
			m, p := desktopPlaylistTestModel(t)
			original := []byte("# Keep comments and ordering.\n[[track]]\npath = \"/music/original.flac\"\ntitle = \"Original\"\n\n[[dir]]\npath = \"/music/live\"\nrecursive = false\n")
			if err := p.RestorePlaylistDocument("Mix", original); err != nil {
				t.Fatal(err)
			}
			request := ipc.Request{Provider: "local", Playlist: "Mix", Path: "/music/live", Name: "on", Tracks: []ipc.TrackInfo{{Path: "/music/new.flac", ProviderMeta: map[string]string{"origin": "kept"}}}}
			if operation == "playlist.dirs.add" {
				request.Path = t.TempDir()
			}
			if result := runV2(t, &m, operation, request); !result.OK {
				t.Fatalf("%s = %+v", operation, result)
			}
			if result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Mix"}); !result.OK {
				t.Fatalf("undo = %+v", result)
			}
			restored, err := p.PlaylistDocument("Mix")
			if err != nil || !bytes.Equal(restored, original) {
				t.Fatalf("restored %q, error %v, want exact %q", restored, err, original)
			}
			if result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Mix"}); result.OK {
				t.Fatal("second undo unexpectedly succeeded")
			}
		})
	}
}

func TestDesktopSavedPlaylistUndoRefusesNewerWrite(t *testing.T) {
	m, p := desktopPlaylistTestModel(t)
	if err := p.SavePlaylist("Mix", []playlist.Track{{Path: "/before.mp3"}}); err != nil {
		t.Fatal(err)
	}
	if result := runV2(t, &m, "playlist.prepend", ipc.Request{Provider: "local", Playlist: "Mix", Tracks: []ipc.TrackInfo{{Path: "/first.mp3"}}}); !result.OK {
		t.Fatal(result)
	}
	if err := p.AddTrackToPlaylist(context.Background(), "Mix", playlist.Track{Path: "/external.mp3"}); err != nil {
		t.Fatal(err)
	}
	expected, _ := p.PlaylistDocument("Mix")
	result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Mix"})
	if !strings.HasPrefix(result.Error, ipc.V2ErrorCodeConflict) {
		t.Fatalf("undo = %+v", result)
	}
	actual, _ := p.PlaylistDocument("Mix")
	if !bytes.Equal(actual, expected) {
		t.Fatal("undo overwrote another writer's edit")
	}
}

func TestDesktopSavedPlaylistCreateRenameUndo(t *testing.T) {
	m, p := desktopPlaylistTestModel(t)
	if result := runV2(t, &m, "playlist.create", ipc.Request{Provider: "local", Playlist: "Mix"}); !result.OK {
		t.Fatal(result)
	}
	if result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Mix"}); !result.OK {
		t.Fatal(result)
	}
	if _, err := p.PlaylistDocument("Mix"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("created playlist remains: %v", err)
	}
	original := []byte("# retained\n[[track]]\npath = \"/a.mp3\"\n[[dir]]\npath = \"/source\"\n")
	if err := p.RestorePlaylistDocument("Mix", original); err != nil {
		t.Fatal(err)
	}
	if result := runV2(t, &m, "playlist.rename", ipc.Request{Provider: "local", Playlist: "Mix", NewName: "Renamed"}); !result.OK {
		t.Fatal(result)
	}
	if result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Renamed"}); !result.OK {
		t.Fatal(result)
	}
	actual, _ := p.PlaylistDocument("Mix")
	if !bytes.Equal(actual, original) {
		t.Fatalf("rename undo document = %q", actual)
	}
}

func TestDesktopDirectoriesAndPrependPreserveSources(t *testing.T) {
	m, p := desktopPlaylistTestModel(t)
	dir := t.TempDir()
	file := filepath.Join(dir, "file.mp3")
	if err := os.WriteFile(file, []byte{}, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := p.SavePlaylist("Mix", []playlist.Track{{Path: "/existing.mp3"}}); err != nil {
		t.Fatal(err)
	}
	if result := runV2(t, &m, "playlist.dirs.add", ipc.Request{Provider: "local", Playlist: "Mix", Path: dir}); !result.OK {
		t.Fatal(result)
	}
	if result := runV2(t, &m, "playlist.dirs.recursive", ipc.Request{Provider: "local", Playlist: "Mix", Path: dir, Name: "off"}); !result.OK {
		t.Fatal(result)
	}
	if result := runV2(t, &m, "playlist.prepend", ipc.Request{Provider: "local", Playlist: "Mix", Tracks: []ipc.TrackInfo{{Path: file}, {Path: "/new.mp3"}, {Path: "/existing.mp3"}}}); !result.OK {
		t.Fatal(result)
	}
	dirs, err := p.DirSources("Mix")
	if err != nil || len(dirs) != 1 || dirs[0].Path != dir || dirs[0].Recursive {
		t.Fatalf("directory sources = %+v, %v", dirs, err)
	}
	document, _ := p.PlaylistDocument("Mix")
	if bytes.Contains(document, []byte("path = \""+file+"\"")) {
		t.Fatal("prepend materialized a directory source track")
	}
	if !bytes.Contains(document, []byte("[[dir]]")) {
		t.Fatal("prepend dropped directory source")
	}
}

func TestDesktopBatchTracksAndQueueUndoShareSnapshot(t *testing.T) {
	for _, op := range []string{"tracks.append", "tracks.replace"} {
		t.Run(op, func(t *testing.T) {
			m, _, _ := queueOpModel(t, false, "Mix", 0)
			m.playlist.Queue(2)
			track := ipc.TrackInfo{Path: "spotify:track:one", Title: "One", Restricted: true, ProviderMeta: map[string]string{"source": "spotify"}}
			if result := runV2(t, &m, op, ipc.Request{Tracks: []ipc.TrackInfo{track}, Revision: m.playlist.Revision()}); !result.OK {
				t.Fatal(result)
			}
			tracks := m.playlist.Tracks()
			last := tracks[len(tracks)-1]
			if last.ProviderMeta["source"] != "spotify" || !last.Restricted {
				t.Fatalf("metadata lost: %+v", last)
			}
			if !m.playlistUndo.active {
				t.Fatal("batch did not share Ctrl+Z undo")
			}
			if result := runV2(t, &m, "queue.undo", ipc.Request{Revision: m.playlist.Revision()}); !result.OK {
				t.Fatal(result)
			}
			if got := queueOpPaths(m.playlist.Tracks()); got != "a b c" || m.loadedPlaylist != "Mix" || m.playlist.QueueLen() != 1 {
				t.Fatalf("undo = %s, loaded %q, play-next %d", got, m.loadedPlaylist, m.playlist.QueueLen())
			}
		})
	}
}

func TestDesktopQueueUndoRevisionAndPersistence(t *testing.T) {
	m, p, _ := queueOpModel(t, false, "Mix", 1)
	original, _ := p.PlaylistDocument("Mix")
	before := m.playlist.Revision()
	if result := runV2(t, &m, "queue.move", ipc.Request{Index: 0, To: 2, Revision: before}); !result.OK {
		t.Fatal(result)
	}
	if result := runV2(t, &m, "queue.undo", ipc.Request{Revision: before}); result.Error != ipc.V2ErrorCodeConflict {
		t.Fatalf("stale undo = %+v", result)
	}
	if result := runV2(t, &m, "queue.undo", ipc.Request{Revision: m.playlist.Revision()}); !result.OK {
		t.Fatal(result)
	}
	restored, _ := p.PlaylistDocument("Mix")
	if !bytes.Equal(restored, original) || queueOpPaths(m.playlist.Tracks()) != "a b c" {
		t.Fatal("queue reorder undo did not restore disk and memory")
	}
	if result := runV2(t, &m, "queue.remove", ipc.Request{Index: 1}); !result.OK {
		t.Fatal(result)
	}
	m.undoPlaylistMutation()
	if queueOpPaths(m.playlist.Tracks()) != "a b c" {
		t.Fatal("Ctrl+Z did not undo desktop removal")
	}
}

func TestDesktopPlaylistConcurrentWriteRejected(t *testing.T) {
	m, p := desktopPlaylistTestModel(t)
	if err := p.SavePlaylist("Mix", []playlist.Track{{Path: "/a.mp3"}}); err != nil {
		t.Fatal(err)
	}
	first := v2Request(t, "playlist.prepend", ipc.Request{Provider: "local", Playlist: "Mix", Tracks: []ipc.TrackInfo{{Path: "/b.mp3"}}})
	updated, cmd := m.Update(first)
	m = updated.(Model)
	if cmd == nil {
		t.Fatal("expected deferred edit")
	}
	if result := runV2(t, &m, "playlist.delete", ipc.Request{Provider: "local", Playlist: "Mix"}); result.Error != ipc.V2ErrorCodeConflict {
		t.Fatalf("overlapping edit = %+v", result)
	}
	updated, _ = m.Update(cmd())
	m = updated.(Model)
	job, _ := first.Jobs.Get(first.JobID)
	if job.State != ipc.JobSucceeded {
		t.Fatalf("first edit = %+v", job)
	}
}

func TestDesktopBatchRemovalIsAtomicAndUndoable(t *testing.T) {
	for _, op := range []string{"queue.remove_many", "playnext.remove_many", "playlist.remove_many"} {
		t.Run(op, func(t *testing.T) {
			m, p, _ := queueOpModel(t, false, "Mix", 1)
			m.playlist.Queue(0)
			m.playlist.Queue(1)
			m.playlist.Queue(2)
			request := ipc.Request{Provider: "local", Playlist: "Mix", Indexes: []int{0, 2}, Revision: m.playlist.Revision(),
				Tracks: []ipc.TrackInfo{{Path: "/music/a.mp3"}, {Path: "/music/c.mp3"}}}
			if result := runV2(t, &m, op, request); !result.OK {
				t.Fatal(result)
			}
			if op == "playlist.remove_many" {
				tracks, _ := p.Tracks("Mix")
				if queueOpPaths(tracks) != "b" {
					t.Fatalf("remaining saved tracks = %v", tracks)
				}
				if result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Mix"}); !result.OK {
					t.Fatal(result)
				}
				tracks, _ = p.Tracks("Mix")
				if queueOpPaths(tracks) != "a b c" {
					t.Fatal("saved undo lost batch members")
				}
			} else {
				if result := runV2(t, &m, "queue.undo", ipc.Request{Revision: m.playlist.Revision()}); !result.OK {
					t.Fatal(result)
				}
				if queueOpPaths(m.playlist.Tracks()) != "a b c" || m.playlist.QueueLen() != 3 {
					t.Fatal("undo lost live/play-next batch state")
				}
			}
		})
	}
	m, p, _ := queueOpModel(t, false, "Mix", 0)
	before, _ := p.PlaylistDocument("Mix")
	result := runV2(t, &m, "playlist.remove_many", ipc.Request{Provider: "local", Playlist: "Mix",
		Indexes: []int{0, 2}, Tracks: []ipc.TrackInfo{{Path: "/music/a.mp3"}, {Path: "/changed.mp3"}}})
	if !strings.HasPrefix(result.Error, ipc.V2ErrorCodeConflict) {
		t.Fatalf("stale saved removal = %+v", result)
	}
	after, _ := p.PlaylistDocument("Mix")
	if !bytes.Equal(before, after) {
		t.Fatal("failed batch removed an earlier selected track")
	}
}

func TestDesktopServerSortHasNoWireBatchLimit(t *testing.T) {
	m, p := desktopPlaylistTestModel(t)
	tracks := make([]playlist.Track, 1200)
	for i := range tracks {
		tracks[i] = playlist.Track{Path: fmt.Sprintf("/track-%04d.mp3", 1200-i), Title: fmt.Sprintf("%04d", 1200-i)}
	}
	if err := p.SavePlaylist("Large", tracks); err != nil {
		t.Fatal(err)
	}
	before, _ := p.PlaylistDocument("Large")
	if result := runV2(t, &m, "playlist.sort", ipc.Request{Provider: "local", Playlist: "Large", Sort: "title"}); !result.OK {
		t.Fatal(result)
	}
	sorted, _ := p.Tracks("Large")
	if len(sorted) != 1200 || sorted[0].Title != "0001" || sorted[1199].Title != "1200" {
		t.Fatal("sort did not apply to entire saved playlist")
	}
	if result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Large"}); !result.OK {
		t.Fatal(result)
	}
	restored, _ := p.PlaylistDocument("Large")
	if !bytes.Equal(before, restored) {
		t.Fatal("large sort undo did not restore exact document")
	}
}

func TestDesktopEnqueuePreservesInputOrderAndSourceMetadata(t *testing.T) {
	m, _, _ := queueOpModel(t, false, "Mix", 0)
	request := ipc.Request{Tracks: []ipc.TrackInfo{
		{Path: "https://example.com/episode-one.mp3", ProviderMeta: map[string]string{"podcast": "one"}},
		{Path: "https://example.com/episode-two.mp3", ProviderMeta: map[string]string{"podcast": "two"}},
	}, Revision: m.playlist.Revision()}
	if result := runV2(t, &m, "tracks.enqueue", request); !result.OK {
		t.Fatal(result)
	}
	entries := m.playlist.QueueEntries()
	if len(entries) != 2 || entries[0].Track.ProviderMeta["podcast"] != "one" || entries[1].Track.ProviderMeta["podcast"] != "two" {
		t.Fatalf("queue = %+v", entries)
	}
}

func TestDesktopSaveQueueCapturesCompleteListWithoutOverwrite(t *testing.T) {
	m, p := desktopPlaylistTestModel(t)
	tracks := make([]playlist.Track, 1200)
	for i := range tracks {
		tracks[i] = playlist.Track{Path: fmt.Sprintf("/track-%d.flac", i), ProviderMeta: map[string]string{"provider": "kept"}}
	}
	m.playlist.Add(tracks...)
	request := ipc.Request{Provider: "local", Playlist: "Saved", Revision: m.playlist.Revision()}
	if result := runV2(t, &m, "playlist.save_queue", request); !result.OK {
		t.Fatal(result)
	}
	saved, err := p.Tracks("Saved")
	if err != nil || len(saved) != len(tracks) || saved[1199].ProviderMeta["provider"] != "kept" {
		t.Fatalf("saved %d, err %v", len(saved), err)
	}
	before, _ := p.PlaylistDocument("Saved")
	if result := runV2(t, &m, "playlist.save_queue", request); result.OK {
		t.Fatal("overwrote existing saved queue")
	}
	after, _ := p.PlaylistDocument("Saved")
	if !bytes.Equal(before, after) {
		t.Fatal("duplicate save modified original playlist")
	}
	if result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Saved"}); !result.OK {
		t.Fatal(result)
	}
	if _, err := p.PlaylistDocument("Saved"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("undo saved queue = %v", err)
	}
}

func TestDesktopPlaylistImportPreservesLiveQueueMetadataAndExactUndo(t *testing.T) {
	m, p := desktopPlaylistTestModel(t)
	original := []byte("# Keep the saved directory document.\n[[track]]\npath = \"/original.flac\"\ntitle = \"Original\"\n\n[[dir]]\npath = \"/music/source\"\nrecursive = false\n")
	if err := p.RestorePlaylistDocument("Mix", original); err != nil {
		t.Fatal(err)
	}
	m.playlist.Add(playlist.Track{Path: "/playing.flac", Title: "Playing", ProviderMeta: map[string]string{"id": "live"}})
	m.playlist.Queue(0)
	m.loadedPlaylist, m.playlistSource = "Live", "Existing source"
	live, revision := m.playlist.Snapshot(), m.playlist.Revision()
	var source strings.Builder
	source.WriteString("#EXTM3U\n")
	for i := range 1200 {
		fmt.Fprintf(&source, "#EXTINF:123,Imported title %d\nhttps://example.com/%d.flac\n", i, i)
	}
	path := filepath.Join(t.TempDir(), "Selected collection.m3u8")
	if err := os.WriteFile(path, []byte(source.String()), 0o600); err != nil {
		t.Fatal(err)
	}
	if result := runV2(t, &m, "playlist.import", ipc.Request{Provider: "local", Playlist: "Mix", Args: []string{path}}); !result.OK {
		t.Fatal(result)
	}
	saved, err := p.Tracks("Mix")
	if err != nil || len(saved) != 1201 {
		t.Fatalf("saved tracks = %d, error %v", len(saved), err)
	}
	last := saved[len(saved)-1]
	if last.Title != "Imported title 1199" || last.DurationSecs != 123 || !last.Stream || last.Realtime {
		t.Fatalf("imported metadata = %+v", last)
	}
	dirs, err := p.DirSources("Mix")
	if err != nil || len(dirs) != 1 || dirs[0].Path != "/music/source" || dirs[0].Recursive {
		t.Fatalf("directory sources = %+v, error %v", dirs, err)
	}
	if !reflect.DeepEqual(live, m.playlist.Snapshot()) || revision != m.playlist.Revision() || m.loadedPlaylist != "Live" || m.playlistSource != "Existing source" {
		t.Fatal("saved import modified live playback or source state")
	}
	if result := runV2(t, &m, "playlist.undo", ipc.Request{Provider: "local", Playlist: "Mix"}); !result.OK {
		t.Fatal(result)
	}
	actual, err := p.PlaylistDocument("Mix")
	if err != nil || !bytes.Equal(actual, original) {
		t.Fatalf("undo did not restore exact document: %q, %v", actual, err)
	}
	if !reflect.DeepEqual(live, m.playlist.Snapshot()) || revision != m.playlist.Revision() {
		t.Fatal("saved import undo modified live queue")
	}
}

func TestDesktopPlaylistImportResolvesAllSourcesBeforeWriting(t *testing.T) {
	m, p := desktopPlaylistTestModel(t)
	if err := p.SavePlaylist("Mix", []playlist.Track{{Path: "/original.mp3"}}); err != nil {
		t.Fatal(err)
	}
	original, _ := p.PlaylistDocument("Mix")
	dir := t.TempDir()
	first := filepath.Join(dir, "First file.mp3")
	if err := os.WriteFile(first, []byte{}, 0o600); err != nil {
		t.Fatal(err)
	}
	result := runV2(t, &m, "playlist.import", ipc.Request{Provider: "local", Playlist: "Mix", Args: []string{first, filepath.Join(dir, "missing.m3u")}})
	if result.OK {
		t.Fatal("import with an unreadable source succeeded")
	}
	actual, _ := p.PlaylistDocument("Mix")
	if !bytes.Equal(actual, original) {
		t.Fatal("partial resolution changed the saved playlist")
	}
	if _, exists := m.desktopPlaylistState().undo[playlistDesktopKey("local", "Mix")]; exists {
		t.Fatal("failed import replaced undo history")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := resolveDesktopPlaylistImport(ctx, []string{first}); !errors.Is(err, context.Canceled) {
		t.Fatalf("canceled import = %v", err)
	}
	if desktopPlaylistCapabilities(p)["import"] != true {
		t.Fatal("local provider did not advertise imports")
	}
}
