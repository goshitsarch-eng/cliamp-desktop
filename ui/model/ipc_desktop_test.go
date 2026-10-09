package model

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/charmbracelet/x/ansi"

	"github.com/bjarneo/cliamp/internal/playback"
	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
	"github.com/bjarneo/cliamp/theme"
	"github.com/bjarneo/cliamp/ui"
)

type desktopAuthProvider struct {
	commandsTestProvider
	called int
	err    error
}

func (p *desktopAuthProvider) Authenticate() error {
	p.called++
	return p.err
}

// Sign-in is independent of the selected TUI provider. A URL can arrive while
// the job runs, and canceling its IPC job must not permit overlapping flows.
func TestDesktopProviderAuthLifecycle(t *testing.T) {
	for _, tc := range []struct {
		name   string
		err    error
		cancel bool
		state  string
	}{
		{name: "success", state: "authenticated"},
		{name: "failure", err: errors.New("authorization denied"), state: "failed"},
		{name: "canceled job with successful provider flow", cancel: true, state: "authenticated"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			p := &desktopAuthProvider{commandsTestProvider: commandsTestProvider{name: "Remote"}, err: tc.err}
			local := commandsTestProvider{name: "Local"}
			m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{
				{Key: "local", Name: "Local", Provider: local},
				{Key: "remote", Name: "Remote", Provider: p},
			})
			broker := ipc.NewBroker()
			m.SetIPCBroker(broker)
			sub, err := broker.Subscribe([]string{"provider.auth"})
			if err != nil {
				t.Fatal(err)
			}
			defer sub.Close()
			status := runV2(t, &m, "provider.auth.status", ipc.Request{Provider: "remote"})
			if !status.OK || status.Auth == nil || status.Auth.State != "idle" {
				t.Fatalf("initial status = %+v", status)
			}
			list := runV2(t, &m, "provider.list", ipc.Request{})
			if len(list.Providers) != 2 || list.Providers[0].Authenticatable || !list.Providers[1].Authenticatable {
				t.Fatalf("providers = %+v", list.Providers)
			}

			request := v2Request(t, "provider.auth", ipc.Request{Provider: "remote"})
			next, cmd := m.Update(request)
			m = next.(Model)
			if cmd == nil {
				t.Fatal("sign-in returned no command")
			}
			if tc.cancel {
				if err := request.Jobs.Cancel(request.JobID); err != nil {
					t.Fatal(err)
				}
			}
			duplicate := runV2(t, &m, "provider.auth", ipc.Request{Provider: "remote"})
			if duplicate.Error != ipc.V2ErrorCodeConflict {
				t.Fatalf("duplicate request = %+v", duplicate)
			}
			const signInURL = "https://example.com/authorize?state=test"
			next, _ = m.Update(ProvAuthURLMsg{ProviderName: "Remote", URL: signInURL})
			m = next.(Model)
			status = runV2(t, &m, "provider.auth.status", ipc.Request{Provider: "remote"})
			if status.Auth == nil || status.Auth.State != "authenticating" || status.Auth.URL != signInURL {
				t.Fatalf("running status = %+v", status.Auth)
			}
			// Neither URL nor completion needs the TUI provider pane to load.
			if m.provPane.authURL != "" || m.provPane.loading {
				t.Fatal("desktop sign-in changed TUI provider pane")
			}
			next, _ = m.Update(cmd())
			m = next.(Model)
			status = runV2(t, &m, "provider.auth.status", ipc.Request{Provider: "remote"})
			if status.Auth == nil || status.Auth.State != tc.state || status.Auth.URL != "" || p.called != 1 {
				t.Fatalf("finished status = %+v, calls = %d", status.Auth, p.called)
			}
			job, _ := request.Jobs.Get(request.JobID)
			wantJob := ipc.JobSucceeded
			if tc.err != nil {
				wantJob = ipc.JobFailed
			}
			if tc.cancel {
				wantJob = ipc.JobCanceled
			}
			if job.State != wantJob {
				t.Fatalf("job state = %s, want %s", job.State, wantJob)
			}
			for _, wantState := range []string{"authenticating", "authenticating", tc.state} {
				select {
				case event := <-sub.Events():
					var response ipc.Response
					if err := json.Unmarshal(event.Data, &response); err != nil {
						t.Fatal(err)
					}
					if response.Auth == nil || response.Auth.State != wantState {
						t.Fatalf("auth event = %+v, want %s", response.Auth, wantState)
					}
				default:
					t.Fatalf("missing %s auth event", wantState)
				}
			}
		})
	}
}

