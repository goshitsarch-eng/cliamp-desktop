package model

import (
	"context"
	"errors"
	"strings"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/ui"
)

type ipcDesktopState struct {
	initialVisualizer string
	auth              map[string]*ipcProviderAuthState
}

type ipcProviderAuthState struct {
	info         ipc.ProviderAuthInfo
	providerName string
	jobID        string
	running      bool
	tui          bool
	tuiGen       uint64
}

type ipcProviderAuthDoneMsg struct {
	group string
	jobs  *ipc.JobStore
	jobID string
	err   error
}

// SetDesktopVisualizer remembers the saved visualizer without changing the
// ordinary daemon's spectrum behavior. A desktop appearance request activates
// it after Lua visualizers have been registered.
func (m *Model) SetDesktopVisualizer(name string) {
	m.desktop.initialVisualizer = name
}

func (m *Model) activateDesktopVisualizer() {
	if m.vis != nil && m.desktop.initialVisualizer != "" {
		m.SetVisualizer(m.desktop.initialVisualizer)
		m.desktop.initialVisualizer = ""
	}
}

func (m *Model) handleV2DesktopVisualizer(jobs *ipc.JobStore, jobID string, request ipc.Request, index *int) tea.Cmd {
	m.activateDesktopVisualizer()
	if index == nil {
		return m.handleV2Visualizer(jobs, jobID, request)
	}
	if m.vis == nil {
		m.failV2Job(jobs, jobID, v2UnavailableError())
		return nil
	}
	if request.Name != "" || *index < 0 || *index >= len(m.vis.AllModeNames()) {
		m.failV2Job(jobs, jobID, v2InvalidParamsError())
		return nil
	}
	m.vis.SetMode(ui.VisMode(*index))
	m.refreshChrome()
	m.applyHeightMode()
	if err := m.saveVisualizerChoice(); err != nil {
		m.failV2Job(jobs, jobID, v2InternalError())
		return nil
	}
	m.completeV2Job(jobs, jobID, ipc.Response{OK: true, Visualizer: m.vis.ModeName(), Index: int(m.vis.Mode)})
	return nil
}

// handleV2VisualizerFrame uses the same renderer, audio analysis, animation,
// and Lua host as the terminal. Dimensions are terminal cells, not pixels.
// Restore the terminal layout after drawing so attached TUI clients keep
// their own geometry. The frame contains ANSI SGR styling and UTF-8 glyphs.
func (m *Model) handleV2VisualizerFrame(jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	response, err := m.visualizerFrame(request.Width, request.Height)
	if err != nil {
		m.failV2Job(jobs, jobID, err)
		return nil
	}
	m.completeV2Job(jobs, jobID, response)
	return nil
}

// visualizerFrame serves both the legacy job operation and the direct read
// method. Frequent frames must not occupy or evict finite operation-job records.
func (m *Model) visualizerFrame(width, height int) (ipc.Response, *ipc.V2Error) {
	if width < 0 || width > 240 || height < 0 || height > 80 {
		return ipc.Response{}, v2InvalidParamsError()
	}
	if width == 0 {
		width = 80
	}
	if height == 0 {
		height = 20
	}
	if m.vis == nil {
		return ipc.Response{}, v2UnavailableError()
	}
	m.activateDesktopVisualizer()
	oldCols, oldRows := m.vis.Cols, m.vis.Rows
	defer func() { m.vis.Cols, m.vis.Rows = oldCols, oldRows }()
	m.vis.Cols, m.vis.Rows = width, height
	ctx := m.visualizerTickContext(time.Now())
	// A graphical client can show a frame while an attached TUI has its
	// provider pane or a compact layout open. Its audio must remain live.
	if m.player != nil {
		ctx.Playing = m.player.IsPlaying() && !m.player.IsPaused()
		ctx.Paused = m.player.IsPlaying() && m.player.IsPaused()
	}
	m.vis.Tick(ctx)
	frame := m.vis.Render()
	return ipc.Response{
		OK: true, Frame: frame, Width: width, Height: height,
		Visualizer: m.vis.ModeName(), Index: int(m.vis.Mode), Theme: m.runtimeSnapshot().Theme,
	}, nil
}

