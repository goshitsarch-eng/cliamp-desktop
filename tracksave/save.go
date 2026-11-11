// Package tracksave persists downloaded tracks in the user's music directory.
package tracksave

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/bjarneo/cliamp/internal/fileutil"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/resolve"
)

// Directory resolves the configured directory, falling back to ~/Music/cliamp.
func Directory(directory string) (string, error) {
	if directory != "" {
		if !filepath.IsAbs(directory) {
			return "", fmt.Errorf("download directory must be an absolute path")
		}
		resolved, err := filepath.Abs(directory)
		if err != nil {
			return "", fmt.Errorf("resolve download directory: %w", err)
		}
		return resolved, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "Music", "cliamp"), nil
}

// SaveTo downloads or copies a track to the configured directory. A cancel of
// ctx stops a yt-dlp download.
func SaveTo(ctx context.Context, track playlist.Track, directory string) (string, error) {
	saveDir, err := Directory(directory)
	if err != nil {
		return "", err
	}
	if err := os.MkdirAll(saveDir, 0o755); err != nil {
		return "", err
	}
	if NeedsDownload(track) {
		return resolve.DownloadYTDLContext(ctx, track.Path, saveDir)
	}
	if track.Stream || !insideTempDir(track.Path) {
		return "", fmt.Errorf("only downloaded tracks can be saved")
	}
	name := track.Title
	if name == "" {
		name = strings.TrimSuffix(filepath.Base(track.Path), filepath.Ext(track.Path))
	}
	if track.Artist != "" {
		name = track.Artist + " - " + name
	}
	name = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return -1
		}
		if strings.ContainsRune(`/\\:*?"<>|`, r) {
			return '_'
		}
		return r
	}, name)
	name = strings.Trim(name, ". ")
	name = truncateUTF8Bytes(name, 200)
	if name == "" {
		name = "track"
	}
	ext := strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || strings.ContainsRune(`/\\:*?"<>|`, r) {
			return -1
		}
		return r
	}, filepath.Ext(track.Path))
	cleanSaveDir := filepath.Clean(saveDir)
	destination := filepath.Join(cleanSaveDir, name+ext)
	if filepath.Dir(destination) != cleanSaveDir {
		return "", fmt.Errorf("invalid destination filename")
	}
	if err := fileutil.CopyFile(track.Path, destination); err != nil {
		return "", err
	}
	return destination, nil
}

func truncateUTF8Bytes(s string, maxBytes int) string {
	if len(s) <= maxBytes {
		return s
	}
	for maxBytes > 0 && !utf8.RuneStart(s[maxBytes]) {
		maxBytes--
	}
	return strings.TrimRight(s[:maxBytes], ". ")
}

// NeedsDownload reports whether SaveTo downloads track with yt-dlp, which can
// take minutes. SaveTo copies every other track that it can save.
func NeedsDownload(track playlist.Track) bool {
	return playlist.IsYouTubeURL(track.Path) || playlist.IsYTDL(track.Path)
}

func insideTempDir(path string) bool {
	if fi, err := os.Lstat(path); err != nil || !fi.Mode().IsRegular() {
		return false
	}
	tempDir, err := filepath.EvalSymlinks(os.TempDir())
	if err != nil {
		tempDir = filepath.Clean(os.TempDir())
	}
	realPath, err := filepath.EvalSymlinks(path)
	if err != nil {
		return false
	}
	relative, err := filepath.Rel(tempDir, realPath)
	return err == nil && relative != "." && relative != ".." && !strings.HasPrefix(relative, ".."+string(filepath.Separator)) && !filepath.IsAbs(relative)
}