func TestDesktopProviderAuthInvalidTargets(t *testing.T) {
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{
		{Key: "local", Name: "Local", Provider: commandsTestProvider{name: "Local"}},
	})
	for _, tc := range []struct {
		provider string
		code     string
	}{
		{provider: "", code: ipc.V2ErrorCodeInvalidParams},
		{provider: "missing", code: ipc.V2ErrorCodeNotFound},
		{provider: "local", code: ipc.V2ErrorCodeUnavailable},
	} {
		for _, op := range []string{"provider.auth", "provider.auth.status"} {
			if response := runV2(t, &m, op, ipc.Request{Provider: tc.provider}); response.Error != tc.code {
				t.Fatalf("%s(%q) = %+v, want %s", op, tc.provider, response, tc.code)
			}
		}
	}
}

type desktopLuaHost struct {
	rows, cols int
	renders    int
}

func (h *desktopLuaHost) InitVis(string, int, int) {}
func (h *desktopLuaHost) DestroyVis(string)        {}
func (h *desktopLuaHost) RenderVis(_ string, _ [ui.DefaultSpectrumBands]float64, rows, cols int, _ uint64) string {
	h.rows, h.cols = rows, cols
	h.renders++
	return "\x1b[38;2;20;40;60mLua visualizer\x1b[0m"
}

func TestDesktopVisualizerFramesPreserveBuiltinsAndLua(t *testing.T) {
	engine := &headlessEngine{tone: true}
	engine.playing = true
	m := newHeadlessModel(t, engine, nil, playlist.Track{Path: "/music/tone.flac"})
	host := &desktopLuaHost{}
	m.RegisterLuaVisualizers([]string{"desktop-test-lua"}, host)
	list := runV2(t, &m, "desktop.vis", ipc.Request{Name: "list"})
	if !list.OK || !slices.Contains(list.Items, "desktop-test-lua") || len(list.Items) != len(ui.VisModeNames())+1 {
		t.Fatalf("visualizers = %+v", list)
	}
	for _, name := range list.Items {
		t.Run(name, func(t *testing.T) {
			if response := runV2(t, &m, "desktop.vis", ipc.Request{Name: name}); !response.OK {
				t.Fatalf("select %s = %+v", name, response)
			}
			oldCols, oldRows := m.vis.Cols, m.vis.Rows
			response := runV2(t, &m, "desktop.vis.frame", ipc.Request{Width: 48, Height: 12})
			if !response.OK || response.Visualizer != name || response.Width != 48 || response.Height != 12 {
				t.Fatalf("frame metadata = %+v", response)
			}
			if m.vis.Cols != oldCols || m.vis.Rows != oldRows {
				t.Fatalf("frame changed terminal geometry from %dx%d to %dx%d", oldCols, oldRows, m.vis.Cols, m.vis.Rows)
			}
			if m.vis.Mode == ui.VisNone {
				if response.Frame != "" {
					t.Fatal("disabled visualizer returned a frame")
				}
				return
			}
			lines := strings.Split(ansi.Strip(response.Frame), "\n")
			if len(lines) != 12 {
				t.Fatalf("frame rows = %d, want 12", len(lines))
			}
			for _, line := range lines {
				if width := ansi.StringWidth(line); width != 48 {
					t.Fatalf("frame line width = %d, want 48", width)
				}
			}
			if name == "desktop-test-lua" && (!strings.Contains(response.Frame, "Lua visualizer") || host.renders == 0 || host.cols != 48 || host.rows != 12) {
				t.Fatalf("Lua renderer = %+v, frame = %q", host, response.Frame)
			}
		})
	}
}

