# Desktop audit defect log

Final application `f0bf245`: all 31 application defects were retested successfully in the final Linux walkthrough. [266-stage evidence](verification.json); ENV-001 remains unresolved as documented below.

Baseline: `261ead0`. Entries are added only after real UI reproduction; each records steps, expected/actual behavior, cause, fix and native retest evidence.

## BUG-001 — Small windows hide the library and navigation

- **Area / severity:** Main window, all library screens; high usability defect.
- **Reproduction:** Launch the native Linux release; resize to 640×480, then 400×300; open Queue.
- **Expected:** Track list, navigation and playback controls remain reachable at the supported minimum size.
- **Actual:** The fixed hero/header/player heights consume the available height. Debug native execution reports a 4 px bottom overflow at 640×480 and the 400×300 screenshot shows a 202 px overflow and no reachable navigation items.
- **Evidence:** `baseline-640x480.png`, `baseline-400x300.png`, `layout-Queue-640x480.png`, `layout-Queue-400x300.png` in the audit evidence directory.
- **Root cause:** Fixed vertical decorations and no native minimum-size contract.
- **Files:** `desktop/lib/src/app.dart`, native runner window setup.
- **Fix:** Compact headings and top padding below 650 px; native content minimum of 640×480 in all three runners.
- **Retest:** Linux native run `native-third.log`: all 11 screens at 1280×940, 900×650, 640×480 and 1600×500; 400×300 requests correctly clamp to 640×480. No layout exceptions. Windows/macOS native checks require those operating systems.

## BUG-002 — Add music dialog overflows short windows

- **Area / severity:** Source import dialog; medium.
- **Reproduction:** Open Add music; resize native window to 640×480 and below.
- **Expected:** Source field and both action buttons remain reachable.
- **Actual:** Fixed non-scrollable content reports a 148 px bottom overflow.
- **Root cause / files:** `desktop/lib/src/app.dart`, unconstrained dialog content column.
- **Fix:** Make the dialog content scrollable while retaining fixed action buttons.
- **Retest:** PASS in native-third: 640×480, attempted below-minimum resize and restored 1280×940.

## BUG-003 — Visualizer controls exhaust available height

- **Area / severity:** Visualizer; medium.
- **Reproduction:** Open Visualizer at 640×480.
- **Expected:** Mode, theme, preview/fullscreen controls and canvas remain reachable.
- **Actual:** Control rows overflow by 35 px; canvas loses its space.
- **Root cause / files:** `desktop/lib/src/visualizer.dart`, fixed controls above an expanded canvas.
- **Fix:** Give the visualizer a bounded minimum content height with scrolling when necessary.
- **Retest:** PASS in native-third: 640×480, attempted below-minimum resize and restored 1280×940.

## BUG-004 — Empty source submission gives no feedback

- **Area / severity:** Add music; low.
- **Reproduction:** Enter spaces/newlines and press Continue.
- **Expected:** Explain what input is needed.
- **Actual:** No feedback or state change.
- **Root cause / files:** `desktop/lib/src/app.dart`, empty input silently returns.
- **Fix:** Inline validation explains that a source, file or folder is required.
- **Retest:** PASS in native-third and subsequent interaction runs: spaces/newlines show the inline message; Cancel returns to the unchanged queue.

## BUG-005 — Selection actions have no visible horizontal scroll control

- **Area / severity:** Queue multi-selection; medium usability.
- **Reproduction:** Import two tracks, select visible tracks, resize to 640×480.
- **Expected:** All selection actions are discoverable and reachable with a mouse.
- **Actual:** Save, Remove and Finish selecting extend beyond the right edge with no scrollbar.
- **Evidence:** `selected-640x480.png` from native-seventh.
- **Root cause / files:** `desktop/lib/src/app.dart`, horizontal selection scroll view without an explicit scrollbar.
- **Fix:** Persistent horizontal scrollbar with its own scroll controller and space below the actions.
- **Retest:** PASS: native four-row selection and the end of its toolbar remain reachable at 640×480; Final native walkthrough PASS.

