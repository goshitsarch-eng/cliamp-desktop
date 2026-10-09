package model

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"reflect"
	"slices"
	"sort"
	"strings"

	tea "charm.land/bubbletea/v2"

	"github.com/bjarneo/cliamp/ipc"
	"github.com/bjarneo/cliamp/playlist"
	"github.com/bjarneo/cliamp/provider"
	"github.com/bjarneo/cliamp/resolve"
)

// The owner loop serializes edits to each saved playlist, while network/disk
// work remains in commands. A single saved edit per playlist is undoable.
type ipcPlaylistDesktopState struct {
	busy map[string]bool
	undo map[string]ipcSavedPlaylistUndo
}

type ipcPlaylistDocument struct {
	name     string
	exists   bool
	raw      bool
	document []byte
	tracks   []playlist.Track
}

type ipcSavedPlaylistUndo struct {
	before, after ipcPlaylistDocument
}

type ipcPlaylistDesktopDoneMsg struct {
	jobs                   *ipc.JobStore
	jobID                  string
	provider               string
	keys                   []string
	undo                   *ipcSavedPlaylistUndo
	clearUndo              bool
	renamedFrom, renamedTo string
	result                 map[string]any
	err                    error
}

type ipcDirSource struct {
	Path      string `json:"path"`
	Recursive bool   `json:"recursive"`
}

var errDesktopPlaylistConflict = errors.New("playlist changed since the edit; reload before undoing")

func isDesktopPlaylistOperation(op string) bool {
	switch op {
	case "playlist.capabilities", "playlist.dirs.list", "playlist.dirs.add", "playlist.dirs.remove", "playlist.dirs.recursive", "playlist.prepend", "playlist.undo",
		"playlist.create", "playlist.rename", "playlist.delete", "playlist.add", "playlist.add_many", "playlist.replace", "playlist.remove", "playlist.remove_many", "playlist.sort", "playlist.move", "playlist.save_queue", "playlist.import",
		"queue.undo", "queue.remove_many", "playnext.remove_many", "tracks.append", "tracks.replace", "tracks.enqueue":
		return true
	}
	return false
}

func (m *Model) desktopPlaylistState() *ipcPlaylistDesktopState {
	if m.ipcPlaylistDesktop == nil {
		m.ipcPlaylistDesktop = &ipcPlaylistDesktopState{busy: make(map[string]bool), undo: make(map[string]ipcSavedPlaylistUndo)}
	}
	return m.ipcPlaylistDesktop
}

func playlistDesktopKey(key, name string) string { return key + "\x00" + name }

func desktopPlaylistCapabilities(p playlist.Provider) map[string]any {
	_, create := p.(provider.PlaylistCreator)
	_, rename := p.(provider.PlaylistRenamer)
	_, remove := p.(provider.PlaylistDeleter)
	_, appendOne := p.(provider.PlaylistWriter)
	_, appendMany := p.(provider.PlaylistBatchWriter)
	_, replace := p.(provider.PlaylistSaver)
	_, prepend := p.(provider.PlaylistPrepender)
	_, dirs := p.(provider.PlaylistDirSourceManager)
	_, document := p.(provider.PlaylistDocumenter)
	return map[string]any{"ok": true, "create": create, "rename": rename, "delete": remove, "remove": remove,
		"add": appendOne, "add_many": appendOne || appendMany, "import": appendOne || appendMany, "replace": replace, "prepend": prepend,
		"directories": dirs, "undo": document || replace, "exact_document_undo": document, "remove_many": replace, "sort": replace, "move": replace, "save_queue": create && replace && remove}
}

