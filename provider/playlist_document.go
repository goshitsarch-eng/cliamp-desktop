package provider

import "errors"

// ErrPlaylistDocumentChanged means a guarded restore found a newer write.
var ErrPlaylistDocumentChanged = errors.New("playlist document changed")

// PlaylistDocumentRestorer guards compare-and-restore with the provider's
// write lock. It prevents a concurrent writer from being overwritten by undo.
type PlaylistDocumentRestorer interface {
	RestorePlaylistDocumentIfUnchanged(name string, expected []byte, expectedExists bool, restored []byte, restoredExists bool) error
}
