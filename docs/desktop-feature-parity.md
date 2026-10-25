# Desktop feature parity

The Godot application controls the existing Go engine. Audio decoding,
provider integrations, playback reports, resume, media controls, and Lua execution
remain in that engine. The desktop adds graphical workflows and bounded IPC or
stdin APIs for capabilities previously exposed only through terminal controls.

This matrix distinguishes implemented workflows from release acceptance. A
passing fake-provider test establishes routing and UI behavior; it does not
establish that a remote account, physical audio device, or another operating
system has been tested.

## Implemented workflows

| Area | Desktop workflow | Engine contract |
| --- | --- | --- |
| Playback | Transport, slider and exact-time seek, volume with configured dB floor, shuffle/repeat, speed, mono, device selection, downloads | Existing player operations and snapshots |
| Equalizer | Ten bands, built-in presets and saved Custom curve | `eq` and `eq_bands` |
| Sources | Native file/folder selection, URLs, SSH paths, playlist files, append/replace and play choice | `sources.load` resolves the complete selection before committing |
| Live and play-next queues | Fuzzy filtering, multi-selection, full-track append/enqueue/replace, reorder, atomic removal, undo | `tracks.*`, `queue.*`, `playnext.*`; displayed-list revisions guard edits |
| Saved playlists | Create/rename/delete with list-level undo, native file import, prepend/append, whole-list sort, move, multi-remove, directory sources and recursive scanning, document-preserving undo | `playlist.capabilities`, `playlist.import`, `playlist.dirs.*`, `playlist.sort`, `playlist.move`, `playlist.undo` |
| Save current queue | Save the engine's complete queue without a client-side page limit | `playlist.save_queue` |
| Provider browsing | Actual provider labels/modes, artists/albums, genres and category favorites, search/catalog search, sort, refresh, related tracks, track-to-artist navigation | `provider.browse` and advertised optional provider operations |
| Radio location | Country/category browsing, pinned categories, explicit allow/deny before location inference | `provider.location` and `provider.location.consent` |
| Subscriptions | Browse subscribed shows, unsubscribe, play/append/queue shows or newest episodes, batch newest with per-feed failures | `provider.subscriptions`, `provider.subscription.load`, `provider.subscriptions.newest` |
| Episode state | Provider-supplied played and resume markers | `provider.playback_state` |
| Accounts | Conditional setup forms, private credential submission, browser sign-in/status and cancellation when supported | `setup schema/apply`, `provider.auth`, `provider.auth.status` |
| Lyrics | Synced following, manual scroll, select-to-seek, untimed/live display, shared timing adjustment | `lyrics`, `lyrics.offset`, `lyrics_offset_ms` |
| Appearance | All engine/Lua visualizers, original ANSI colors, duplicate-name selection by index, fullscreen with transport/volume/title controls, preview/apply/cancel, shared theme colors | `desktop.theme`, `desktop.vis`, preview operations, direct `visualizer.frame` |
| Plugins | Installed list, source/permission/hash review, exact-content approval, remove, enable/disable, private configuration, commands and registered key actions | `plugins desktop`, `plugin.commands`, `plugin.call`, `plugin.keys`, `plugin.key` |
| Preferences | Searchable grouped nonsecret settings, validation, preservation of unrelated config, explicit owned-engine restart | `preferences schema/apply` |
| Long operations | Running/completed/failed/canceled jobs and cancellation controls | `job.get`, `job.cancel`, runtime events |
| Desktop interaction | Command palette, keyboard shortcuts protected while editing text, native file dialogs, selection, metadata, compact player and responsive pages | Godot controls backed by the same engine operations |

Provider-specific controls depend on `provider.browse` and playlist capabilities.
Unsupported provider writes are not implied by a globally registered operation.
Local playlist undo preserves the raw document, including directory-source
sections. Other providers expose only the capabilities they actually implement.

## Validation evidence

The Godot client was ported from the Flutter application page by page. On
Windows 11 it has been run against a freshly built engine (MSYS2 MinGW64 codecs)
with the repeatable [engine smoke](../godot/tests/engine_smoke.gd), which uses a
generated WAV, an isolated config directory and the machine's audio output. It
covers connection and capability discovery, playback, pause, seek, volume, EQ
presets, shuffle, queue edits and revision conflicts, streamed spectrum bands,
direct visualizer frames, lyrics, history, local playlists, preference, plugin
and provider-setup schemas, and graceful shutdown. All 29 checks passed. The
fake-process [adapter tests](../godot/tests/backend_test.gd) (66 checks) port the
Flutter adapter's lifecycle and protocol tests: attaching versus owning a daemon,
shutdown fallbacks, startup diagnostics and deadlines, polling without replaying
mutations, conflicts, hostile path characters, overflow resynchronization,
provider sign-in events, bounded command waits, protocol versions, idempotent
close, secrets only over stdin, and frames without jobs. The pure-logic suites
cover ANSI parsing, lyric timing, EQ values, preference schema forms and plugin
payloads. Every page was screenshotted against the engine with the screenshot
harness. Defects found this way are fixed, among them: Godot does not escape quotes in
Windows arguments, and whole numbers must be sent as integers.

The Go suite independently exercises the shared engine and added contracts.
The smoke does not validate audible output, every codec/stream, live account
credentials, remote service availability, or native file-dialog interaction on
each operating system. The prompt, confirm, custom-content and seek dialogs are driven by button presses
in a [headless test](../godot/tests/dialogs_test.gd) (19 checks). The save-to-playlist
chooser with its name prompt, playlist tools and provider setup dialogs are driven
against the real engine in [engine_dialogs](../godot/tests/engine_dialogs.gd)
(13 checks), including creating a playlist and writing a track to it. The plugin
review and configuration dialogs are driven against the real engine in
[engine_plugins](../godot/tests/engine_plugins.gd) (16 checks): declining installs
nothing, approval needs the exact-content checkbox, and the reviewed token installs
and removes the plugin. The plugin command dialog was exercised only through its
content builder and basic open/close.
The Flutter application's widget tests have no Godot counterpart yet beyond the
suites above; migrating them to GdUnit4 is open work.

## Remaining release acceptance

- Launch the macOS and Linux bundles on those operating systems. The Windows
  export was built and launched here, and the Linux and macOS presets export
  cleanly from the Windows machine (the macOS export caught a missing
  ETC2/ASTC setting and an invalid bundle identifier, both fixed), but neither
  bundle has been run, and the CI workflow and Flatpak recipe have not been run.
- Exercise actual service accounts: initial authentication, cancellation,
  expired credentials, representative searches/collections, subscription actions,
  playback reports and resume. Providers may impose account or API restrictions.
- Exercise physical audio, gapless transitions across representative supported
  formats, stream metadata changes, non-seekable sources, downloads, and optional
  FFmpeg/yt-dlp discovery on target machines.
- Review visual fidelity and keyboard-only accessibility on native desktops,
  including Unicode/emoji cell widths, custom themes and third-party Lua modes.
- Produce distributable installers and complete codec redistribution, platform
  signing and macOS notarization. Current outputs are development bundles.

No entry above claims those platform/account acceptance checks have passed.
The authoritative feature semantics remain in [Keybindings](keybindings.md),
[Configuration](configuration.md), [Plugins](plugins.md), the provider guides,
and [Remote Control](remote-control.md).