func (m *Model) handleV2DesktopPlaylistRequest(ctx context.Context, jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	if request.Cmd == "queue.undo" {
		return m.handleV2QueueUndo(jobs, jobID, request)
	}
	if request.Cmd == "tracks.append" || request.Cmd == "tracks.replace" || request.Cmd == "tracks.enqueue" {
		return m.handleV2TracksBatch(jobs, jobID, request)
	}
	if request.Cmd == "queue.remove_many" || request.Cmd == "playnext.remove_many" {
		return m.handleV2QueueRemoveMany(jobs, jobID, request)
	}
	if request.Cmd == "playlist.save_queue" {
		if request.Revision != 0 && request.Revision != m.playlist.Revision() {
			m.failV2Job(jobs, jobID, v2ConflictError())
			return nil
		}
		current := m.playlist.Tracks()
		request.Tracks = make([]ipc.TrackInfo, len(current))
		for i, track := range current {
			request.Tracks[i] = ipcTrackInfo(track, i, 0, false)
		}
	}
	entry, ok := m.ipcProvider(request.Provider)
	if !ok {
		m.failV2Job(jobs, jobID, v2NotFoundError())
		return nil
	}
	if request.Cmd == "playlist.capabilities" {
		result := desktopPlaylistCapabilities(entry.Provider)
		if request.Playlist == "" {
			m.completeV2Job(jobs, jobID, result)
			return nil
		}
		return func() tea.Msg {
			lists, err := entry.Provider.Playlists()
			if err == nil {
				result["can_add"] = false
				for _, list := range lists {
					if list.ID != request.Playlist {
						continue
					}
					canAdd := result["add"] == true || result["add_many"] == true
					if filter, ok := entry.Provider.(provider.PlaylistTargetFilter); ok {
						canAdd = canAdd && filter.CanAddToPlaylist(list)
					}
					result["can_add"] = canAdd
				}
			}
			return ipcPlaylistDesktopDoneMsg{jobs: jobs, jobID: jobID, result: result, err: err}
		}
	}
	if strings.TrimSpace(request.Playlist) == "" {
		m.failV2Job(jobs, jobID, v2InvalidParamsError())
		return nil
	}
	if request.Cmd == "playlist.import" {
		if len(request.Args) == 0 || len(request.Args) > 1000 {
			m.failV2Job(jobs, jobID, v2InvalidParamsError())
			return nil
		}
		for _, path := range request.Args {
			if strings.TrimSpace(path) == "" {
				m.failV2Job(jobs, jobID, v2InvalidParamsError())
				return nil
			}
		}
		if desktopPlaylistCapabilities(entry.Provider)["import"] != true {
			m.failV2Job(jobs, jobID, v2UnavailableError())
			return nil
		}
	}
	if (strings.HasPrefix(request.Cmd, "playlist.dirs.") && request.Cmd != "playlist.dirs.list" && strings.TrimSpace(request.Path) == "") ||
		(request.Cmd == "playlist.dirs.recursive" && request.Name != "on" && request.Name != "off") ||
		(request.Cmd == "playlist.sort" && !slices.Contains(plMgrSortModes, request.Sort)) {
		m.failV2Job(jobs, jobID, v2InvalidParamsError())
		return nil
	}
	if request.Cmd == "playlist.dirs.list" {
		dirs, ok := entry.Provider.(provider.PlaylistDirSourceManager)
		if !ok {
			m.failV2Job(jobs, jobID, v2UnavailableError())
			return nil
		}
		return func() tea.Msg {
			sources, err := dirs.DirSources(request.Playlist)
			return ipcPlaylistDesktopDoneMsg{jobs: jobs, jobID: jobID, result: desktopDirsResult(sources), err: err}
		}
	}
	state := m.desktopPlaylistState()
	key := playlistDesktopKey(entry.Key, request.Playlist)
	keys := []string{key}
	if request.Cmd == "playlist.rename" {
		if strings.TrimSpace(request.NewName) == "" {
			m.failV2Job(jobs, jobID, v2InvalidParamsError())
			return nil
		}
		keys = append(keys, playlistDesktopKey(entry.Key, request.NewName))
	}
	for _, key := range keys {
		if state.busy[key] {
			m.failV2Job(jobs, jobID, v2ConflictError())
			return nil
		}
	}
	undo, hasUndo := state.undo[key]
	if request.Cmd == "playlist.undo" && !hasUndo {
		// The terminal and desktop also share the local manager's undo slot.
		if entry.Key == "local" && m.plManager.undo.kind != plUndoNone && m.plManager.undo.name == request.Playlist {
			old := m.plManager.undo
			undo.before = ipcPlaylistDocument{name: old.name, exists: true, raw: old.doc != nil, document: append([]byte(nil), old.doc...), tracks: cloneTracks(old.tracks)}
			var err error
			undo.after, err = captureDesktopPlaylist(entry.Provider, old.name)
			if err != nil {
				m.failDesktopPlaylistJob(jobs, jobID, err)
				return nil
			}
			hasUndo = true
		}
		if !hasUndo {
			m.failV2Job(jobs, jobID, v2NotFoundError())
			return nil
		}
	}
	for _, key := range keys {
		state.busy[key] = true
	}
	return func() tea.Msg {
		msg := ipcPlaylistDesktopDoneMsg{jobs: jobs, jobID: jobID, provider: entry.Key, keys: keys}
		if err := ctx.Err(); err != nil {
			msg.err = err
			return msg
		}
		if request.Cmd == "playlist.undo" {
			msg.err = restoreDesktopPlaylist(entry.Provider, undo)
			msg.clearUndo = msg.err == nil
			if undo.before.name != undo.after.name {
				msg.renamedFrom, msg.renamedTo = undo.after.name, undo.before.name
			}
			msg.result = map[string]any{"ok": true, "playlist": undo.before.name}
			return msg
		}
		if request.Cmd == "playlist.import" {
			// Resolve the complete selection before taking the undo snapshot or
			// writing anything. Importing files never changes the live playlist.
			tracks, err := resolveDesktopPlaylistImport(ctx, request.Args)
			if err != nil {
				msg.err = err
				return msg
			}
			request.Tracks = ipcTrackInfos(tracks, func(playlist.Track) bool { return false })
		}
		before, captureErr := captureDesktopPlaylist(entry.Provider, request.Playlist)
		_, documenter := entry.Provider.(provider.PlaylistDocumenter)
		_, saver := entry.Provider.(provider.PlaylistSaver)
		canUndo := documenter || saver
		if canUndo && captureErr != nil {
			msg.err = captureErr
			return msg
		}
		if err := ctx.Err(); err != nil {
			msg.err = err
			return msg
		}
		result, err := mutateDesktopPlaylist(ctx, entry.Provider, request)
		msg.result, msg.err = result, err
		if err != nil {
			return msg
		}
		if request.Cmd == "playlist.rename" {
			msg.renamedFrom, msg.renamedTo = request.Playlist, request.NewName
		}
		if canUndo {
			name := request.Playlist
			if request.Cmd == "playlist.rename" {
				name = request.NewName
			}
			after, err := captureDesktopPlaylist(entry.Provider, name)
			if err != nil {
				msg.err = fmt.Errorf("edit succeeded but undo snapshot failed: %w", err)
				return msg
			}
			if before.name != after.name || !sameDesktopDocument(before, after) {
				msg.undo = &ipcSavedPlaylistUndo{before: before, after: after}
			}
		}
		return msg
	}
}

