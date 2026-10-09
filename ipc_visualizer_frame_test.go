package main

import (
	"context"
	"encoding/json"
	"testing"

	tea "charm.land/bubbletea/v2"
	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/ui/model"
)

func TestDirectVisualizerFramesDoNotUseJobCapacity(t *testing.T) {
	jobs := ipc.NewJobStore(ipc.WithJobStoreCapacity(1))
	retained, err := jobs.Create("provider.load")
	if err != nil {
		t.Fatal(err)
	}
	frames := 0
	dispatcher := newV2Dispatcher(func(message tea.Msg) {
		request := message.(model.V2RequestMsg)
		if request.JobID != "" || request.Jobs != nil {
			t.Fatal("frame allocated an operation job")
		}
		if request.Request.Width != 100 || request.Request.Height != 30 {
			t.Fatal("lost frame dimensions")
		}
		frames++
		request.Reply <- model.V2RequestResult{Result: ipc.V2Result{Result: json.RawMessage(`{"ok":true,"frame":"frame"}`)}}
	}, jobs, nil)
	for range 300 {
		response, err := dispatcher.DispatchV2(context.Background(), ipc.V2Request{Method: "visualizer.frame", Width: 100, Height: 30})
		if err != nil || response.Job != nil || len(response.Result) == 0 {
			t.Fatalf("frame result = %+v, error = %v", response, err)
		}
	}
	if frames != 300 {
		t.Fatalf("frames = %d", frames)
	}
	if job, ok := jobs.Get(retained.ID); !ok || job.State != ipc.JobQueued {
		t.Fatal("frames disturbed retained operation")
	}
}