## BUG-006 — Notifications cover playback seeking

- **Area / severity:** Shared playback bar; medium usability.
- **Reproduction:** Remove a favorite, return to Queue and resize to 640×480 while the notification is visible.
- **Expected:** Playback controls remain available while feedback is shown.
- **Actual:** The floating notification covers the seek slider.
- **Evidence:** `selected-640x480.png` from native-seventh.
- **Root cause / files:** `desktop/lib/src/app.dart`, player bar lived inside the Scaffold body, so the snackbar did not reserve its height.
- **Fix:** Place the player in Scaffold.bottomNavigationBar; Flutter positions notifications above it.
- **Retest:** PASS: native minimum-size error notifications sit above the playback bar and leave seeking accessible; Final native walkthrough PASS.

## BUG-007 — Track duration contradicts the player

- **Area / severity:** Queue track rows; low visual/data defect.
- **Reproduction:** Import a local WAV without cached duration metadata and start it.
- **Expected:** Use the known current duration; indicate unknown duration for tracks not yet probed.
- **Actual:** The row says 0:00 while the playback bar correctly says 2:00.
- **Evidence:** `play-pause-seek-controls-failed.png` from native-seventh (the seek scenario itself was interrupted by a test input synchronization issue).
- **Root cause / files:** `desktop/lib/src/app.dart`, duration display uses missing track metadata as zero and ignores the current engine duration.
- **Fix:** Use the current engine duration when metadata is missing; use an em dash for an unknown duration.
- **Retest:** PASS: duration regression unit test and native playback show 2:00 for the current WAV, with an em dash for unknown metadata; Final native walkthrough PASS.

## BUG-008 — Accessibility tree assertion during playback dialog resize

- **Area / severity:** Playback / accessibility; high (framework assertion).
- **Reproduction:** Native-eighth: play/pause, seek, toggle playback options, open Adjust volume, resize 640×480 and restore 1280×940.
- **Expected:** Layout and accessibility tree update without framework exceptions.
- **Actual:** Flutter `_SemanticsGeometry.computeChildGeometry` asserts that the child and parent render objects no longer share the expected ancestor.
- **Files / root cause:** Framework diagnostics traced a stale semantics parent to the seek slider’s internal GlobalKey being reparented when its enabled state changes. Restart reproduces this independently of resizing.
- **Fix:** Key seek and volume slider state by availability, preserving external values while rebuilding the internal focus/semantics subtree on transitions. Accessibility remains enabled.
- **Retest:** Native plugin installation/restart passed without the assertion; Final native walkthrough PASS. Temporary framework diagnostics were removed.

## BUG-009 — Idle spectrum updates rebuild the whole frontend

- **Area / severity:** Performance; high.
- **Reproduction:** Launch baseline release with an empty queue and null audio output; leave it idle. Sample application `/proc/PID/stat` CPU time over five seconds after three seconds of startup.
- **Expected:** A static paused window does little rendering work.
- **Actual:** 136.59% of one CPU core in this Xvfb/software-rendered Linux session (baseline release PID 128049).
- **Root cause / files:** `desktop/lib/src/app.dart`, every 30 Hz spectrum packet calls setState even when bands are identical or the visible page has no spectrum.
- **Fix:** Ignore identical band values and only rebuild spectrum-bearing pages; retain the latest values for later navigation.
- **Retest:** PASS: matched baseline/final release, same engine and isolated profiles, 20-second warmup and 10-second samples: CPU 229.74% → 1.40% of one core; RSS 295.0 → 283.7 MiB. Both close their owned engine processes. Software-renderer figures are environment-specific.

## BUG-010 — Preference validation does not identify the invalid field