func resolveDesktopPlaylistImport(ctx context.Context, paths []string) ([]playlist.Track, error) {
	var tracks []playlist.Track
	for _, path := range paths {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		resolved, err := resolve.URLContext(ctx, path)
		if err != nil {
			return nil, fmt.Errorf("import %s: %w", path, err)
		}
		tracks = append(tracks, resolved...)
	}
	if err := ctx.Err(); err != nil {
		return nil, err
	}
	if len(tracks) == 0 {
		return nil, fmt.Errorf("no playable tracks found")
	}
	return tracks, nil
}

func desktopDirsResult(sources []playlist.DirSource) map[string]any {
	dirs := make([]ipcDirSource, len(sources))
	for i, source := range sources {
		dirs[i] = ipcDirSource{Path: source.Path, Recursive: source.Recursive}
	}
	return map[string]any{"ok": true, "directories": dirs}
}

func captureDesktopPlaylist(p playlist.Provider, name string) (ipcPlaylistDocument, error) {
	result := ipcPlaylistDocument{name: name}
	if documenter, ok := p.(provider.PlaylistDocumenter); ok {
		result.raw = true
		doc, err := documenter.PlaylistDocument(name)
		if errors.Is(err, os.ErrNotExist) {
			return result, nil
		}
		if err != nil {
			return result, err
		}
		result.exists, result.document = true, append([]byte(nil), doc...)
		result.tracks, err = p.Tracks(name)
		if err != nil {
			return result, err
		}
		result.tracks = cloneTracks(result.tracks)
		return result, nil
	}
	if _, ok := p.(provider.PlaylistSaver); !ok {
		return result, nil
	}
	tracks, err := p.Tracks(name)
	if errors.Is(err, os.ErrNotExist) {
		return result, nil
	}
	if err != nil {
		return result, err
	}
	result.exists, result.tracks = true, cloneTracks(tracks)
	return result, nil
}

