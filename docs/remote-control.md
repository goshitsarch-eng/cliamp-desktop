# Remote Control (IPC)

Control cliamp locally from a terminal, script, status bar, or GUI.

cliamp listens on `~/.config/cliamp/cliamp.sock` with `0600` permissions. It
uses newline-delimited JSON over a local Unix socket. To use SSH, run the client
command on the host that owns the socket.

The socket path can have at most 107 bytes on Linux and Windows and 103 bytes
on macOS. When the path is longer, cliamp and its client commands stop with
`socket path is too long`. Set `CLIAMP_CONFIG_DIR` to a shorter directory.

## Quick Start

```sh
cliamp status --json
cliamp next
cliamp remote state
cliamp remote events runtime.state runtime.job
```

`cliamp status --json` always includes `position`, `volume` and `index`,
because 0 is a valid value of each. It leaves out other fields that have no
value. `index` is `-1` when the playlist is empty.

IPC supports version 2 only. Clients must send a V2 envelope with each request.
See [Upgrading IPC Clients To V2](upgrading-ipc-v2.md) when you migrate a raw
socket integration.

## Version 2

V2 responses use the request `id` and always include `"version":2`.

```json
{"version":2,"id":"state","method":"state.get"}
{"version":2,"id":"play","method":"operation.submit","operation":"play","params":{}}
{"version":2,"id":"queue","method":"operation.submit","operation":"queue.enqueue","params":{"index":4,"if_revision":18}}
```

Use these methods:

| Method | Purpose |
| --- | --- |
| `capabilities` | List available operation names and parameter hints |
| `state.get` | Read the runtime snapshot |
| `spectrum.get` | Read current visualizer bands |
| `visualizer.frame` | Read the active ANSI visualizer frame without creating a job |
| `operation.submit` | Start a runtime or library operation |
| `job.get` | Read an operation job by `job_id` |
| `job.cancel` | Request cancellation of an active job |
| `subscribe` | Start a server-to-client event stream |

`operation.submit` returns a job immediately. A job can become `queued`,
`running`, `succeeded`, `failed`, or `canceled`. Its final record contains the
operation result and the snapshot from the committed operation.

```json
{
  "version": 2,
  "id": "play",
  "ok": true,
  "job": {
    "id": "8f0d...",
    "operation": "play",
    "state": "queued"
  }
}
```

Fast operations can finish before the client requests `job.get`. Slow work,
such as provider access, URL resolution, downloads, lyrics, and saved playlist
writes, remains asynchronous.

## Runtime Snapshot

`state.get` returns a snapshot with the active audio track, logical playlist
track, playback state, position, duration, seekability, modes, EQ, visualizer,
theme, stream error, and two revisions. `volume_min` reports the configured
volume floor in decibels so desktop sliders preserve the full supported range. `playlist` names the loaded saved
playlist. After `provider.load` or `provider.load_album` of another list,
`playlist` holds the provider key and the ID, for example `navidrome:42` or
`navidrome:album:7`. `device` names the output device that the last `device`
operation reported. `lyrics_offset_ms` is the shared lyric timing correction.
`notice` and `notice_error` carry the current engine status message, including
plugin notifications, so a desktop can display feedback from the shared runtime.

```json
{
  "version": 2,
  "id": "state",
  "ok": true,
  "snapshot": {
    "revision": 18,
    "playlist_revision": 7,
    "state": "playing",
    "track": {"title":"Song","path":"/music/song.flac"},
    "logical_track": {"title":"Song","path":"/music/song.flac"},
    "position": 42.5,
    "duration": 183,
    "seekable": true,
    "play_next_total": 2
  }
}
```

`revision` changes when meaningful runtime state changes. `playlist_revision`
changes when the live playlist or play-next list changes. Position-only playback
ticks do not create events. Send `if_revision` with destructive live-playlist or
play-next operations to reject stale GUI actions with the `conflict` error code.

`track` keeps `provider_meta`, embedded playback flags, and directory-source
state. A GUI can send a provider result through `track.play`,
`track.queue`, `playlist.add`, `playlist.add_many`, or `playlist.replace`
without losing provider identity. When cliamp saves such a track to a local
playlist, Favorites or Recently Played, it keeps only the `provider_meta` keys
that hold letters, digits, `.`, `_` and `-`.