- **Area / severity:** Preferences; medium usability.
- **Reproduction:** Find Volume min, enter 999 and click Save changes.
- **Expected:** Identify the field and its allowed range.
- **Actual:** Generic “settings or plugin operation could not complete” message gives no specific correction.
- **Evidence:** `preferences-validation-and-save-failed.png` in native-preferences-tail evidence.
- **Root cause / files:** Backend management diagnostics intentionally suppress potentially sensitive process output; `preferences.dart` lacked local schema validation.
- **Fix:** Validate changed numeric fields, integer values, bounds, name lists and EQ arrays locally and identify the failing field without exposing process diagnostics.
- **Retest:** PASS: native preference validation rejects 999, saves -48 and reopens with that value. Final native walkthrough PASS.

## BUG-011 — Restarting for plugin changes discards the queue

- **Area / severity:** Engine lifecycle; high, loss of listening session.
- **Reproduction:** Import two local tracks; install the reviewed audit plugin; press Restart player.
- **Expected:** Plugin reload retains the queue and play-next entries.
- **Actual:** The newly started engine has an empty queue. Native plugin audit compares two tracks before restart with no tracks afterward.
- **Root cause / files:** `desktop/lib/src/backend.dart`, restart stopped and launched the engine without capturing the live queue.
- **Fix:** Capture all queue pages and play-next entries before stopping; restore tracks and modes, resume active playback/position, then restore play-next order. Failed capture leaves the original daemon running.
- **Retest:** PASS: native plugin install/restart retains both tracks, paused state and play-next order. Run14 also verifies a known 45-second position, repeat mode and the plugin Ctrl+N shortcut. Unit tests cover 201 tracks across pages and failure before stopping. Final native walkthrough PASS.

## BUG-012 — Blank playlist and plugin submissions are silent

- **Area / severity:** Required text input; low usability.
- **Reproduction:** In the native release, Playlists > New playlist > Create with a blank name; separately Plugins > Manage plugins > Review source with no source.
- **Expected:** Identify the required input.
- **Actual:** Both buttons silently return with no validation feedback. Captured before/after screenshots in the manual-input evidence directory.
- **Root cause / files:** `app.dart` shared prompt and `plugin_manager.dart` return early for blank strings.
- **Fix:** Shared prompts show field-specific validation for mouse and Enter submission; plugin review requests a source explicitly. Prompts scroll at small sizes.
- **Retest:** PASS: native run12 rejects blank/whitespace playlist names and empty plugin sources. Long names, duplicates, and path traversal input also passed; Final native walkthrough PASS.

## BUG-013 — Closing input dialogs can crash under slow frames

- **Area / severity:** Dialog lifecycle; high.
- **Reproduction:** Native file audit: submit Add music with two source paths, then navigate as the route dismisses. Logs report `A TextEditingController was used after being disposed`, followed by widget-tree assertions.
- **Expected:** Fields remain valid for the entire dismissal animation.
- **Actual:** The timed controller disposal can run before the dialog subtree unmounts.
- **Root cause / files:** `app.dart` disposes controllers 300 ms after `Navigator.pop`, using wall-clock delay as a proxy for widget lifetime in Add music, shared prompts and Engine operations.
- **Fix:** A small stateful dialog owner creates and disposes each controller with the actual route subtree. No timer or assumed animation duration.
- **Retest:** PASS: real native file/folder selection and cancellation after the lifecycle fix; Final native walkthrough PASS.

## BUG-014 — Escape leaves playback shortcuts trapped in search

- **Area / severity:** Keyboard navigation; medium.
- **Reproduction:** Ctrl+F, type into search, Escape, Tab/Shift+Tab, Ctrl+X. Native audit finds that compact mode does not open; the search field keeps editing focus after Escape.
- **Expected:** Escape exits the search interaction, restoring application shortcuts.
- **Actual:** Escape clears text but leaves focus in the field, so editing shortcuts continue intercepting playback commands.
- **Root cause / files:** `app.dart` Escape handler clears the controller without releasing its FocusNode.
- **Fix:** Unfocus the search when Escape handles the main route; modal Escape still closes only its route.
- **Retest:** PASS: native Escape, Tab/Shift+Tab and Ctrl+X sequence in run7; Final native walkthrough PASS.

