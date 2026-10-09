package model

import (
	"encoding/json"

	tea "charm.land/bubbletea/v2"
	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/theme"
	"github.com/bjarneo/cliamp/ui"
)

// Preview changes the shared renderer without writing settings. The desktop
// picker restores its captured choice on cancel and uses the regular setters
// to commit, as the terminal pickers do.
func (m *Model) handleV2AppearancePreview(msg V2RequestMsg, request ipc.Request) tea.Cmd {
	if request.Cmd == "desktop.theme.preview" {
		m.themes = theme.LoadAll()
		if !m.SetTheme(request.Name) {
			m.failV2Job(msg.Jobs, msg.JobID, v2NotFoundError())
			return nil
		}
	} else {
		var params struct {
			Index *int `json:"index"`
		}
		if json.Unmarshal(msg.Request.Params, &params) != nil || params.Index == nil {
			m.failV2Job(msg.Jobs, msg.JobID, v2InvalidParamsError())
			return nil
		}
		m.activateDesktopVisualizer()
		if m.vis == nil {
			m.failV2Job(msg.Jobs, msg.JobID, v2UnavailableError())
			return nil
		}
		if *params.Index < 0 || *params.Index >= len(m.vis.AllModeNames()) {
			m.failV2Job(msg.Jobs, msg.JobID, v2InvalidParamsError())
			return nil
		}
		m.vis.SetMode(ui.VisMode(*params.Index))
		m.refreshChrome()
		m.applyHeightMode()
	}
	m.completeV2Job(msg.Jobs, msg.JobID, ipc.Response{OK: true, Theme: m.runtimeSnapshot().Theme})
	return nil
}
