// Package fileutil provides file operation utilities.
package fileutil

import (
	"fmt"
	"os"
)

// CopyFile streams src into dst. Failed copies preserve the existing destination.
// Saving to the source itself, including a hard link, leaves its contents intact.
func CopyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	source, err := in.Stat()
	if err != nil {
		return err
	}
	if !source.Mode().IsRegular() {
		return fmt.Errorf("copy %s: source is not a regular file", src)
	}
	mode := os.FileMode(0o666)
	if target, err := os.Stat(dst); err == nil {
		if os.SameFile(source, target) {
			return nil
		}
		if !target.Mode().IsRegular() {
			return fmt.Errorf("copy %s: destination is not a regular file", dst)
		}
		mode = target.Mode().Perm()
		// Honor existing write permissions before replacing the directory entry.
		existing, err := os.OpenFile(dst, os.O_WRONLY, 0)
		if err != nil {
			return err
		}
		if err := existing.Close(); err != nil {
			return err
		}
	} else if !os.IsNotExist(err) {
		return err
	}
	return replaceFileAtomic(dst, in, mode, false)
}
