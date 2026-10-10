# Flutter desktop feature parity

The Flutter application controls the existing Go engine. Audio decoding,
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
| Desktop interaction | Command palette, keyboard shortcuts protected while editing text, native file dialogs, selection, metadata, compact player and responsive pages | Flutter controls backed by the same engine operations |

Provider-specific controls depend on `provider.browse` and playlist capabilities.
Unsupported provider writes are not implied by a globally registered operation.
Local playlist undo preserves the raw document, including directory-source
sections. Other providers expose only the capabilities they actually implement.

## Validation evidence

The Linux release bundle has been built and launched with its adjacent Go
sidecar. Native keyboard seeking, fullscreen volume and track-information
controls, and complete icon rendering have been checked. Closing the window
exits successfully, reaps all three owned engine/stream processes, and removes
the IPC socket. The
repeatable [real-engine smoke](../desktop/tool/backend_smoke.dart) uses a generated
WAV, temporary HOME/config/data directories, and an ALSA null sink. It covers:

- Playback, pause/resume, seek, volume and custom volume floor, EQ, queue conflicts,
  real event/spectrum streams, attachment, graceful shutdown and owned restart.
- Atomic multi-source resolution, batch removal/undo, saved ordering/prepend,
  complete queue capture without overwriting an existing playlist, provider
  metadata, atomic saved-file imports without touching playback, directory
  sources, recursive scanning and document undo.
- Lyrics timing, direct visualizer reads without job creation, preference
  read/write, appearance previews without persisting preferences, offline plugin
  review/trust/configuration/removal, private provider setup over stdin, and
  registration after restart.

Flutter tests cover adapter lifecycle/protocol failures, provider setup,
preferences and plugin approval, provider navigation/consent/subscription routing,
appearance preview, frames and fullscreen controls, queue revision races,
filtering/selection, shared themes, listening markers, keyboard text focus and
popup dismissal, exact-time seek validation and track-change guards, saved
playlist deletion/undo, errors/retry, and all library pages at 900×650.
On 2026-10-09, all 96 Flutter tests passed and `flutter analyze` reported no
issues. All 59 Go packages passed, along with formatting, vet and staticcheck.
The Go suite independently exercises the shared engine and added contracts.
The 2026-10-10 [native desktop audit](qa/desktop-audit.md) records the subsequent
UI fixes, 114 passing Flutter tests, real native-dialog workflows, release
relaunch/scaling checks, and the status of the complete regression pass.
Run the commands in [the desktop guide](desktop.md#validate) against
the current checkout; test totals change as regression coverage expands.

The smoke uses silent audio and fixture providers. It does not validate audible
output, every codec/stream, live account credentials, remote service availability,
or native file-dialog interaction on each operating system.

## Remaining release acceptance

- Build and launch the native macOS and Windows bundles on those operating
  systems. Their projects and CI jobs exist; this Linux environment cannot
  establish native launch, media keys, audio-device behavior, signing or socket
  access there.
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
