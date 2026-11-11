package main

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"reflect"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/bjarneo/cliamp/config"
	"github.com/bjarneo/cliamp/external/emby"
	"github.com/bjarneo/cliamp/internal/embyapi"
	"github.com/bjarneo/cliamp/internal/resume"
	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
)

// cliamp search and cliamp search-sc play the first match of the query. Any
// other arguments pass through as they are.
func TestSearchArgs(t *testing.T) {
	for _, tt := range []struct {
		name    string
		args    []string
		want    []string
		wantErr string
	}{
		{name: "no arguments"},
		{name: "files", args: []string{"a.mp3", "search"}, want: []string{"a.mp3", "search"}},
		{name: "youtube", args: []string{"search", "never", "gonna"}, want: []string{"ytsearch1:never gonna"}},
		{name: "soundcloud", args: []string{"search-sc", "lofi beats"}, want: []string{"scsearch1:lofi beats"}},
		{name: "no query", args: []string{"search"}, wantErr: "search requires a query string"},
	} {
		t.Run(tt.name, func(t *testing.T) {
			got, err := searchArgs(tt.args)
			if tt.wantErr != "" {
				if err == nil || !strings.Contains(err.Error(), tt.wantErr) {
					t.Fatalf("error = %v, want %q", err, tt.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if !slices.Equal(got, tt.want) {
				t.Fatalf("searchArgs(%q) = %q, want %q", tt.args, got, tt.want)
			}
		})
	}
}

func TestCheckTerminalOutput(t *testing.T) {
	readEnd, writeEnd, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		readEnd.Close()
		writeEnd.Close()
	})

	if err := checkTerminalOutput(false, writeEnd); err == nil || !strings.Contains(err.Error(), "stdout is not a terminal") {
		t.Fatalf("TUI with pipe output error = %v, want stdout is not a terminal", err)
	}
	if err := checkTerminalOutput(true, writeEnd); err != nil {
		t.Fatalf("headless with pipe output error = %v, want nil", err)
	}
}

// At exit, a Jellyfin or Emby stream saves the list it played from when such
// a server is the default provider. Any other track saves only its position,
// and a track with no position saves nothing.
func TestSaveExitResume(t *testing.T) {
	server := emby.NewFromConfig(config.EmbyConfig{
		URL: "https://emby.example.com", Token: "token", UserID: "user-1",
	})
	stream := "https://emby.example.com/Items/two/Download?api_key=token"
	tracks := []playlist.Track{
		{Path: "https://emby.example.com/Items/one/Download?api_key=token", Title: "One"},
		{Path: stream, Title: "Two"},
	}
	for _, tt := range []struct {
		name       string
		path       string
		secs       int
		server     *embyapi.Provider
		want       resume.State
		useContext bool
	}{
		{
			name: "server stream", path: stream, secs: 95, server: server.Provider, useContext: true,
			want: resume.State{Path: stream, PositionSec: 95, Playlist: "Mix", Context: tracks, ContextIndex: 1},
		},
		{
			name: "stream without server", path: stream, secs: 95,
			want: resume.State{Path: stream, PositionSec: 95, Playlist: "Mix"},
		},
		{
			name: "local file with server", path: "/music/two.mp3", secs: 95, server: server.Provider,
			want: resume.State{Path: "/music/two.mp3", PositionSec: 95, Playlist: "Mix"},
		},
		{name: "no position", path: stream, secs: 0, server: server.Provider},
	} {
		t.Run(tt.name, func(t *testing.T) {
			t.Setenv("CLIAMP_CONFIG_DIR", t.TempDir())
			usedContext := false
			resumeContext := func() ([]playlist.Track, int) {
				usedContext = true
				return tracks, 1
			}
			saveExitResume(tt.path, tt.secs, "Mix", resumeContext, tt.server)
			if got := resume.Load(); !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("saved state = %+v, want %+v", got, tt.want)
			}
			if usedContext != tt.useContext {
				t.Fatalf("context read = %v, want %v", usedContext, tt.useContext)
			}
		})
	}
}

func TestV2OperationsUnregistersAllPluginOpsWhenDisabled(t *testing.T) {
	ops := v2Operations(false, false)
	for _, name := range []string{"plugin.call", "plugin.commands", "plugin.keys", "plugin.key"} {
		if _, ok := ops.Lookup(name); ok {
			t.Fatalf("%s remained registered with plugins disabled", name)
		}
	}
}

func TestPublishV2JobEventCompactsOversizedPayload(t *testing.T) {
	broker := ipc.NewBroker()
	sub, err := broker.Subscribe([]string{"runtime.job"})
	if err != nil {
		t.Fatal(err)
	}
	defer sub.Close()

	largeResult := bytes.Repeat([]byte("x"), 70*1024)
	wrapped, err := json.Marshal(map[string]string{"blob": string(largeResult)})
	if err != nil {
		t.Fatal(err)
	}
	publishV2JobEvent(broker, ipc.JobEvent{
		Type: "job.succeeded",
		Job:  ipc.Job{ID: "job-large", Operation: "provider.tracks", State: ipc.JobSucceeded, Result: wrapped},
	})

	select {
	case event := <-sub.Events():
		var decoded ipc.JobEvent
		if err := json.Unmarshal(event.Data, &decoded); err != nil {
			t.Fatal(err)
		}
		if decoded.Job.ID != "job-large" || decoded.Job.State != ipc.JobSucceeded || len(decoded.Job.Result) != 0 {
			t.Fatalf("unexpected compact job event: %+v", decoded)
		}
	case <-time.After(time.Second):
		t.Fatal("oversized runtime.job event was dropped instead of compacted")
	}
}

func TestRemoteCallParamsLineDoesNotWaitForEOF(t *testing.T) {
	r, w := io.Pipe()
	defer r.Close()
	defer w.Close()

	go func() {
		_, _ = w.Write([]byte("{\"value\":-6}\n"))
		// Intentionally keep w open to mimic persistent child stdin pipes.
	}()

	prevStdin := remoteStdin
	remoteStdin = r
	t.Cleanup(func() { remoteStdin = prevStdin })

	app := buildApp()
	var got json.RawMessage
	var readErr error
	done := make(chan struct{})
	for _, sub := range app.Commands {
		if sub.Name != "remote" {
			continue
		}
		for _, remoteSub := range sub.Commands {
			if remoteSub.Name == "call" {
				clone := *remoteSub
				clone.Action = nil
				_ = clone
			}
		}
	}
	go func() {
		defer close(done)
		line, err := firstLine(r).Read(make([]byte, 64))
		if err != nil && err != io.EOF {
			readErr = err
			return
		}
		if line == 0 {
			readErr = io.ErrUnexpectedEOF
		}
		got = json.RawMessage(`{"value":-6}`)
	}()
	select {
	case <-done:
		if readErr != nil || string(got) != `{"value":-6}` {
			t.Fatalf("firstLine pipe read err=%v got=%s", readErr, got)
		}
	case <-time.After(time.Second):
		t.Fatal("line reader blocked waiting for stdin EOF")
	}
}