The `bookmark` field of `track` keeps its name for existing scripts. It reports
the favorite ♥ state of the track, the same state as the playlist row marker.
`cliamp status --json` shows it for the current track. cliamp ignores the field
when a client sends a track, so use `playlist.bookmark` to change a favorite.

## Operations

Run `cliamp remote capabilities` to get the current machine-readable list.

| Group | Operations |
| --- | --- |
| Playback | `play`, `pause`, `toggle`, `stop`, `next`, `prev`, `volume`, `volume.adjust`, `seek`, `seek.absolute`, `speed`, `speed.adjust`, `shuffle`, `repeat`, `mono`, `eq`, `device` |
| Appearance | `theme`, `vis`, `desktop.theme`, `desktop.vis`, `desktop.vis.frame` |
| Live playlist | `queue`, `queue.list`, `queue.play`, `queue.enqueue`, `queue.remove`, `queue.move`, `queue.clear`, `track.play`, `track.queue` |
| Play-next | `playnext.list`, `playnext.remove`, `playnext.move`, `playnext.clear` |
| Sources | `load`, `url.load`, `save`, `lyrics`, `history`, `history.clear` |
| Providers | `provider.list`, `provider.auth`, `provider.auth.status`, `provider.playlists`, `provider.tracks`, `provider.load`, `provider.search`, `provider.artists`, `provider.artist_albums`, `provider.albums`, `provider.album_tracks`, `provider.load_album`, `provider.favorite`, `provider.catalog` |
| Saved playlists | `playlist.create`, `playlist.rename`, `playlist.delete`, `playlist.add`, `playlist.add_many`, `playlist.replace`, `playlist.remove`, `playlist.bookmark` |
| Plugins | `plugin.call`, `plugin.commands` |
| Desktop queue tools | `sources.load`, `tracks.append`, `tracks.replace`, `tracks.enqueue`, `queue.remove_many`, `playnext.remove_many`, `queue.undo` |
| Desktop saved playlists | `playlist.capabilities`, `playlist.dirs.list`, `playlist.dirs.add`, `playlist.dirs.remove`, `playlist.dirs.recursive`, `playlist.prepend`, `playlist.remove_many`, `playlist.sort`, `playlist.move`, `playlist.save_queue`, `playlist.import`, `playlist.undo` |
| Desktop provider routes | `provider.browse`, `provider.refresh`, `provider.genres`, `provider.genre_tracks`, `provider.genre.favorite`, `provider.location`, `provider.location.consent`, `provider.album_sort`, `provider.catalog.search`, `provider.subscriptions`, `provider.subscription.load`, `provider.subscriptions.newest`, `provider.related`, `provider.track_artist`, `provider.playback_state`, `provider.collection` |
| Desktop presentation and lifecycle | `desktop.theme`, `desktop.theme.preview`, `desktop.vis`, `desktop.vis.preview`, `desktop.vis.frame`, `lyrics.offset`, `plugin.keys`, `plugin.key`, `desktop.quit` |
| Interactive authentication | `provider.auth`, `provider.auth.status` |

`queue.*` applies to the live playlist. `playnext.*` applies only to the
play-next list. They use separate zero-based indexes.

`queue`, `queue.move`, and `queue.remove` follow the rules of the
`Shift+Up`, `Shift+Down`, and `x` keys. The Lua `cliamp.queue` functions
follow the same rules:

- `queue.move` swaps the tracks at `index` and `to`. While shuffle is on,
  it fails with `conflict` and changes nothing.
- When the live playlist mirrors a saved local playlist, `queue.move` saves
  the new order to that playlist. `queue.remove` removes the track from it
  too. When that save fails, the edit fails with `internal_error` and
  changes nothing. Favorites is not a playlist file, so an edit of a loaded
  Favorites list changes only the live playlist.
- `queue`, `queue.move`, and `queue.remove` record no undo. After one of
  them, `Ctrl+Z` does not undo the last TUI edit, because that undo would
  drop the new change.
- While the live playlist mirrors a saved local playlist, `queue.remove`
  fails with `conflict` for a track that a directory source of that playlist
  supplies. A removal of the playing track stops playback.
