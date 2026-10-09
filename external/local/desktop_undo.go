package local

import (
	"bytes"
	"errors"
	"os"

	"github.com/bjarneo/cliamp/internal/fileutil"
	"github.com/bjarneo/cliamp/provider"
)

// RestorePlaylistDocumentIfUnchanged makes undo's stale-document check and
// restore one locked operation, including undoing create/delete.
func (p *Provider) RestorePlaylistDocumentIfUnchanged(name string, expected []byte, expectedExists bool, restored []byte, restoredExists bool) error {
	if err := writable(name); err != nil {
		return err
	}
	path, err := p.safePath(name)
	if err != nil {
		return err
	}
	unlock, err := p.lock()
	if err != nil {
		return err
	}
	defer unlock()
	current, err := os.ReadFile(path)
	exists := err == nil
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if exists != expectedExists || (exists && !bytes.Equal(current, expected)) {
		return provider.ErrPlaylistDocumentChanged
	}
	if !restoredExists {
		if !exists {
			return nil
		}
		return os.Remove(path)
	}
	if err := os.MkdirAll(p.dir, 0o755); err != nil {
		return err
	}
	return fileutil.WriteFileAtomicInExistingDir(path, restored, 0o644)
}
