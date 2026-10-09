package local

import (
	"bytes"
	"errors"
	"os"
	"testing"

	"github.com/bjarneo/cliamp/provider"
)

func TestGuardedDocumentUndoPreservesNewerWriter(t *testing.T) {
	t.Setenv("CLIAMP_CONFIG_DIR", t.TempDir())
	p := New(nil, nil)
	before := []byte("# before\n[[dir]]\npath=\"/music\"\n")
	after := []byte("# after\n[[dir]]\npath=\"/music\"\nrecursive=false\n")
	newer := []byte("# another writer\n[[dir]]\npath=\"/different\"\n")
	if err := p.RestorePlaylistDocument("Mix", newer); err != nil {
		t.Fatal(err)
	}
	if err := p.RestorePlaylistDocumentIfUnchanged("Mix", after, true, before, true); !errors.Is(err, provider.ErrPlaylistDocumentChanged) {
		t.Fatalf("restore = %v", err)
	}
	actual, _ := p.PlaylistDocument("Mix")
	if !bytes.Equal(actual, newer) {
		t.Fatal("guarded undo overwrote newer document")
	}
	if err := p.RestorePlaylistDocumentIfUnchanged("Mix", newer, true, before, true); err != nil {
		t.Fatal(err)
	}
	actual, _ = p.PlaylistDocument("Mix")
	if !bytes.Equal(actual, before) {
		t.Fatal("guarded undo did not preserve exact bytes")
	}
	if err := p.RestorePlaylistDocumentIfUnchanged("Mix", before, true, nil, false); err != nil {
		t.Fatal(err)
	}
	if _, err := p.PlaylistDocument("Mix"); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("undo create = %v", err)
	}
	if err := p.RestorePlaylistDocumentIfUnchanged("Mix", nil, false, before, true); err != nil {
		t.Fatal(err)
	}
}