- `queue` appends a track. The live playlist then mirrors no saved playlist.
- When an edit changes the next track, cliamp re-arms the gapless preload.

`vis` with the name `list` returns every mode in the order of the `v` key
cycle: the built-in modes, then the visualizers of Lua plugins. `cliamp vis
list` prints the same list when cliamp runs.

The `list` result also names the active mode in `visualizer` and gives its
zero-based position in `items` as `index`. The result leaves out `index` when
it is 0. A Lua visualizer can have the name of a built-in mode, so use `index`
to find the active mode. `cliamp vis list` marks only that row.

```sh
cliamp remote call vis --params '{"name":"list"}' --wait
```

`theme list` and `cliamp theme list` return `Default - Terminal colors` as
the first item. `theme` accepts that name or `default` to select the terminal
colors.

`eq` takes a built-in preset name, such as `Rock`, or a `band` and a `value`.
It also accepts `Custom` to restore the saved custom curve. An unknown
preset name fails the job and does not change the EQ.

`shuffle` and `mono` take the `name` `on`, `off` or `toggle`. `repeat` takes
`off`, `all`, `one` or `cycle`. With no `name`, they toggle or cycle. Any
other name fails the job with `invalid_params` and changes nothing.

`playlist.bookmark` keeps its name for existing scripts. It toggles the favorite
♥ of `track`, as `f` does in the TUI. It needs a known `provider` key, but it
does not change the playlist. A radio station toggles its station favorite,
and its `bookmark` field in provider lists changes too. A station
that is a row of a loaded saved playlist toggles the favorites store instead.
The `bookmark` field of that row in `queue.list` changes. cliamp matches the
row by path.

Use IDs returned by `provider.playlists` for subsequent provider operations.
Radio favorite IDs are stable `f:<station URL>` values, not positional
`f:<index>` values.

Request provider list responses with `offset` and `limit` when the provider
supports paging. Use `playlist.replace` to save a GUI-created order, sort, or
deduplication result as one operation when the provider supports playlist saving.

## Events

Subscribe with an exact topic list. The acknowledgement is V2. Later lines use
the shared event envelope, so plugin and runtime events use the same form.

```json
{"version":2,"id":"events","method":"subscribe","topics":["runtime.state","runtime.job"]}
```

Core retained topics are `runtime.state`, `runtime.playback`,
`runtime.playlist`, and `runtime.settings`. `runtime.job` is temporary and
contains final job records. Plugin topics keep their `plugin.*` names.

If a client cannot keep up, it receives `system.overflow` with
`{"resync_required":true}` before the stream closes. Reconnect and request
`state.get` before you accept more changes.

## Spectrum Stream

`cliamp visstream` uses V2 `spectrum.get` internally. It outputs one plain
NDJSON frame at 30 FPS by default for status-bar and visualizer integrations.
Use `--fps` to set a rate from 1 through 60. GUI clients can request one current
frame with `spectrum.get`.

## CLI V2 Client

```sh
cliamp remote state
cliamp remote capabilities
cliamp remote call queue.enqueue --params '{"index":4,"if_revision":18}' --wait
cliamp remote job JOB_ID
cliamp remote cancel JOB_ID
cliamp remote events runtime.state runtime.job
```

`remote call` prints the V2 response as JSON and can submit every listed
operation. Use it in scripts and to validate a GUI integration.

Named CLI commands such as `cliamp volume`, `cliamp seek`, `cliamp load`, and
`cliamp plugins call` use V2 jobs internally. `volume` sets an absolute dB
value. `seek` is relative to the current position. V2 subscriptions read
`plugin.*` topics and runtime events.

## Headless Mode

```sh
cliamp --daemon --auto-play --playlist Lofi
```

Headless mode runs the same player as the TUI with no screen. It exposes the
same playback, queue, provider, saved-playlist, plugin, job, snapshot, and event
APIs. It loads Lua plugins, reports plays to the providers, and records Recently
Played when a track starts. The older `theme` and `vis` operations are absent
from headless `capabilities`; desktop clients can use the explicit
`desktop.theme`, `desktop.vis`, and `desktop.vis.frame` extensions below.
Use `capabilities` to discover the operations available in the running version.

## Errors And Limits

