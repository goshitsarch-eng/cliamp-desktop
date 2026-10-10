# Desktop hands-on audit

**Status: final regression in progress. Do not treat the complete walkthrough as passed yet.**

## Application tested

Cliamp Desktop **0.1.0+1**, Flutter frontend with the real Go audio engine. Baseline `261ead0` was merged as `1aa11a0`. The follow-up is on `codex/desktop-qa-fixes`. Final implementation commit and release fingerprints will be recorded after the final build.

## Test environment

- Debian GNU/Linux 13.6 (trixie), Linux 6.18.44, x86_64.
- Go 1.26.6; Flutter 3.47.7 (`abaf9c5237`); Dart 3.13.5; engine `deb287481e`.
- GTK desktop runner, Xvfb 2560×1600, xfwm4, D-Bus, software rendering.
- ALSA null output. Playback state is observable; physical audible quality is not.
- Disposable engine profiles, generated WAV/FLAC files, M3U/PLS fixtures, a 205-track library, local RSS/audio and plugin HTTP servers. No private provider credentials are configured.

## Method and evidence

The audit launches a real native Flutter window and its real Go sidecar. Native integration actions use the rendered UI; no engine mock is substituted. Text entry and Ctrl shortcuts use the OS keyboard/clipboard, while GTK pickers use native mouse/keyboard input. X11 screenshots verify actual window dimensions. Framework exceptions and render overflows fail the run. Separate widget and Go tests protect lower-level regressions.

The [complete UI inventory](desktop-ui-inventory.md) lists controls, all 69 preference fields, and all 14 service forms. The [live defect log](desktop-defects.md) records each reproduction, expected/actual result, root cause, changed files, fix and retest. Test-helper errors are not counted as application defects.

`desktop/tool/native_audit.py` runs the entire walkthrough, a separate-process persistence check, and an independent location-consent pass. It saves action/result JSON, native screenshots and logs. Its full run does not inherit incremental phase or skip flags.

## Areas exercised

| Area | Native checks |
|---|---|
| Navigation/layout | All 11 pages; compact rail/player; small, normal, wide/short and tall/narrow windows; below-minimum attempts; maximize/restore; dialog resizing |
| Imports and errors | Files/folders, multiple selection, OS picker select/cancel, Unicode and multiline paths, M3U/PLS, failed replacement preserving the queue, missing/corrupt/unsupported/read-only files, long errors, clear/undo |
| Queue and saved library | Playback rows and menus, favorites, details, range/batch selection, append/replace/remove/save/prepend, play-next ordering and clear, create/rename/delete/cancel/undo, six saved-playlist sorts, directory sources/recursion, queue and saved-playlist pagination |
| Player/keyboard | Play/pause/stop, previous/next, seek drag/exact time, volume drag/dialog/apply/cancel, all seven speeds, repeat/shuffle/mono, lyrics and download controls, command palette, text editing, focus return, real Linux MPRIS calls |
| Settings/setup | Every preference field; validation and save/reopen; every service and conditional connection form; required/Unicode inputs and secret masks; connection failure, explicit offline save and Later |
| Visualizer/EQ/lyrics | All 34 visualizer modes and 23 themes with engine-state confirmation; preview/apply/cancel; fullscreen controls/keys; four light-theme contrast measurements; all EQ presets/bands; embedded synced lyrics, seek, offset, follow and resize |
| Providers/podcasts | Public provider routes, country/tag pinning and filtering, sorting/pagination, collection append/play, search/clear/reload, location consent, local RSS subscribe/unsubscribe and every episode action |
| Plugins/jobs/recovery | Source review and validation, exact-content approval, install/configure/toggle/remove, command and keyboard action, engine restart retaining queue/position/play-next, running-job cancellation, owned-engine failure/reconnect |
| Developer operations | All 123 operation-selector entries, invalid/valid JSON, running a queue query and inspecting feedback. Selecting an operation is not a claim that every parameterized engine operation was executed. |

Account-specific controls requiring authenticated providers remain outside verified native coverage; see the limits below. The final inventory will distinguish these from passed local/public workflows.

## Bugs fixed

**30 reproduced defects currently logged.** Full details and individual file references are in the [defect log](desktop-defects.md).