## BUG-015 — Populated background activity crashes its dialog

- **Area / severity:** Background activity; high.
- **Reproduction:** Import music, open Background activity, resize the dialog at 640×480 and normal size. Native run9 keyboard pass reproduces this after successful engine operation execution.
- **Expected:** Completed and active operations remain visible in a scrollable dialog.
- **Actual:** `RenderShrinkWrappingViewport does not support returning intrinsic dimensions`, followed by missing-layout assertions.
- **Root cause / files:** `app.dart` passes a lazy list inside JobsPanel directly to AlertDialog, whose intrinsic width calculation reaches the viewport.
- **Fix:** Bound the dialog content width explicitly; available dialog constraints still limit it at minimum window size. Screenshot review also found the title repeated twice; retain one full-size heading in the activity panel.
- **Retest:** PASS: native run12 keyboard opens populated activity, resizes and closes without framework errors; regression unit test also passed.

## BUG-016 — Missing playlist entries replace a working queue

- **Area / severity:** Import integrity; high.
- **Reproduction:** Queue two playable tracks; Add music > Replace queue; choose an M3U containing `missing-file.wav`; confirm Replace.
- **Expected:** Failed resolution preserves the two-track queue and identifies the unavailable entry.
- **Actual:** Native run10 sources reduces the queue from two tracks to one missing path.
- **Root cause / files:** `ui/model/ipc_sources_desktop.go` resolves playlist syntax but does not validate local entries before applying the batch.
- **Fix:** Validate each resolved local path as an existing regular file before committing any queue mutation. Remote/SSH tracks retain their resolver behavior.
- **Retest:** PASS: native run11 missing M3U preserves both tracks and displays an error at 640×480. Go regressions cover a mixed valid/missing playlist and a directory entry; full Go checks passed.

## BUG-017 — JSON validation exposes an exception type

- **Area / severity:** Engine operation input; low usability.
- **Reproduction:** Select queue.list, enter `[]`, click Run operation.
- **Expected:** Plain correction: “Enter a JSON object.”
- **Actual:** Native screenshot `engine-json-validation.png` shows “FormatException: Enter a JSON object.”
- **Root cause / files:** `app.dart` stringifies the complete FormatException rather than its message.
- **Fix:** Display the parser message without exception type or source dump.
- **Retest:** PASS: native run12 rejects array input and then executes a valid queue query; screenshot shows the plain validation message.

## BUG-018 — Long source errors push notifications off screen

- **Area / severity:** Error feedback / layout; medium.
- **Reproduction:** Add music > Replace queue; enter a 4,000-character nonexistent path; confirm; resize to 640×480.
- **Expected:** Readable error feedback with accessible player and dismissal controls.
- **Actual:** Native run11 raises “Floating SnackBar presented off screen”; the unbounded path message is taller than the available window.
- **Root cause / files:** `app.dart` renders arbitrarily long backend error text without height constraints.
- **Fix:** Limit message height to 120 logical pixels and allow scrolling through the full text.
- **Retest:** PASS: native run12 displays the long error at minimum size without framework errors; final native walkthrough PASS.

## BUG-019 — Resizing hides the active lyric line

- **Area / severity:** Synced lyrics / resizing; medium usability.
- **Reproduction:** Play and pause the embedded-LRC fixture; click the second line to seek to 0:30; leave Follow lyrics on; resize from 1280×940 to 640×480.
- **Expected:** The active line remains fully visible while following.
- **Actual:** Native run12 screenshot `synced-lyrics-640x480.png` shows the active second line clipped behind the player boundary.
- **Root cause / files:** `lyrics.dart` only follows when the active line index changes, not when the lyric viewport shrinks.
- **Fix:** Reposition the active lyric on viewport height changes while following remains enabled; manual scrolling still disables following.
- **Retest:** PASS: native run13 checks the active lyric bounds above the player after resizing; the focused resize unit test also passed.