func sameDesktopDocument(a, b ipcPlaylistDocument) bool {
	if a.exists != b.exists || a.raw != b.raw {
		return false
	}
	if !a.exists {
		return true
	}
	if a.raw {
		return bytes.Equal(a.document, b.document)
	}
	return reflect.DeepEqual(a.tracks, b.tracks)
}

func restoreDesktopPlaylist(p playlist.Provider, undo ipcSavedPlaylistUndo) error {
	if atomic, ok := p.(provider.PlaylistDocumentRestorer); ok && undo.before.raw && undo.after.raw && undo.before.name == undo.after.name {
		return atomic.RestorePlaylistDocumentIfUnchanged(undo.before.name, undo.after.document, undo.after.exists, undo.before.document, undo.before.exists)
	}
	current, err := captureDesktopPlaylist(p, undo.after.name)
	if err != nil {
		return err
	}
	if !sameDesktopDocument(current, undo.after) {
		return errDesktopPlaylistConflict
	}
	if undo.before.name != undo.after.name {
		old, err := captureDesktopPlaylist(p, undo.before.name)
		if err != nil {
			return err
		}
		if old.exists {
			return errDesktopPlaylistConflict
		}
		rename, ok := p.(provider.PlaylistRenamer)
		if !ok {
			return fmt.Errorf("provider cannot undo a rename")
		}
		return rename.RenamePlaylist(undo.after.name, undo.before.name)
	}
	if !undo.before.exists {
		deleter, ok := p.(provider.PlaylistDeleter)
		if !ok {
			return fmt.Errorf("provider cannot undo playlist creation")
		}
		return deleter.DeletePlaylist(undo.after.name)
	}
	if undo.before.raw {
		documenter, ok := p.(provider.PlaylistDocumenter)
		if !ok {
			return fmt.Errorf("provider cannot restore playlist document")
		}
		return documenter.RestorePlaylistDocument(undo.before.name, undo.before.document)
	}
	saver, ok := p.(provider.PlaylistSaver)
	if !ok {
		return fmt.Errorf("provider cannot restore playlist tracks")
	}
	return saver.SavePlaylist(undo.before.name, cloneTracks(undo.before.tracks))
}

