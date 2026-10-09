package model

import (
	"encoding/json"
	"testing"

	"github.com/bjarneo/cliamp/ipc"
)

func TestDirectVisualizerFrameRendersWithoutJobStore(t *testing.T) {
	m := newHeadlessModel(t, &headlessEngine{tone: true}, nil)
	originalCols, originalRows := m.vis.Cols, m.vis.Rows
	for _, size := range []struct{ width, height int }{{80, 20}, {100, 30}, {0, 0}} {
		reply := make(chan V2RequestResult, 1)
		m.handleV2Request(V2RequestMsg{Request: ipc.V2Request{Method: "visualizer.frame", Width: size.width, Height: size.height}, Reply: reply})
		result := <-reply
		var response ipc.Response
		if result.Error != nil {
			t.Fatal(result.Error)
		}
		if err := json.Unmarshal(result.Result.Result, &response); err != nil {
			t.Fatal(err)
		}
		if !response.OK || response.Width == 0 || response.Height == 0 || response.Frame == "" {
			t.Fatalf("frame = %+v", response)
		}
		if m.vis.Cols != originalCols || m.vis.Rows != originalRows {
			t.Fatal("frame changed TUI dimensions")
		}
	}
	reply := make(chan V2RequestResult, 1)
	m.handleV2Request(V2RequestMsg{Request: ipc.V2Request{Method: "visualizer.frame", Width: 241, Height: 20}, Reply: reply})
	if result := <-reply; result.Error == nil || result.Error.Code != ipc.V2ErrorCodeInvalidParams {
		t.Fatalf("oversized frame = %+v", result)
	}
}
