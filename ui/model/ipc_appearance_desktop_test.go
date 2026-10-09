package model

import (
	"encoding/json"
	"github.com/bjarneo/cliamp/ipc"
	"testing"
)

func TestDesktopPreviewDoesNotPersistAndCancelRestores(t *testing.T) {
	m := newHeadlessModel(t, &headlessEngine{}, nil)
	saver := &recordingSaver{}
	m.configSaver = saver
	originalTheme := m.ThemeName()
	originalMode := int(m.vis.Mode)
	if r := runV2(t, &m, "desktop.vis.preview", ipc.Request{Index: 1}); !r.OK {
		t.Fatal(r)
	}
	if int(m.vis.Mode) != 1 {
		t.Fatal("preview did not change renderer")
	}
	if len(saver.saved) != 0 {
		t.Fatalf("preview persisted: %v", saver.saved)
	}
	msg := v2Request(t, "desktop.vis.preview", ipc.Request{})
	msg.Request.Params, _ = json.Marshal(map[string]int{"index": originalMode})
	next, _ := m.Update(msg)
	m = next.(Model)
	job, _ := msg.Jobs.Get(msg.JobID)
	if job.State != ipc.JobSucceeded {
		t.Fatalf("restore: %+v", job)
	}
	if int(m.vis.Mode) != originalMode {
		t.Fatal("cancel did not restore mode")
	}
	if r := runV2(t, &m, "desktop.theme.preview", ipc.Request{Name: originalTheme}); !r.OK {
		t.Fatal(r)
	}
	if len(saver.saved) != 0 {
		t.Fatalf("cancel persisted: %v", saver.saved)
	}
	if r := runV2(t, &m, "desktop.vis", ipc.Request{Index: 1}); !r.OK {
		t.Fatal(r)
	}
	if saver.saved["visualizer"] == "" {
		t.Fatal("commit did not persist")
	}
}
