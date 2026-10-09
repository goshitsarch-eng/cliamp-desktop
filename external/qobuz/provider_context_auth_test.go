package qobuz

import (
	"context"
	"errors"
	"testing"
	"time"
)

// A canceled desktop job must stop the actual callback/polling context, and a
// late successful callback must not install a session after cancellation.
func TestAuthenticateContextCancelsFlowAndRejectsLateSuccess(t *testing.T) {
	original := signIn
	t.Cleanup(func() { signIn = original })
	started := make(chan struct{})
	signIn = func(ctx context.Context) (*client, error) {
		close(started)
		<-ctx.Done()
		return &client{}, nil
	}
	p := New(27)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan error, 1)
	go func() { done <- p.AuthenticateContext(ctx) }()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("sign-in did not start")
	}
	cancel()
	select {
	case err := <-done:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("error = %v, want context.Canceled", err)
		}
	case <-time.After(time.Second):
		t.Fatal("sign-in did not stop after cancellation")
	}
	if p.client != nil {
		t.Fatal("canceled sign-in installed a session")
	}
	if err := p.AuthenticateContext(ctx); !errors.Is(err, context.Canceled) {
		t.Fatalf("pre-canceled context error = %v", err)
	}
}