func TestDesktopAppearanceRestoresSavedVisualizerAndTheme(t *testing.T) {
	m := newHeadlessModel(t, &headlessEngine{}, nil)
	m.SetDesktopVisualizer("Wave")
	if m.VisualizerName() == "Wave" {
		t.Fatal("saved desktop visualizer changed ordinary daemon")
	}
	list := runV2(t, &m, "desktop.vis", ipc.Request{Name: "list"})
	if list.Visualizer != "Wave" {
		t.Fatalf("desktop did not restore saved visualizer: %+v", list)
	}
	saver := &recordingSaver{}
	m.configSaver = saver
	t.Cleanup(func() { applyThemeAll(theme.Default()) })
	if response := runV2(t, &m, "desktop.theme", ipc.Request{Name: "dracula"}); !response.OK {
		t.Fatalf("theme = %+v", response)
	}
	if saver.saved["theme"] != `"dracula"` {
		t.Fatalf("saved theme = %v", saver.saved)
	}
	response := runV2(t, &m, "desktop.vis.frame", ipc.Request{})
	if response.Width != 80 || response.Height != 20 || response.Theme == nil || !strings.EqualFold(response.Theme.Name, "dracula") || response.Theme.Accent == "" {
		t.Fatalf("frame theme/default size = %+v", response)
	}
	for _, size := range []ipc.Request{{Width: -1}, {Width: 241}, {Height: -1}, {Height: 81}} {
		if response := runV2(t, &m, "desktop.vis.frame", size); response.Error != ipc.V2ErrorCodeInvalidParams {
			t.Fatalf("invalid dimensions %+v = %+v", size, response)
		}
	}
}

func TestDesktopVisualizerFrameSamplesWhileTerminalVisualizerHidden(t *testing.T) {
	engine := &headlessEngine{tone: true}
	engine.playing = true
	m := newHeadlessModel(t, engine, nil)
	m.simplified = true
	if m.visualizerVisible() {
		t.Fatal("terminal visualizer should be hidden")
	}
	response := runV2(t, &m, "desktop.vis.frame", ipc.Request{})
	if !response.OK || slices.Max(m.vis.SmoothedBands()) <= 0 {
		t.Fatal("desktop frame failed to analyze audio with the terminal visualizer hidden")
	}
}

type desktopGroupedAuthProvider struct {
	desktopAuthProvider
}

func (*desktopGroupedAuthProvider) AuthenticationGroup() string { return "shared" }

func TestDesktopProviderAuthSharesAliasesAndTUI(t *testing.T) {
	video := &desktopGroupedAuthProvider{desktopAuthProvider: desktopAuthProvider{commandsTestProvider: commandsTestProvider{name: "Video"}}}
	music := &desktopGroupedAuthProvider{desktopAuthProvider: desktopAuthProvider{commandsTestProvider: commandsTestProvider{name: "Music"}}}
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{
		{Key: "video", Name: "Video", Provider: video},
		{Key: "music", Name: "Music", Provider: music},
	})
	request := v2Request(t, "provider.auth", ipc.Request{Provider: "video"})
	next, command := m.Update(request)
	m = next.(Model)
	if command == nil {
		t.Fatal("missing desktop sign-in command")
	}
	if response := runV2(t, &m, "provider.auth", ipc.Request{Provider: "music"}); response.Error != ipc.V2ErrorCodeConflict {
		t.Fatalf("concurrent alias sign-in = %+v", response)
	}
	status := runV2(t, &m, "provider.auth.status", ipc.Request{Provider: "music"})
	if status.Auth == nil || status.Auth.State != "authenticating" || status.Auth.Provider != "music" {
		t.Fatalf("alias status = %+v", status.Auth)
	}
	m.provider = music
	if cmd := m.startTUIProviderAuth(music); cmd != nil {
		t.Fatal("TUI started overlapping alias sign-in")
	}
	next, _ = m.Update(command())
	m = next.(Model)
	command = m.startTUIProviderAuth(music)
	if command == nil {
		t.Fatal("TUI could not start after desktop flow completed")
	}
	if response := runV2(t, &m, "provider.auth", ipc.Request{Provider: "video"}); response.Error != ipc.V2ErrorCodeConflict {
		t.Fatalf("desktop overlapped TUI sign-in: %+v", response)
	}
	// Switching panes invalidates TUI generation but must still release the
	// shared sign-in when the original provider completes.
	m.provider = video
	nextRequest(&m.requests.auth)
	next, _ = m.Update(command())
	m = next.(Model)
	status = runV2(t, &m, "provider.auth.status", ipc.Request{Provider: "video"})
	if status.Auth == nil || status.Auth.State != "authenticated" {
		t.Fatalf("completed TUI alias status = %+v", status.Auth)
	}
	if video.called != 1 || music.called != 1 {
		t.Fatalf("authentication calls = %d video, %d music", video.called, music.called)
	}
}