| Defects | Correction | Main files |
|---|---|---|
| 001–003, 005–006 | Usable minimum layout, scrolling dialogs/visualizer, visible selection scrollbar, notifications above playback | `app.dart`, `visualizer.dart`, Linux/macOS/Windows runners |
| 004, 010, 012–013 | Required-input and schema validation; dialog-owned editing resources survive route dismissal | `app.dart`, `preferences.dart`, `plugin_manager.dart` |
| 007–008, 011, 026, 029 | Honest unknown durations, stable slider accessibility, restart retention, queue selection/page retention and native-picker focus restoration | `app.dart`, `backend.dart` |
| 009 | Ignore unchanged or invisible spectrum/state updates that caused excessive idle redraws | `app.dart` |
| 014, 023–024 | Search releases focus, Return executes palette matches, provider Escape clears search and returns from remote results | `app.dart`, `provider_browser.dart` |
| 015–022, 027–028 | Activity-dialog constraints, atomic local import validation, readable/scrollable errors, lyric resize following, theme contrast, podcast terminology/counts, short provider layouts | `app.dart`, `jobs.dart`, `lyrics.dart`, `visualizer.dart`, `provider_browser.dart`, `ui/model/ipc_sources_desktop.go` |
| 025 | Podcast catalog/search favorite flags agree with subscription state | `external/podcast/provider.go` |

Visual evidence includes [small queue before](screenshots/queue-before-640x480.png)/[after](screenshots/queue-after-640x480.png), [visualizer before](screenshots/visualizer-before-640x480.png)/[after](screenshots/visualizer-after-640x480.png), [provider overflow before](screenshots/provider-collection-before.png)/[after](screenshots/provider-collection-after.png), [lyrics before](screenshots/lyrics-before-resize.png)/[after](screenshots/lyrics-after-resize.png), [light caption before](screenshots/light-theme-caption-before.png)/[after](screenshots/light-theme-caption-after.png), [bounded error](screenshots/long-error-after.png), and [activity dialog](screenshots/activity-after-640x480.png).

## Automated regression protection

- App tests: responsive layout, input feedback, notification bounds, populated activity, durations, slider semantics, idle frame scheduling, slow dialog dismissal, command submission, native-picker focus loss and paginated queue selection.
- Backend tests: capture/restore beyond 200 tracks, playback state and play-next retention, and capture failure leaving the old engine running.
- Preferences/plugin tests: number/list/EQ validation and explicit review of plugin contents.
- Provider/lyrics tests: Escape after search submission, restored results/focus and active lyric visibility after resize.
- Go tests: reject missing/non-file local playlist entries before queue replacement; subscription favorite state across catalog/search sections.
- Native regression runner: real desktop/engine workflows and separate-process persistence, including the original failure sequences.

## Verification so far

- **PASS:** `make check` (format, vet and tests; 59 packages with passing tests), under a Linux child-subreaper wrapper.
- **PASS:** all **113 Flutter tests** after the latest product fixes.
- **PASS:** Flutter analysis at the latest completed analysis checkpoint; final analysis pending.
- **PASS:** targeted native visualizer, palette, source, library, podcast, lyrics, plugin/restart, download, cancellation, recovery, setup-save and native file-picker workflows. Remaining provider routes and the complete final run are pending.
- **PENDING:** final complete walkthrough, separate-process persistence, final release smoke/scaling and matched performance measurement.

The container's PID 1 does not reap orphaned children. An existing Lua child-process test mistakes zombies for live processes in an unwrapped run. The local subreaper supplies normal child reaping; no product behavior or test assertion was weakened.

## Performance

An earlier matched release comparison, after ten seconds of warmup over five-second samples, reduced idle frontend CPU from **225.98% to 15.00%** of one core after the spectrum fix. RSS was approximately 298 MiB versus 293 MiB. Further unchanged-state filtering is included in this follow-up. Final combined-build measurements are pending. Software-renderer figures are environment-specific, not a hardware performance guarantee.

## External verification limits

- **Windows/macOS:** this Linux host cannot launch either native runner. Their native builds, window behavior, platform media keys and packaging require the respective operating systems.
- **Live accounts:** no provider credentials, private media servers or SSH test endpoint are configured. Authentication, private catalogs, account playback and private SSH sources cannot be certified from public/local-fixture checks.
- **Physical hardware:** ALSA null output does not test audible output, real device switching, physical media-key hardware or GPU-specific rendering.
- **Hosted CI:** GitHub Actions cannot start because the repository account is billing-locked. The checked annotation is: “The job was not started because your account is locked due to a billing issue.” [Observed run](https://github.com/goshitsarch-eng/cliamp-desktop/actions/runs/37998938519). Local results do not establish hosted CI success.

## Final result

**Pending.** The final result will be updated only after the full post-fix walkthrough, relaunch and release smoke test complete. No complete cross-platform or authenticated-provider pass is claimed.
