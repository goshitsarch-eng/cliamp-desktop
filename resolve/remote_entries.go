package resolve

import (
	"net/url"
	"strings"

	"github.com/bjarneo/cliamp/playlist"
)

// filterRemoteEntries drops tracks from a network-fetched playlist whose path
// names a transport other than http or https, or a UNC network share.
//
// The entry strings in a remote M3U or PLS are chosen by whoever serves it,
// not by the user, and they become track paths that playback dispatches on.
// An ssh:// entry reaches exec.Command("ssh", ...) against a server-named
// host; file:// and data: entries are not playable but are worth refusing on
// the same principle. Fetching a playlist should never let its author pick
// which program cliamp runs.
//
// Entries with no scheme are left as they were by filterRemoteEntries itself
// (unless they are UNC paths \\host\share or //host/share). HTTP playlist
// resolvers additionally resolve relative references against the playlist URL.
func filterRemoteEntries(tracks []playlist.Track) []playlist.Track {
	filtered := make([]playlist.Track, 0, len(tracks))
	for _, t := range tracks {
		if strings.HasPrefix(t.Path, `\\`) || strings.HasPrefix(t.Path, "//") {
			continue
		}
		switch URIScheme(t.Path) {
		case "":
			filtered = append(filtered, t)
		case "http", "https":
			if u, err := url.Parse(t.Path); err == nil && u.Hostname() != "" {
				filtered = append(filtered, t)
			}
		}
	}
	return filtered
}

func resolveRemotePlaylistTracks(base *url.URL, tracks []playlist.Track) []playlist.Track {
	resolved := make([]playlist.Track, 0, len(tracks))
	for _, t := range filterRemoteEntries(tracks) {
		if URIScheme(t.Path) != "" {
			t.Stream = true
			resolved = append(resolved, t)
			continue
		}
		// Reject Windows drive letters and backslashes in remote playlists so
		// an HTTP playlist cannot open local files or SMB shares.
		if base == nil || strings.Contains(t.Path, `\`) || (len(t.Path) >= 2 && t.Path[1] == ':') {
			continue
		}
		ref, err := url.Parse(t.Path)
		if err != nil {
			continue
		}
		u := base.ResolveReference(ref)
		if (u.Scheme != "http" && u.Scheme != "https") || u.Hostname() == "" || u.User != nil {
			continue
		}
		t.Path = u.String()
		t.Stream = true
		resolved = append(resolved, t)
	}
	return resolved
}

// URIScheme returns the lowercased scheme of s, or "" when s does not begin
// with one. Schemes shorter than two characters are reported as absent so a
// Windows drive letter is not mistaken for one.
func URIScheme(s string) string {
	for i, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z':
			continue
		case r >= '0' && r <= '9', r == '+', r == '-', r == '.':
			if i == 0 {
				return ""
			}
		case r == ':':
			if i < 2 {
				return ""
			}
			return strings.ToLower(s[:i])
		default:
			return ""
		}
	}
	return ""
}