func mutateDesktopPlaylist(ctx context.Context, p playlist.Provider, request ipc.Request) (map[string]any, error) {
	result := map[string]any{"ok": true, "playlist": request.Playlist}
	tracks := make([]playlist.Track, len(request.Tracks))
	for i, track := range request.Tracks {
		if strings.TrimSpace(track.Path) == "" {
			return nil, fmt.Errorf("track path is required")
		}
		tracks[i] = ipcTrackFromInfo(track)
	}
	if len(tracks) > 1000 && request.Cmd != "playlist.save_queue" && request.Cmd != "playlist.import" {
		return nil, fmt.Errorf("at most 1000 tracks may be written in one request")
	}
	var err error
	switch request.Cmd {
	case "playlist.save_queue":
		creator, creates := p.(provider.PlaylistCreator)
		saver, saves := p.(provider.PlaylistSaver)
		deleter, deletes := p.(provider.PlaylistDeleter)
		if !creates || !saves || !deletes {
			return nil, fmt.Errorf("provider does not support creating a saved queue")
		}
		name, createErr := creator.CreatePlaylist(ctx, request.Playlist)
		if createErr != nil {
			return nil, createErr
		}
		if err := ctx.Err(); err != nil {
			if cleanup := deleter.DeletePlaylist(name); cleanup != nil {
				return nil, fmt.Errorf("%w; could not remove empty playlist: %v", err, cleanup)
			}
			return nil, err
		}
		if saveErr := saver.SavePlaylist(name, tracks); saveErr != nil {
			if cleanup := deleter.DeletePlaylist(name); cleanup != nil {
				return nil, fmt.Errorf("%w; could not remove empty playlist: %v", saveErr, cleanup)
			}
			return nil, saveErr
		}
		result["playlist"], result["total"] = name, len(tracks)
	case "playlist.create":
		p, ok := p.(provider.PlaylistCreator)
		if !ok {
			return nil, fmt.Errorf("provider does not support playlist creation")
		}
		result["playlist"], err = p.CreatePlaylist(ctx, request.Playlist)
	case "playlist.rename":
		p, ok := p.(provider.PlaylistRenamer)
		if !ok {
			return nil, fmt.Errorf("provider does not support playlist renaming")
		}
		err = p.RenamePlaylist(request.Playlist, request.NewName)
		result["playlist"] = request.NewName
	case "playlist.delete", "playlist.remove":
		p, ok := p.(provider.PlaylistDeleter)
		if !ok {
			return nil, fmt.Errorf("provider does not support playlist removal")
		}
		if request.Cmd == "playlist.delete" {
			err = p.DeletePlaylist(request.Playlist)
		} else {
			err = p.RemoveTrack(request.Playlist, request.Index)
		}
	case "playlist.add":
		p, ok := p.(provider.PlaylistWriter)
		if !ok {
			return nil, fmt.Errorf("provider does not support adding tracks")
		}
		if request.Track == nil || strings.TrimSpace(request.Track.Path) == "" {
			return nil, fmt.Errorf("track path is required")
		}
		err = p.AddTrackToPlaylist(ctx, request.Playlist, ipcTrackFromInfo(*request.Track))
	case "playlist.add_many", "playlist.import":
		if len(tracks) == 0 {
			return nil, fmt.Errorf("tracks are required")
		}
		var added, skipped int
		added, skipped, err = provider.AddTracks(ctx, p, request.Playlist, tracks)
		result["added"], result["skipped"], result["total"] = added, skipped, added
	case "playlist.prepend":
		p, ok := p.(provider.PlaylistPrepender)
		if !ok {
			return nil, fmt.Errorf("provider does not support prepending tracks")
		}
		if len(tracks) == 0 {
			return nil, fmt.Errorf("tracks are required")
		}
		var added, moved, skipped int
		added, moved, skipped, err = p.PrependTracksToPlaylist(ctx, request.Playlist, tracks)
		result["added"], result["moved"], result["skipped"] = added, moved, skipped
	case "playlist.replace":
		p, ok := p.(provider.PlaylistSaver)
		if !ok {
			return nil, fmt.Errorf("provider does not support saving playlists")
		}
		err = p.SavePlaylist(request.Playlist, tracks)
	case "playlist.remove_many":
		saver, ok := p.(provider.PlaylistSaver)
		if !ok {
			return nil, fmt.Errorf("provider does not support batch removal")
		}
		if len(request.Indexes) != len(tracks) {
			return nil, fmt.Errorf("selected tracks must accompany removal indexes")
		}
		mutate := func(current []playlist.Track) ([]playlist.Track, error) {
			indexes, indexErr := desktopRemovalIndexes(request.Indexes, len(current))
			if indexErr != nil {
				return nil, indexErr
			}
			for i, index := range request.Indexes {
				if current[index].Path != tracks[i].Path {
					return nil, errDesktopPlaylistConflict
				}
				if current[index].DirSourced {
					return nil, errQueueDirTrack
				}
			}
			for _, index := range indexes {
				current = slices.Delete(current, index, index+1)
			}
			result["removed"] = len(indexes)
			return current, nil
		}
		if updater, ok := p.(playlistUpdater); ok {
			err = updater.UpdatePlaylist(request.Playlist, mutate)
		} else {
			current, readErr := p.Tracks(request.Playlist)
			if readErr != nil {
				return nil, readErr
			}
			current, err = mutate(current)
			if err == nil {
				err = saver.SavePlaylist(request.Playlist, current)
			}
		}
	case "playlist.sort", "playlist.move":
		saver, ok := p.(provider.PlaylistSaver)
		if !ok {
			return nil, fmt.Errorf("provider does not support saved ordering")
		}
		mutate := func(current []playlist.Track) ([]playlist.Track, error) {
			if request.Cmd == "playlist.sort" {
				if !slices.Contains(plMgrSortModes, request.Sort) {
					return nil, fmt.Errorf("unknown playlist sort")
				}
				sort.SliceStable(current, func(i, j int) bool { return compareUITracks(current[i], current[j], request.Sort) < 0 })
			} else {
				if request.Index < 0 || request.To < 0 || request.Index >= len(current) || request.To >= len(current) {
					return nil, errQueueIndex
				}
				if request.Track != nil && request.Track.Path != current[request.Index].Path {
					return nil, errDesktopPlaylistConflict
				}
				if current[request.Index].DirSourced || current[request.To].DirSourced {
					return nil, errQueueDirTrack
				}
				current[request.Index], current[request.To] = current[request.To], current[request.Index]
			}
			return current, nil
		}
		if updater, ok := p.(playlistUpdater); ok {
			err = updater.UpdatePlaylist(request.Playlist, mutate)
		} else {
			current, readErr := p.Tracks(request.Playlist)
			if readErr != nil {
				return nil, readErr
			}
			current, err = mutate(current)
			if err == nil {
				err = saver.SavePlaylist(request.Playlist, current)
			}
		}
	case "playlist.dirs.add", "playlist.dirs.remove", "playlist.dirs.recursive":
		p, ok := p.(provider.PlaylistDirSourceManager)
		if !ok {
			return nil, fmt.Errorf("provider does not support directory sources")
		}
		if strings.TrimSpace(request.Path) == "" {
			return nil, fmt.Errorf("directory path is required")
		}
		switch request.Cmd {
		case "playlist.dirs.add":
			result["added"], err = p.AddDirSource(request.Playlist, request.Path)
		case "playlist.dirs.remove":
			err = p.RemoveDirSource(request.Playlist, request.Path)
		case "playlist.dirs.recursive":
			if request.Name != "on" && request.Name != "off" {
				return nil, fmt.Errorf("recursive name must be on or off")
			}
			err = p.SetDirRecursive(request.Playlist, request.Path, request.Name == "on")
		}
		if err == nil {
			var dirs []playlist.DirSource
			dirs, err = p.DirSources(request.Playlist)
			result = desktopDirsResult(dirs)
		}
	default:
		return nil, fmt.Errorf("unknown playlist operation")
	}
	return result, err
}

