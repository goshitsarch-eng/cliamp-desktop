package main

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/bjarneo/cliamp/ipc"
)

func TestDesktopPluginKeysCanListDispatchAndRejectUnknown(t *testing.T) {
	plugins := newTestPlugins(t, map[string]string{"desktopkeys": `
 local p=plugin.register({name="Desktop Keys",type="hook",permissions={"keymap"}})
 local count=0
 p:bind("ctrl+alt+j","Increment",function() count=count+1 end)
 p:command("count",function() return tostring(count) end)
 `})
	jobs := ipc.NewJobStore()
	t.Cleanup(jobs.CancelAll)
	run := func(op, params string) ipc.Job {
		t.Helper()
		job, err := jobs.Create(op)
		if err != nil {
			t.Fatal(err)
		}
		runV2PluginJob(jobs, job.ID, ipc.V2Request{Operation: op, Params: json.RawMessage(params)}, plugins)
		got, _ := jobs.Get(job.ID)
		return got
	}
	listed := run("plugin.keys", `{}`)
	var result struct {
		Bindings []struct{ Key, Plugin, Description string }
	}
	if err := json.Unmarshal(listed.Result, &result); err != nil {
		t.Fatal(err)
	}
	if listed.State != ipc.JobSucceeded || len(result.Bindings) != 1 || result.Bindings[0].Description != "Increment" {
		t.Fatalf("list: %+v, %s", listed, listed.Result)
	}
	dispatched := run("plugin.key", `{"name":"CTRL+ALT+J"}`)
	if dispatched.State != ipc.JobSucceeded {
		t.Fatalf("dispatch: %+v", dispatched)
	}
	// A keyboard action is queued asynchronously, just as in the terminal.
	deadline := time.Now().Add(2 * time.Second)
	for {
		counted := run("plugin.call", `{"name":"Desktop Keys","sub":"count"}`)
		var response ipc.Response
		if err := json.Unmarshal(counted.Result, &response); err != nil {
			t.Fatal(err)
		}
		if response.Output == "1" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("keyboard callback did not run: %+v", counted)
		}
		time.Sleep(time.Millisecond)
	}
	unknown := run("plugin.key", `{"name":"unknown"}`)
	if unknown.Error == nil || unknown.Error.Code != ipc.V2ErrorCodeNotFound {
		t.Fatalf("unknown: %+v", unknown)
	}
	invalid := run("plugin.key", `{}`)
	if invalid.Error == nil || invalid.Error.Code != ipc.V2ErrorCodeInvalidParams {
		t.Fatalf("invalid: %+v", invalid)
	}
}