func (m *Model) handleV2ProviderAuth(jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	if strings.TrimSpace(request.Provider) == "" {
		m.failV2Job(jobs, jobID, v2InvalidParamsError())
		return nil
	}
	entry, ok := m.ipcProvider(request.Provider)
	if !ok {
		m.failV2Job(jobs, jobID, v2NotFoundError())
		return nil
	}
	auth, ok := entry.Provider.(playlist.Authenticator)
	if !ok {
		m.failV2Job(jobs, jobID, v2UnavailableError())
		return nil
	}
	group := providerAuthGroup(entry.Provider)
	contextAuth, cancellable := entry.Provider.(playlist.ContextAuthenticator)
	state := m.desktop.auth[group]
	if request.Cmd == "provider.auth.status" {
		info := ipc.ProviderAuthInfo{Provider: entry.Key, State: "idle", Cancellable: cancellable}
		if state != nil {
			info = state.info
			info.Provider = entry.Key
		}
		m.completeV2Job(jobs, jobID, ipc.Response{OK: true, Auth: &info})
		return nil
	}
	if state != nil && state.running {
		m.failV2Job(jobs, jobID, v2ConflictError())
		return nil
	}
	if m.desktop.auth == nil {
		m.desktop.auth = make(map[string]*ipcProviderAuthState)
	}
	state = &ipcProviderAuthState{
		info:         ipc.ProviderAuthInfo{Provider: entry.Key, State: "authenticating", Cancellable: cancellable},
		providerName: entry.Provider.Name(), jobID: jobID, running: true,
	}
	m.desktop.auth[group] = state
	m.publishIPCProviderAuth(state.info)
	command := authenticateProviderCmd(auth, entry.Provider.Name(), 0)
	ctx, exists := jobs.Context(jobID)
	if !exists {
		m.failV2Job(jobs, jobID, v2NotFoundError())
		state.running = false
		return nil
	}
	return func() tea.Msg {
		if cancellable {
			return ipcProviderAuthDoneMsg{group: group, jobs: jobs, jobID: jobID, err: contextAuth.AuthenticateContext(ctx)}
		}
		// Legacy providers explicitly report cancellable=false. Keep their
		// busy state until Authenticate returns, even after job cancellation.
		result := command().(provAuthDoneMsg)
		return ipcProviderAuthDoneMsg{group: group, jobs: jobs, jobID: jobID, err: result.err}
	}
}

func (m *Model) handleIPCProviderAuthURL(msg ProvAuthURLMsg) {
	// The same OAuth observer can publish under several display names, as
	// YouTube does. Publish a shared group's URL once, under the initiating
	// provider's key.
	for _, state := range m.desktop.auth {
		if state.running && state.providerName == msg.ProviderName && state.info.URL != msg.URL {
			state.info.URL = msg.URL
			m.publishIPCProviderAuth(state.info)
		}
	}
}

func (m *Model) handleIPCProviderAuthDone(msg ipcProviderAuthDoneMsg) {
	state := m.desktop.auth[msg.group]
	if state == nil || state.jobID != msg.jobID {
		return
	}
	state.running = false
	state.info.URL = ""
	state.info.State = "authenticated"
	if errors.Is(msg.err, context.Canceled) {
		state.info.State = "canceled"
		_ = msg.jobs.Cancel(msg.jobID)
	} else if msg.err != nil {
		state.info.State = "failed"
		state.info.Error = msg.err.Error()
		err := v2InternalError()
		err.Detail = msg.err.Error()
		m.failV2Job(msg.jobs, msg.jobID, err)
	} else {
		m.completeV2Job(msg.jobs, msg.jobID, ipc.Response{OK: true, Auth: &state.info})
	}
	m.publishIPCProviderAuth(state.info)
}

func providerAuthGroup(p playlist.Provider) string {
	if grouped, ok := p.(playlist.AuthenticationGroupProvider); ok && grouped.AuthenticationGroup() != "" {
		return "group:" + grouped.AuthenticationGroup()
	}
	return "provider:" + p.Name()
}

// startTUIProviderAuth shares the busy state with graphical clients and other
// provider aliases. The actual TUI completion retains its generation checks.
func (m *Model) startTUIProviderAuth(auth playlist.Authenticator) tea.Cmd {
	group := providerAuthGroup(m.provider)
	if state := m.desktop.auth[group]; state != nil && state.running {
		m.status.Warning("Sign-in already in progress", statusTTLDefault)
		return nil
	}
	if m.desktop.auth == nil {
		m.desktop.auth = make(map[string]*ipcProviderAuthState)
	}
	key := m.provider.Name()
	for _, entry := range m.providers {
		if entry.Provider.Name() == m.provider.Name() {
			key = entry.Key
			break
		}
	}
	gen := nextRequest(&m.requests.auth)
	state := &ipcProviderAuthState{
		info:         ipc.ProviderAuthInfo{Provider: key, State: "authenticating"},
		providerName: m.provider.Name(), running: true, tui: true, tuiGen: gen,
	}
	m.desktop.auth[group] = state
	m.publishIPCProviderAuth(state.info)
	return authenticateProviderCmd(auth, m.provider.Name(), gen)
}

func (m *Model) handleIPCProviderTUIAuthDone(msg provAuthDoneMsg) {
	for _, state := range m.desktop.auth {
		if !state.running || !state.tui || state.providerName != msg.providerName || state.tuiGen != msg.gen {
			continue
		}
		state.running = false
		state.info.URL = ""
		state.info.State = "authenticated"
		if msg.err != nil {
			state.info.State = "failed"
			state.info.Error = msg.err.Error()
		}
		m.publishIPCProviderAuth(state.info)
	}
}

func (m *Model) publishIPCProviderAuth(info ipc.ProviderAuthInfo) {
	if m.ipcRuntime != nil && m.ipcRuntime.broker != nil {
		// Sign-in URLs are transient; status polling supplies the current
		// state to late subscribers without retaining a completed URL.
		_ = m.ipcRuntime.broker.Publish("provider.auth", marshalV2Result(ipc.Response{OK: true, Auth: &info}), false)
	}
}