## BUG-020 — Error notification dismissal has poor contrast

- **Area / severity:** Error feedback / visual; low accessibility.
- **Reproduction:** Display a failed import notification with the default theme at minimum size.
- **Expected:** The dismissal icon is as legible as the notification text.
- **Actual:** Native `long-error-after.png` shows a dark dismissal icon against the red error container.
- **Root cause / files:** `app.dart` sets a custom error background and text color but leaves the close icon on the normal snackbar color.
- **Fix:** Use the same corresponding foreground color for the close icon and notification text.
- **Retest:** PASS: minimum-size long-error screenshot shows a readable white close icon matching the error text; Final native walkthrough PASS.

## BUG-021 — Visualizer captions ignore light theme contrast

- **Area / severity:** Appearance / accessibility; medium.
- **Reproduction:** Open Visualizer and preview the alucard light theme.
- **Expected:** Small captions maintain at least 4.5:1 contrast on the theme background.
- **Actual:** Native theme inspection measures 2.405:1 for the fixed gray caption. Evidence: `visualizer-light-alucard.png`.
- **Root cause / files:** `visualizer.dart` hardcodes its subtitle and mode/theme caption gray despite the application supporting light palettes.
- **Fix:** Use the theme’s contrast-adjusted onSurfaceVariant foreground for both captions. Match the canvas frame to its actual background and use a theme-aware border to remove dark edge artifacts on light palettes.
- **Retest:** Native run15 passes all 34 modes, every theme, preview/cancel/apply, fullscreen resizing, transport and keyboard controls. Engine snapshots confirm each selection. Light-caption contrast ranges from 4.81:1 to 5.56:1. Final native walkthrough PASS.

## BUG-022 — Podcast catalog uses radio-station labels

- **Area / severity:** Provider browsing / terminology; low usability.
- **Reproduction:** Open Providers > Podcasts.
- **Expected:** Catalog and search labels describe podcast shows.
- **Actual:** Native podcast screenshot shows “Station catalog”; the search route also hardcodes “Station search”.
- **Root cause / files:** `provider_browser.dart` assumes every catalog provider is a radio provider.
- **Fix:** Use show labels when the provider advertises show browsing; keep radio station labels for radio.
- **Retest:** PASS: native run15 podcast catalog/search/episode and subscription cycle uses show labels; Final native walkthrough PASS.

## BUG-023 — Return does not execute a command-palette result

- **Area / severity:** Keyboard navigation; medium.
- **Reproduction:** F1, type “Open Queue”, press the physical/native Return key.
- **Expected:** Execute the matching command and close the palette.
- **Actual:** Native run13 records an X11 Return event, but the dialog stays open without executing the command.
- **Root cause / files:** `app.dart` provides clickable results but no submission handler for the command search field.
- **Fix:** Return executes the first matching visible command; unmatched queries remain editable.
- **Retest:** Native run15 passes Return submission, every palette action, transport shortcuts and text editing. Submission unit test passes. Final native walkthrough PASS.

## BUG-024 — Escape leaves provider search filtered

- **Area / severity:** Provider search / keyboard; medium.
- **Reproduction:** Providers > cliamp radio; type “no matches Café 春”, submit, press Escape.
- **Expected:** Clear the provider search and release editing focus.
- **Actual:** Native run13 retains the query and filtered results.
- **Root cause / files:** `provider_browser.dart` owns a separate search controller; the parent Escape handler only clears the main library controller.
- **Fix:** Handle Escape within provider browsing to clear its controller/filter and leave editing focus. A browser focus scope retains shortcut routing after Return submits and leaves the text field. Escape also returns from a submitted remote search to the preceding collection.
- **Retest:** Run14 exposed focus moving outside the browser after native Return; scope and remote-search return fixes plus a submission regression added. PASS: native Return/Escape clearing and return navigation in all four available provider browsers, including final8.

