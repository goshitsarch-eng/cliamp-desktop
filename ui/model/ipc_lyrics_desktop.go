package model

import (
	"encoding/json"
	"math"
	"time"

	tea "charm.land/bubbletea/v2"

	"github.com/bjarneo/cliamp/ipc"
)

// The offset is shared with terminal controls and persisted by the same saver.
// Omission is a read; an explicit zero resets the correction.
func (m *Model) handleV2LyricsOffset(msg V2RequestMsg) tea.Cmd {
	var params struct {
		Value *float64 `json:"value"`
	}
	if len(msg.Request.Params) > 0 && json.Unmarshal(msg.Request.Params, &params) != nil {
		m.failV2Job(msg.Jobs, msg.JobID, v2InvalidParamsError())
		return nil
	}
	if params.Value != nil {
		value := *params.Value
		if math.IsNaN(value) || math.IsInf(value, 0) || value != math.Trunc(value) || value < -10000 || value > 10000 {
			m.failV2Job(msg.Jobs, msg.JobID, v2InvalidParamsError())
			return nil
		}
		if err := m.saveConfigFloat("lyrics_offset_ms", value, 0); err != nil {
			m.completeV2Job(msg.Jobs, msg.JobID, ipc.Response{OK: false, Error: err.Error()})
			return nil
		}
		m.lyrics.offset = time.Duration(value) * time.Millisecond
	}
	m.completeV2Job(msg.Jobs, msg.JobID, struct {
		OK       bool  `json:"ok"`
		OffsetMS int64 `json:"offset_ms"`
	}{true, m.lyrics.offset.Milliseconds()})
	return nil
}