func (m *Model) handleIPCPlaylistDesktopDone(msg ipcPlaylistDesktopDoneMsg) tea.Cmd {
	state := m.desktopPlaylistState()
	for _, key := range msg.keys {
		delete(state.busy, key)
	}
	if msg.err != nil {
		m.failDesktopPlaylistJob(msg.jobs, msg.jobID, msg.err)
		return nil
	}
	if msg.renamedFrom != "" && msg.provider == "local" {
		m.renameLoadedPlaylist(msg.renamedFrom, msg.renamedTo)
	}
	if msg.clearUndo {
		for _, key := range msg.keys {
			delete(state.undo, key)
		}
		if msg.provider == "local" {
			m.plManager.undo = plManagerUndo{}
		}
	} else if msg.undo != nil {
		for _, key := range msg.keys {
			delete(state.undo, key)
		}
		state.undo[playlistDesktopKey(msg.provider, msg.undo.after.name)] = *msg.undo
		if msg.provider == "local" && msg.undo.before.exists && msg.undo.before.name == msg.undo.after.name {
			m.plManager.undo = plManagerUndo{kind: plUndoTracks, name: msg.undo.before.name, doc: append([]byte(nil), msg.undo.before.document...), tracks: cloneTracks(msg.undo.before.tracks)}
		}
	}
	if msg.provider == "local" {
		m.plMgrRefreshList()
	}
	m.completeV2Job(msg.jobs, msg.jobID, msg.result)
	return nil
}

func (m *Model) failDesktopPlaylistJob(jobs *ipc.JobStore, jobID string, err error) {
	protocol := v2InternalError()
	if errors.Is(err, errDesktopPlaylistConflict) || errors.Is(err, provider.ErrPlaylistDocumentChanged) || errors.Is(err, errQueueDirTrack) {
		protocol = v2ConflictError()
	}
	if errors.Is(err, errQueueIndex) {
		protocol = v2InvalidParamsError()
	}
	protocol.Detail = err.Error()
	m.failV2Job(jobs, jobID, protocol)
}

func (m *Model) handleV2QueueUndo(jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	if request.Revision != 0 && request.Revision != m.playlist.Revision() {
		m.failV2Job(jobs, jobID, v2ConflictError())
		return nil
	}
	if !m.playlistUndo.active {
		m.failV2Job(jobs, jobID, v2NotFoundError())
		return nil
	}
	if m.playlistUndo.revision != m.playlist.Revision() || m.playlistUndo.loaded != m.loadedPlaylist {
		m.failV2Job(jobs, jobID, v2ConflictError())
		return nil
	}
	cmd, err := m.restorePlaylistMutation()
	if err != nil {
		m.failDesktopPlaylistJob(jobs, jobID, err)
		return nil
	}
	m.completeV2Job(jobs, jobID, m.v2PlaylistResponse())
	return cmd
}