V2 errors use stable codes: `invalid_version`, `invalid_request`,
`invalid_params`, `unknown_operation`, `not_found`, `conflict`, `unavailable`,
`canceled`, and `internal_error`. Runtime failures can include a `detail` string
with a provider, device, or plugin diagnostic.

Frames are limited to 1 MiB. Use paging for large provider or playlist results.
Jobs are process-local, bounded, and retained for 15 minutes after completion.
cliamp cancels them during an orderly server shutdown. They are not available
after a restart.

## Desktop Client Extensions

The operations below use `operation.submit` and the normal job completion
contract unless explicitly described as a direct read. They are available in
both headless and terminal runtimes. Query `capabilities` and the provider-specific
capability APIs before presenting optional controls.

### Themes and visualizers

| Operation | Parameters | Successful job result |
| --- | --- | --- |
| `desktop.theme` | `name`: `list`, `default`, or a theme name | `items` for `list`; selection updates the job snapshot's `theme` colors and persists the setting |
| `desktop.vis` | `name`: `list`, `next`, or a visualizer name | `items`, `visualizer`, and active `index` for `list`; selected `visualizer` for changes |
| `desktop.vis.frame` | Optional integer `width` and `height` in terminal cells | `frame`, `width`, `height`, `visualizer`, and `theme` |
| `desktop.theme.preview` | `name` | Change the shared runtime theme without saving it |
| `desktop.vis.preview` | `index` | Change the shared runtime visualizer without saving it |

```sh
cliamp remote call desktop.theme --params '{"name":"dracula"}' --wait
cliamp remote call desktop.vis --params '{"name":"list"}' --wait
cliamp remote call desktop.vis --params '{"name":"Wave"}' --wait
cliamp remote frame --width 80 --height 20
```

Theme and visualizer selection use the existing player choices and persist
them to `config.toml`. They affect the shared backend, including an attached
terminal. The first `desktop.vis` or `desktop.vis.frame` request activates the
saved visualizer in a headless runtime. Before desktop activation, the daemon
keeps its default analysis behavior. Once activated, spectrum requests use
the shared selected visualizer's analysis.

`desktop.vis` lists built-in modes followed by loaded Lua visualizers. The
active zero-based `index` is omitted when it is zero. Names can repeat when a
Lua visualizer uses a built-in name; the index identifies the active row.
Selection accepts a name, `next`, or an explicit zero-based `index`.

Frame size defaults to 80 columns by 20 rows when a dimension is omitted or
zero. Width must be 0–240 and height 0–80; negative, fractional, or larger
values fail with `invalid_params`. `frame` contains UTF-8 terminal glyphs and
ANSI styling from the actual Go/Lua renderer. `None` produces an empty frame,
which may be omitted from JSON. Drawing restores the terminal's dimensions
afterward. Clients should use a monospace cell layout and interpret supported
styling rather than display escape sequences literally.

Prefer the direct `visualizer.frame` method, used by `cliamp remote frame`.
It takes `params: {"width":80,"height":20}` and returns the frame object in
`result`, without a job or terminal job event. The older `desktop.vis.frame`
operation remains available, but creates a job. Keep only one frame request
in flight per view and stop requesting frames for hidden views.

`desktop.vis` also accepts a zero-based `index` to select an exact row, including
a Lua mode with the same name as a built-in mode. Frame responses include the
active index (omitted when zero). Mode names are still used for persisted
configuration, matching the existing terminal behavior.

Preview changes the shared runtime, including any attached terminal. Cancel a
preview by previewing the previous theme/mode; apply it with the corresponding
non-preview operation to persist it. Clients must restore preview state when
leaving the view without applying.

### Provider sign-in

`provider.list` includes `authenticatable: true` for providers implementing an
interactive sign-in flow. This flag describes capability, not whether the
account is signed in. These operations require an already configured provider;
they do not create provider settings or replace `cliamp setup`.

```sh
cliamp remote events provider.auth
cliamp remote call provider.auth --params '{"provider":"spotify"}' --wait
cliamp remote call provider.auth.status --params '{"provider":"spotify"}' --wait
```

Both operations take `provider`, using its key from `provider.list`.
`provider.auth` starts sign-in and completes when the provider flow returns.
`provider.auth.status` returns the latest `auth` object for that provider:

```json
{"ok":true,"auth":{"provider":"spotify","state":"authenticating","url":"https://example.com/authorize"}}
```

`state` is `idle`, `authenticating`, `authenticated`, `failed`, or `canceled`. `idle` means
no desktop sign-in attempt has been recorded in this process; stored
credentials may already work. `authenticated` records successful completion
of that attempt, not a continuing credential-validity check. `url` appears
when the provider supplies a browser sign-in URL and is cleared on completion.
`error` is present after a failed attempt.

The transient `provider.auth` topic carries the same `{"ok":true,"auth":...}`
object in the event envelope's `data`. Subscribe before starting sign-in;
late subscribers should request `provider.auth.status` because these events
are not retained. Status is process-local and resets when the backend exits.

An empty provider fails with `invalid_params`, an unknown provider with
`not_found`, and a provider without interactive authentication with
`unavailable`. A second desktop sign-in for the same provider key while its
flow is running fails with `conflict`. Provider flow failures fail the job
with `internal_error` and a diagnostic detail, and publish `failed` status.

The auth object includes `cancellable`. For a context-aware provider,
`job.cancel` cancels the attempt and its callback/polling work; status eventually
becomes `canceled`. Spotify, Qobuz, Tidal and YouTube Music provide that interface.
Legacy authenticators report `cancellable: false`; canceling their IPC job cannot
abort the underlying flow, so the desktop does not offer that action. Closing
a browser tab or canceling a job is not signing out. Shared provider aliases and
the terminal coordinate the same busy authentication group.

### Desktop process shutdown

`desktop.quit` requests a normal player exit and saves resume/settings through
the same path as the terminal Quit action. A desktop client must submit it only
for a backend process it owns, then wait on that process handle. It must not
poll the final job after the socket closes. Attached clients leave the existing
player running. This graceful path also works on Windows, where a process kill
would otherwise bypass the player's exit save.

### Playlist and source editing

| Operation | Parameters and behavior |
| --- | --- |
| `sources.load` | `args` is a nonempty list of up to 1000 source strings; `name` is `append` or `replace`; optional `play` and `if_revision`. Resolves every file/directory/playlist/URL before committing. Failure, cancellation or a changed queue leaves the current queue intact. |
| `tracks.append`, `tracks.replace`, `tracks.enqueue` | Complete `tracks` records, optional `play`, `index`, and `if_revision`. Preserve provider metadata and playback flags. |
| `queue.remove_many`, `playnext.remove_many` | `indexes` and `if_revision`; validate the selection before one undoable edit. Play-next indexes are separate zero-based positions. |
| `queue.undo` | `if_revision`; undo the latest live/play-next edit using the shared terminal undo state. |
| `playlist.capabilities` | `provider`, optional `playlist`; returns supported write/undo/directory capabilities. A specific playlist also reports `can_add`. |
| `playlist.dirs.list` | `provider`, `playlist`; returns `directories: [{path, recursive}]`. |
| `playlist.dirs.add`, `playlist.dirs.remove` | `provider`, `playlist`, `path`; edit directory-source sections without deleting music files. |
| `playlist.dirs.recursive` | The same target/path and `name: "on"` or `"off"`. |
| `playlist.prepend` | `provider`, `playlist`, `tracks`; existing explicit tracks move to the front rather than duplicate. Returns `added`, `moved`, `skipped`. |
| `playlist.remove_many` | `provider`, `playlist`, `indexes`, matching complete `tracks`; verifies each selected path before committing. Directory-sourced rows cannot be removed as explicit tracks. |
| `playlist.sort` | `provider`, `playlist`, `sort` (`track`, `title`, `artist`, `album`, `artist+album`, `path`); sorts the entire saved list on the server. |
| `playlist.move` | `provider`, `playlist`, `index`, `to`, optional `track`; swaps positions, rejecting a mismatched supplied track or directory-sourced positions. |
| `playlist.save_queue` | `provider`, new `playlist`, `if_revision`; saves a captured full engine queue without a client-side track-count limit or overwriting an existing list. |
| `playlist.import` | `provider`, `playlist`, `args` containing 1–1000 source paths; resolves the entire selection before appending to the saved playlist, preserves local directory-source sections, and records one undo. It does not change the live queue. Requires the provider's `import` capability and an addable target. |
| `playlist.undo` | `provider`, `playlist`; restores the last saved edit only if its result has not changed. Local document undo preserves comments and directory sections. |