## BUG-025 — Subscribed search results still offer Add favorite

- **Area / severity:** Podcast subscriptions / state feedback; medium.
- **Reproduction:** Search a podcast feed URL, click Add favorite to subscribe.
- **Expected:** The result shows a filled favorite icon and Remove favorite action.
- **Actual:** Native run13 displays “[subscribed] Audit Podcast” but retains an empty heart and Add favorite tooltip.
- **Root cause / files:** `external/podcast/provider.go` sets the Favorite flag by list section prefix instead of the actual subscription state. Search/catalog rows therefore disagree with their subscribed label.
- **Fix:** Report actual subscription state in all playlist sections. Existing catalog/search assertions now require the correct flag.
- **Retest:** Full Go checks pass. Native run15 passes feed search, subscribe, filled-heart feedback, episode actions, every subscription menu action and unsubscribe. Final native walkthrough PASS.

## BUG-026 — Playback refresh discards loaded pages and selection

- **Area / severity:** Queue state / batch editing; high usability.
- **Reproduction:** Import 205 tracks, load the remaining five, select a range while playback advances.
- **Expected:** An unchanged track list retains its loaded pages and selection.
- **Actual:** Native run13 returns to “Load more · 200 of 205” and “0 selected” after selecting tracks.
- **Root cause / files:** `app.dart` handles every playlist revision with a first-page fetch that clears selection, including revisions caused by playback advancing.
- **Fix:** Background queue refreshes reload the previously loaded page count. Retain selection only when the ordered track paths match; changed lists clear selection and its range anchor.
- **Retest:** Unit test passes for 205 tracks, selection retained over a playback revision and cleared after actual removal. Native run14 retains all pages and the four-row Shift selection through playback and resize; subsequent fuzzy-search assertion corrected to expect exact-title ranking rather than substring-only filtering. Final native walkthrough PASS.

## BUG-027 — Singular provider counts use plural labels

- **Area / severity:** Provider browsing / copy; low.
- **Reproduction:** Subscribe to one podcast and open Subscriptions.
- **Expected:** “1 subscription”.
- **Actual:** Native screenshot displays “1 subscriptions”.
- **Root cause / files:** `provider_browser.dart` interpolates the plural collection kind regardless of count.
- **Fix:** Use a singular label for one item, including the irregular category/categories form.
- **Retest:** PASS: native subscription screenshots show the singular count; Final native walkthrough PASS.

## BUG-028 — Provider collection toolbar overflows short windows

- **Area / severity:** Providers / responsive layout; medium.
- **Reproduction:** Open cliamp radio > Lofi collection and resize to 640×480.
- **Expected:** Collection actions and the track list remain reachable.
- **Actual:** Native run15 reports a 15-pixel bottom overflow; the collection buttons leave no usable list viewport.
- **Root cause / files:** `provider_browser.dart` stacks fixed-height browser controls above an expanded list in the remaining short window space.
- **Fix:** Scroll the browser content when the available height is below its usable minimum, retaining a bounded viewport for the collection list.
- **Retest:** PASS: native run16 cliamp collection, pagination, playback and 640×480 resizing complete without overflow; all four available provider routes and the final native walkthrough PASS, including a physical drag that brings the first collection row fully into view.

## BUG-029 — Keyboard shortcuts lose focus after native file import

- **Area / severity:** File import / keyboard accessibility; medium.
- **Reproduction:** Ctrl+O, Choose files, select a file in the OS dialog, then press Ctrl+O again without clicking the library.
- **Expected:** The Add music dialog opens again.
- **Actual:** Native run16 records an OS Ctrl+O event, but no dialog opens after the previous successful import.
- **Root cause / files:** `app.dart` leaves keyboard focus outside the library shortcut scope when a native chooser closes and the import dialog is removed.
- **Fix:** Own the library focus scope and restore it when importing finishes, including cancellation and error returns.
- **Retest:** PASS: native run17 multiple-file selection and all four file/folder select/cancel workflows, including actual OS Ctrl+O between imports. Final native walkthrough PASS.