func (m *Model) handleV2TracksBatch(jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	if len(request.Tracks) > 1000 {
		m.failV2Job(jobs, jobID, v2InvalidParamsError())
		return nil
	}
	return m.applyV2ResolvedTracksBatch(jobs, jobID, request)
}

// applyV2ResolvedTracksBatch also serves trusted Go resolver/provider results,
// which are not constrained by the external request's JSON batch limit.
func (m *Model) applyV2ResolvedTracksBatch(jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	if request.Revision != 0 && request.Revision != m.playlist.Revision() {
		m.failV2Job(jobs, jobID, v2ConflictError())
		return nil
	}
	if request.Play && (request.Index < 0 || request.Index >= len(request.Tracks)) {
		m.failV2Job(jobs, jobID, v2InvalidParamsError())
		return nil
	}
	tracks := make([]playlist.Track, len(request.Tracks))
	for i, info := range request.Tracks {
		if strings.TrimSpace(info.Path) == "" || info.Feed {
			m.failV2Job(jobs, jobID, v2InvalidParamsError())
			return nil
		}
		tracks[i] = ipcTrackFromInfo(info)
	}
	undo := m.desktopQueueSnapshot()
	start := m.playlist.Len()
	if request.Cmd == "tracks.replace" {
		m.stopPlayback()
		m.retireTracksPaging()
		m.replacePlaylist(tracks)
		m.clearLoadedPlaylist()
		m.setHeaderStateFromTracks(tracks)
		m.plCursor, m.plScroll, start = 0, 0, 0
	} else {
		m.appendTracks(tracks...)
	}
	if request.Cmd == "tracks.enqueue" {
		for i := range tracks {
			m.playlist.Queue(start + i)
		}
		m.normalizeQueueOverlay()
	}
	var cmd tea.Cmd
	if request.Play {
		cmd = m.playIndex(start + request.Index)
	} else if request.Cmd == "tracks.enqueue" && !m.player.IsPlaying() && len(tracks) > 0 {
		cmd = m.nextTrack()
	} else {
		cmd = m.rearmStalePreload()
	}
	m.recordPlaylistUndo(undo)
	m.completeV2Job(jobs, jobID, m.v2PlaylistResponse())
	return cmd
}

func (m *Model) desktopQueueSnapshot() playlistUndo {
	return playlistUndo{snapshot: m.playlist.Snapshot(), restoreSource: true, previousLoaded: m.loadedPlaylist, previousSource: m.playlistSource}
}

func restoreDesktopQueueDocument(p playlist.Provider, undo playlistUndo) error {
	if atomic, ok := p.(provider.PlaylistDocumentRestorer); ok {
		return atomic.RestorePlaylistDocumentIfUnchanged(undo.loaded, undo.documentAfter, true, undo.documentBefore, true)
	}
	doc, ok := p.(provider.PlaylistDocumenter)
	if !ok {
		return fmt.Errorf("provider cannot restore the saved playlist")
	}
	current, err := doc.PlaylistDocument(undo.loaded)
	if err != nil {
		return err
	}
	if !bytes.Equal(current, undo.documentAfter) {
		return errDesktopPlaylistConflict
	}
	return doc.RestorePlaylistDocument(undo.loaded, undo.documentBefore)
}

func desktopRemovalIndexes(input []int, total int) ([]int, error) {
	if len(input) == 0 || len(input) > 1000 {
		return nil, errQueueIndex
	}
	indexes := slices.Clone(input)
	slices.Sort(indexes)
	for i, index := range indexes {
		if index < 0 || index >= total || (i > 0 && indexes[i-1] == index) {
			return nil, errQueueIndex
		}
	}
	slices.Reverse(indexes)
	return indexes, nil
}

