package model

import (
	"context"
	"testing"
	"time"

	tea "charm.land/bubbletea/v2"
	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/provider"
)

type desktopContextAuthProvider struct {
	desktopAuthProvider
	started chan struct{}
}

func (p *desktopContextAuthProvider) AuthenticateContext(ctx context.Context) error {
	close(p.started)
	<-ctx.Done()
	return ctx.Err()
}

func TestDesktopProviderAuthJobCancellationStopsFlow(t *testing.T) {
	p := &desktopContextAuthProvider{
		desktopAuthProvider: desktopAuthProvider{commandsTestProvider: commandsTestProvider{name: "Remote"}},
		started:             make(chan struct{}),
	}
	m := newHeadlessModel(t, &headlessEngine{}, []provider.Entry{
		{Key: "remote", Name: "Remote", Provider: p},
	})
	status := runV2(t, &m, "provider.auth.status", ipc.Request{Provider: "remote"})
	if status.Auth == nil || !status.Auth.Cancellable {
		t.Fatalf("status = %+v", status.Auth)
	}
	request := v2Request(t, "provider.auth", ipc.Request{Provider: "remote"})
	next, cmd := m.Update(request)
	m = next.(Model)
	done := make(chan tea.Msg, 1)
	go func() { done <- cmd() }()
	select {
	case <-p.started:
	case <-time.After(time.Second):
		t.Fatal("provider sign-in did not start")
	}
	if err := request.Jobs.Cancel(request.JobID); err != nil {
		t.Fatal(err)
	}
	select {
	case message := <-done:
		next, _ = m.Update(message)
		m = next.(Model)
	case <-time.After(time.Second):
		t.Fatal("job cancellation did not stop sign-in")
	}
	status = runV2(t, &m, "provider.auth.status", ipc.Request{Provider: "remote"})
	if status.Auth == nil || status.Auth.State != "canceled" || status.Auth.URL != "" {
		t.Fatalf("finished status = %+v", status.Auth)
	}
	if p.called != 0 {
		t.Fatal("used legacy Authenticate despite context support")
	}
	// Cancellation must release the shared-provider lock for a later attempt.
	p.started = make(chan struct{})
	retry := v2Request(t, "provider.auth", ipc.Request{Provider: "remote"})
	next, cmd = m.Update(retry)
	m = next.(Model)
	if cmd == nil {
		t.Fatal("canceled sign-in kept provider locked")
	}
	if err := retry.Jobs.Cancel(retry.JobID); err != nil {
		t.Fatal(err)
	}
	next, _ = m.Update(cmd())
	m = next.(Model)
}