## BUG-030 — Library counts use plural for one item

- **Area / severity:** Queue and library count labels; low.
- **Reproduction:** Launch the release, Ctrl+O, add one local WAV.
- **Expected:** “1 track in queue” and singular one-item counts.
- **Actual:** Hero reads “1 tracks in queue”; the compact header and collection card counts use the same unconditional plural pattern.
- **Evidence:** Manual release `manual-final/imported.png`.
- **Root cause / files:** `desktop/lib/src/app.dart`, plural suffixes embedded in count labels.
- **Fix:** Choose singular for one track, play, playlist, artist or album in the library header and cards.
- **Retest:** PASS: independent final release shows “1 track in queue” and “1 track” on the reopened saved collection and cards. Final native walkthrough PASS.

## BUG-031 — Queue navigation can retain a stale revision

- **Area / severity:** Queue/play-next loading and batch actions; medium.
- **Reproduction:** Load a saved playlist while playback state changes, navigate to Queue, select the visible rows and Append. A runtime revision event arriving during the normal list request leaves the old revision attached to the loaded rows.
- **Expected:** Completed navigation reconciles with the latest queue state; subsequent actions use the displayed list's current revision.
- **Actual:** Append can show “operation cannot be performed in the current state” and leave the two-track queue unchanged. The native failure screenshot captures the two selected rows and error.
- **Evidence:** Final7 `batch-append-remove-replace-undo-failed.png`; a focused regression initially expected revision 84 but observed 41.
- **Root cause / files:** `desktop/lib/src/app.dart`: revision changes during loading suppress a new fetch, and the completion-time reconciliation previously ran only for quiet refreshes, not normal navigation or pagination.
- **Fix:** Reconcile revision changes after every queue/play-next load using a quiet follow-up. Keep the displayed revision while a refresh is pending; never replay a rejected stale mutation.
- **Tests:** `desktop/test/app_test.dart` publishes a revision during pending queue navigation, completes the old response, and checks the next row action uses the reconciled revision. Existing stale-row/no-replay and 205-row selection regressions remain enabled.
- **Retest:** PASS: failing-before/fixed-after unit regression; all 114 Flutter tests; native playlist and batch append/remove/replace/undo, save/prepend, and play-next reorder/clear retests. The uninterrupted final8 walkthrough and separate-process checks PASS.

## ENV-001 — Transient Flutter compositor resize timeout

- **Area / severity:** Linux headless rendering; low observed impact, unresolved external verification.
- **Reproduction:** Launch the baseline or final release under Xvfb/Mesa, with or without xfwm4. Repeatedly resize among 900×650, 640×480, 1280×940, 1600×500 and 640×1400, then open Add music.
- **Expected:** The compositor receives each new-sized frame within its deadline.
- **Actual:** Some transitions log `Timed out waiting for OpenGL frame of size …`; the next frame recovers and the inspected dialog remains correctly drawn and responsive.
- **Evidence:** Baseline 7 warnings and release 2f1aebb 3 warnings over equivalent 18-resize probes; also seen before the final probe. Final f0bf245 also reproduced the warning during native scaling. No associated Dart exception. The attempted release environment renderer switch was ignored and is not a verified workaround.
- **Root cause / files:** Flutter SDK `engine/src/flutter/shell/platform/linux/fl_compositor_opengl.cc`, framebuffer dimensions differ when its 100 ms wait expires. Reproduced before and after application changes.
- **Fix / blocker:** No application workaround or warning suppression applied. Resolving the renderer/driver timing requires upstream graphics-stack investigation and physical-GPU comparison unavailable on this headless cloud host. This remains explicitly unverified on native hardware.
- **Retest:** Reproduced in both baseline and final; restored frame, dialog interaction, and native close work. Application layout assertions continue to pass.