func TestDesktopVisualizerIndexSelectsCollidingLuaName(t *testing.T) {
	m := newHeadlessModel(t, &headlessEngine{}, nil)
	host := &desktopLuaHost{}
	m.RegisterLuaVisualizers([]string{"Bars"}, host)
	response := runV2(t, &m, "desktop.vis", ipc.Request{Index: int(ui.VisCount)})
	if !response.OK || response.Index != int(ui.VisCount) || m.vis.Mode != ui.VisCount {
		t.Fatalf("select Lua Bars by index = %+v", response)
	}
	frame := runV2(t, &m, "desktop.vis.frame", ipc.Request{})
	if !strings.Contains(frame.Frame, "Lua visualizer") {
		t.Fatal("duplicate Lua name rendered the built-in visualizer")
	}
	// The existing Request adapter omits zero indexes; explicitly send 0 to
	// verify selecting the first row is distinct from a missing parameter.
	request := v2Request(t, "desktop.vis", ipc.Request{})
	request.Request.Params = json.RawMessage(`{"index":0}`)
	next, _ := m.Update(request)
	m = next.(Model)
	job, _ := request.Jobs.Get(request.JobID)
	if job.State != ipc.JobSucceeded || m.vis.Mode != ui.VisBars {
		t.Fatalf("select index zero = %s, mode %v", job.State, m.vis.Mode)
	}
	for _, params := range []ipc.Request{{Index: int(ui.VisCount) + 1}, {Index: 1, Name: "Bars"}} {
		if response := runV2(t, &m, "desktop.vis", params); response.Error != ipc.V2ErrorCodeInvalidParams {
			t.Fatalf("invalid index request %+v = %+v", params, response)
		}
	}
}

func TestDesktopQuitPreservesResume(t *testing.T) {
	engine := &headlessEngine{}
	engine.playing = true
	engine.position = 42 * time.Second
	m := newHeadlessModel(t, engine, nil, playlist.Track{Path: "/music/track.flac"})
	request := v2Request(t, "desktop.quit", ipc.Request{})
	next, command := m.Update(request)
	m = next.(Model)
	job, _ := request.Jobs.Get(request.JobID)
	if job.State != ipc.JobSucceeded || command == nil || m.quitting {
		t.Fatalf("quit acknowledgement = %s, command absent %v, quitting %v", job.State, command == nil, m.quitting)
	}
	quit := command()
	if _, ok := quit.(playback.QuitMsg); !ok {
		t.Fatalf("quit command = %T", quit)
	}
	next, command = m.Update(quit)
	m = next.(Model)
	if !m.quitting || m.exitResume.secs != 42 || command == nil {
		t.Fatalf("graceful quit: quitting=%v resume=%+v", m.quitting, m.exitResume)
	}
	if _, ok := command().(tea.QuitMsg); !ok {
		t.Fatal("graceful quit did not stop the event loop")
	}
}

func TestDesktopOpenLocalSourcesThroughURLLoad(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "nested"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, contents := range map[string]string{
		"song.mp3": "", "nested/track.flac": "", "ignore.txt": "ignored",
		"mix.m3u": "#EXTM3U\nsong.mp3\nnested/track.flac\n",
		"mix.pls": "[playlist]\nNumberOfEntries=2\nFile1=song.mp3\nFile2=nested/track.flac\nVersion=2\n",
	} {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(contents), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for _, tc := range []struct {
		name  string
		path  string
		count int
	}{
		{name: "file", path: filepath.Join(dir, "song.mp3"), count: 1},
		{name: "folder", path: dir, count: 2},
		{name: "M3U", path: filepath.Join(dir, "mix.m3u"), count: 2},
		{name: "PLS", path: filepath.Join(dir, "mix.pls"), count: 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			engine := &headlessEngine{}
			engine.playing = true
			m := newHeadlessModel(t, engine, nil, playlist.Track{Path: "/music/previous.flac"})
			response := runV2(t, &m, "url.load", ipc.Request{Path: tc.path, Play: true})
			if !response.OK || response.Total != tc.count || m.playlist.Len() != tc.count+1 || m.playlist.Index() != 1 {
				t.Fatalf("load local source = %+v, playlist len %d index %d", response, m.playlist.Len(), m.playlist.Index())
			}
			for _, track := range response.Tracks {
				if track.Path != filepath.Join(dir, "song.mp3") && track.Path != filepath.Join(dir, "nested", "track.flac") {
					t.Fatalf("unexpected loaded path %q", track.Path)
				}
			}
		})
	}
}