func (m *Model) handleV2QueueRemoveMany(jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	if request.Revision != 0 && request.Revision != m.playlist.Revision() {
		m.failV2Job(jobs, jobID, v2ConflictError())
		return nil
	}
	total := m.playlist.Len()
	if request.Cmd == "playnext.remove_many" {
		total = m.playlist.QueueLen()
	}
	indexes, err := desktopRemovalIndexes(request.Indexes, total)
	if err != nil {
		m.failV2Job(jobs, jobID, v2InvalidParamsError())
		return nil
	}
	undo := m.desktopQueueSnapshot()
	if request.Cmd == "playnext.remove_many" {
		for _, index := range indexes {
			m.playlist.RemoveQueueAt(index)
		}
		m.normalizeQueueOverlay()
		m.recordPlaylistUndo(undo)
		m.completeV2Job(jobs, jobID, m.v2PlayNextResponse())
		return m.rearmStalePreload()
	}
	selected := make([]playlist.Track, len(indexes))
	for i, index := range indexes {
		selected[i], _ = m.playlist.Track(index)
	}
	if loaded := m.writableLoadedPlaylist(); loaded != "" {
		for _, track := range selected {
			if track.DirSourced {
				m.failV2Job(jobs, jobID, v2QueueEditError(errQueueDirTrack))
				return nil
			}
		}
		updater, ok := m.localProvider.(playlistUpdater)
		doc, hasDoc := m.localProvider.(provider.PlaylistDocumenter)
		if !ok || !hasDoc {
			m.failV2Job(jobs, jobID, v2UnavailableError())
			return nil
		}
		undo.documentBefore, err = doc.PlaylistDocument(loaded)
		if err != nil {
			m.failDesktopPlaylistJob(jobs, jobID, err)
			return nil
		}
		err = updater.UpdatePlaylist(loaded, func(tracks []playlist.Track) ([]playlist.Track, error) {
			for _, track := range selected {
				index := slices.IndexFunc(tracks, func(candidate playlist.Track) bool { return !candidate.DirSourced && candidate.Path == track.Path })
				if index < 0 {
					return nil, errDesktopPlaylistConflict
				}
				tracks = slices.Delete(tracks, index, index+1)
			}
			return tracks, nil
		})
		if err != nil {
			m.failDesktopPlaylistJob(jobs, jobID, err)
			return nil
		}
		undo.documentAfter, err = doc.PlaylistDocument(loaded)
		undo.persistedDocument = err == nil
	}
	activeIndex := m.playlist.Index()
	for _, index := range indexes {
		if index == activeIndex && !m.playbackDetached {
			m.stopPlayback()
			m.player.ClearPreload()
		}
		m.playlist.Remove(index)
	}
	m.plCursor = min(m.plCursor, max(0, m.playlist.Len()-1))
	m.normalizeQueueOverlay()
	m.recountHeaderState(m.playlist.Tracks())
	m.adjustScroll()
	m.recordPlaylistUndo(undo)
	m.completeV2Job(jobs, jobID, m.v2PlaylistResponse())
	return m.rearmStalePreload()
}

// handleV2DesktopQueueMutation wraps existing synchronous queue mutations. The
// wrapper shares Ctrl+Z's snapshot and keeps the existing persistence rules.
func (m *Model) handleV2DesktopQueueMutation(ctx context.Context, jobs *ipc.JobStore, jobID string, request ipc.Request) tea.Cmd {
	if request.Revision != 0 && request.Revision != m.playlist.Revision() {
		m.failV2Job(jobs, jobID, v2ConflictError())
		return nil
	}
	if request.Cmd == "queue.remove" {
		cmd, err := m.removeTrack(request.Index, true)
		if err != nil {
			m.failV2Job(jobs, jobID, v2QueueEditError(err))
			return nil
		}
		m.completeV2Job(jobs, jobID, m.v2PlaylistResponse())
		return cmd
	}
	undo := m.desktopQueueSnapshot()
	if request.Cmd == "queue.move" && m.writableLoadedPlaylist() != "" {
		if doc, ok := m.localProvider.(provider.PlaylistDocumenter); ok {
			var err error
			undo.documentBefore, err = doc.PlaylistDocument(m.loadedPlaylist)
			if err != nil {
				m.failDesktopPlaylistJob(jobs, jobID, err)
				return nil
			}
			undo.persistedDocument = true
		}
	}
	var cmd tea.Cmd
	if strings.HasPrefix(request.Cmd, "playnext.") {
		cmd = m.handleV2PlayNext(jobs, jobID, request)
	} else {
		cmd = m.handleV2QueueRequest(ctx, jobs, jobID, request)
	}
	job, ok := jobs.Get(jobID)
	if ok && job.State == ipc.JobSucceeded {
		if undo.persistedDocument {
			doc := m.localProvider.(provider.PlaylistDocumenter)
			var err error
			undo.documentAfter, err = doc.PlaylistDocument(m.loadedPlaylist)
			if err != nil {
				m.playlistUndo = playlistUndo{}
				return cmd
			}
		}
		m.recordPlaylistUndo(undo)
	}
	return cmd
}