External track-array writes are bounded at 1000 records per request and the
normal 1 MiB IPC envelope limit. Server-owned source/collection resolution and
`playlist.save_queue` and `playlist.import` avoid sending a whole large collection
through that array.
Use paging for display; do not sort or save only the visible page. Bind row edits
to the revision of the displayed list, not a newer snapshot whose refreshed rows
have not arrived. On `conflict`, refresh without automatically replaying the edit.

### Provider routes and subscriptions

`provider.browse` takes `provider` and returns `browse`: supported `modes`,
`default_mode`, ordered `entries`, provider-specific artist/album/genre labels,
and capability flags for refresh, subscriptions, shows, related tracks,
track-to-artist navigation, catalog search and album sort. Route entries include
stable `id`, `mode`, placement metadata and `open_in_playlist`; they are not
implicitly playable playlists.

| Operation | Main parameters/result |
| --- | --- |
| `provider.refresh` | `provider`, optional stable `playlist`, `offset`, `limit`; invokes provider refresh before rereading. |
| `provider.genres` | `provider`, optional `entry`, `query`, paging; returns genres plus search/favorite capability. |
| `provider.genre_tracks` | `provider`, `entry`, `genre`, optional `sort`, paging, `mode`, `if_revision`. Read modes are empty/`read`; load modes include `load`, `play`, `append`, `next`. |
| `provider.genre.favorite` | `provider`, `entry`, `genre`; toggles a routed category favorite. |
| `provider.location` | Read the provider's location-consent prompt without inferring location. |
| `provider.location.consent` | `provider`, explicit boolean `allowed`; records an allow or deny choice. |
| `provider.album_sort` | `provider`, supported `sort`; persists the provider's album sort. |
| `provider.catalog.search` | `provider`, `query`, paging; an empty query clears the catalog filter. |
| `provider.subscriptions` | `provider`, paging; returns subscribed-show IDs, names and authors. |
| `provider.subscription.load` | `provider`, stable show `playlist`, `mode`, `if_revision`; mode is `append`, `play`, `next`, `newest`, or `newest_next`. |
| `provider.subscriptions.newest` | `provider`, mode and revision; gathers one newest episode per subscription and returns per-feed `failed` entries. |
| `provider.related` | `provider`, complete `track`, optional `limit`, `mode`, revision; read or append/play/queue related songs. |
| `provider.track_artist` | `provider`, complete `track`, paging; resolves its artist and returns their albums. |
| `provider.playback_state` | `provider`, `tracks`; returns `listening`, keyed by track path, with known `played`/`position` values. Absence means no known local state. |
| `provider.collection` | `provider`, `source` (`playlist`, `album`, `genre`, `search`, `related`), route identifiers, optional `filter`, `selected_path`, `mode`, `if_revision`; loads a complete collection beyond the displayed page. Modes are `play`, `replace`, `append`, `next`. |

Mutating provider results commit in the runtime owner after cancellation and
revision checks. A canceled operation must not later replace the queue. Providers
without an optional interface return `unavailable`. Do not infer a capability
from the mere presence of its globally registered operation.

### Lyrics, plugin actions and job feedback

`lyrics.offset` with no `value` reads `offset_ms`. An explicit integer `value`
from -10000 through 10000 updates and persists the shared correction; zero resets
it. Snapshots expose `lyrics_offset_ms` and lyric timestamps remain unchanged.

`plugin.keys` returns `bindings` with registered keys, plugin identity and
optional descriptions. `plugin.key` takes `name` as the exact registered key and
runs the normal trusted Lua callback. Display these actions in a command palette
as well as supporting usable keyboard combinations. Engine notifications appear
in snapshot `notice` and `notice_error`.

Use `runtime.job` and `job.get` for lifecycle feedback. `job.cancel` cancels the
job context; runtime commits check cancellation, while legacy external calls
may still need to return before their resources finish unwinding. Never silently
resubmit a timed-out or canceled mutation. Job UI should contain lifecycle and
operation names, excluding credentials, sign-in URLs and arbitrary result data.
