# Native desktop audit inventory

Baseline: `261ead0` (desktop 0.1.0+1). Targeted results below come from real native UI runs; the full post-fix regression is pending. Source inventory is not execution evidence. Individual UI actions and outcomes will be recorded by the native walkthrough, with manual native-dialog/window evidence separately. Remote accounts and non-Linux platforms must not be counted as passed.

| ID | Area | Reachable controls / states to exercise | Status |
|---|---|---|---|
| NAV | Navigation | Queue; Play next; Providers; Playlists; Favorites; History; Lyrics; Visualizer; Equalizer; Plugins; Settings; sidebar scrolling; compact rail; Open library | PASS: all 11 pages and compact return; final regression pending |
| HDR | Header | Search; Clear search; Background activity; Commands and shortcuts; Add music | Targeted native PASS: all header actions; final regression pending |
| SRC | Add music | Add to queue; Replace queue; Choose files; Choose folders; multi-line paths; Continue; Cancel; replacement confirmation; native picker select/cancel/location/multiple selection | Targeted native PASS: multiline Unicode/import modes, native multiple/select/cancel and focus return; final regression pending |
| QUE | Queue | Play row; double-click row; favorite; refresh; select tracks; checkbox; Shift-range; Select visible; Append; Play next; Replace queue; Save to playlist; Remove; Finish selecting; Undo; Save queue; Clear queue; Load more | Targeted native PASS: selection/actions/undo, 205 rows, pagination and Shift range; final regression pending |
| TRK | Track menu | Play next; Add to playlist; Move up; Move down; Remove from list; Related tracks; Go to artist; Track details; additional metadata | Targeted native PASS: details, play-next, moves/removal, save; local related/artist feedback; remote recommendations require account |
| NXT | Play next | All queue controls applicable to play-next; reorder; remove; clear and cancel; Undo; empty state | Targeted native PASS: batch/reorder/remove/clear/cancel/undo; final regression pending |
| PLS | Playlists | Provider selector; New playlist; create/cancel/duplicate/invalid name; open collection; Load collection; back; card menu Load/favorite/rename/delete; confirmation cancel; list Undo; track menu and selection | Targeted native PASS: create/open/load/favorite/rename/delete/undo and invalid names; final regression pending |
| SAV | Save picker | Destinations; new playlist; name validation; place at beginning; save/append; cancel; empty/read-only destinations | Targeted native PASS: existing/new destination, prepend/save/cancel; final regression pending |
| TLS | Playlist tools | Add files; Add folder; native selection/cancel; recursive switch; remove source confirmation; all six sort modes; Sort and save; move up/down; previous/next page; Undo; Refresh; Done | Targeted native PASS: six sorts, moves/undo, native files/folders, recursive/remove and 205-row paging; final regression pending |
| FAV | Favorites | Favorite/unfavorite via queue and current player; row playback/actions; empty state; refresh | Targeted native PASS: queue/current toggle, open/play/refresh and empty state; final regression pending |
| HIS | History | Play historical entry; actions; search; Clear history and cancellation; empty state; restart retention | Targeted native PASS: playback/actions, clear/cancel/repopulate; process-relaunch check pending |
| PRV | Provider browser | Provider picker; service setup; refresh; search/filter/clear; every advertised browse mode/route; back; playlists/artists/albums/genres; sort; play and append collection; Load more; retry; pin/favorite; details/artist/related | Targeted native PASS: local, Cliamp channels, public radio, podcast controls; private providers need credentials; final regression pending |
| RAD | Radio | Location allow/deny; country/category; pinned only; station favorite; list/play/append; unavailable catalog error | Targeted native PASS: 241-country catalog, tags, pin/filter/sort/load/play/append/search, consent dismiss/deny/allow; physical audio unverified |
| SUB | Subscriptions | Subscribed shows; subscribe/unsubscribe; play/append/queue show; newest episode; newest all; per-feed errors; played/resume badges | Targeted native PASS: fixture RSS search/subscribe, episode details/play/append/play-next, all five subscription actions, unsubscribe; final regression pending |
| PLY | Player | Play/pause; previous/next; shuffle; repeat all/one/off; favorite; seek drag; exact time click/dialog; volume drag; all seven speeds; download; lyrics; playback options | Targeted native PASS: all transport/options, seven speeds, seek/time, volume, download and lyrics; physical audio unverified |
| POP | Playback menu | Stop playback; Download track; Adjust volume + slider/apply/cancel; mono/stereo; shuffle; repeat | Targeted native PASS: stop/download/volume apply/cancel/mono/shuffle/repeat; final regression pending |
| LYR | Lyrics | Refresh/retry; no-track/no-result/error; synced/untimed/live; click line; scroll; follow toggle; delay/advance and bounds | PASS: embedded synced lyrics, seek, offset, follow, refresh; resize-follow fix pending; live/untimed native states pending |
| VIS | Visualizer | Mode picker every entry; theme picker every entry; Next; preview/apply/cancel; fullscreen; title toggle; fullscreen transport/seek/volume/keys; errors/retry | Targeted native PASS: all 34 modes and 23 themes verified against engine; preview/apply/cancel/fullscreen controls and keys; final regression pending |
| EQU | Equalizer | Every preset including Custom; all ten gain sliders; live saved curve; reset/return/reopen | PASS: preset selection and ten sliders; explicit Custom selection added for final run |
| SET | Settings | All preferences; mono; speed; output device picker; connected providers; Connect service; Setup instructions; Engine operations | Targeted native PASS: preferences, mono/speed, device list/help/setup/operations; actual hardware device switching unverified |
| PREF | Preferences | Search/group filter; every schema field below; booleans/options/text/numbers; validation; save; Done; restart/cancel; dirty close and reopen | PASS: 69 fields and invalid/save/reopen checks; final regression pending |
| AUTH | Provider setup/auth | Every service schema below; conditional auth choice; every field; masks; empty/invalid/long/Unicode; save failure; explicit offline save; restart/cancel; browser link/copy; auth cancel/retry/close | PASS: 14 service forms/all methods; live accounts unavailable |
| PLG | Plugins | Manage; source field; Review source; invalid source; source/hash/permissions display; approve checkbox; Install/trust/cancel; enable/disable; configure key/value/add/save/cancel; remove/cancel; restart; command and key action | PASS: reviewed fixture install/restart/configure/toggle/remove and command/key action; final regression pending |
| JOB | Activity | Running/completed/failed/canceled jobs; expand result; cancel; dialog close; status badge; elapsed time; long error | Targeted native PASS: result expansion/status/close, failed/completed jobs, live HTTP import cancellation; final regression pending |
| CMD | Command palette | Search; every desktop action; plugin actions; Enter selection; Escape/Close; focus return | Targeted native PASS: all 14 desktop actions, search/Return/Escape, plugin command; final regression pending |
| OPS | Engine operations | Operation selector/search; each parameter input; JSON validation; Run; success/error result; cancel/close; dangerous operations isolated | PASS: all 123 selector entries; JSON validation and queue query; final regression pending |
| KEY | Keyboard | Tab/ShiftTab; Enter; Escape; arrows; Space; Delete/Backspace text; Ctrl/Cmd O/F/J/Z/S/K; F1; CtrlX; Ctrl arrows; Alt arrows; plugin keys; fullscreen keys; focus trap/release | Targeted native PASS: focus/search/palette/compact, text editing, transport/fullscreen/plugin shortcuts and Linux MPRIS calls; platform hardware keys unverified |
| WIN | Window/layout | Fresh/empty/populated; 400x300; 640x480; 900x650; 1280x940; 1920x1080; wide/short; tall/narrow; maximize/restore; move; close/reopen; scaling; every dialog at small size | PASS: 11 screens at five sizes, dialogs, maximize/restore; tall size and final release/scaling pending |
| ERR | Failures | Unavailable/corrupt/unsupported/read-only sources; canceled edits; failed auth; stopped engine/reconnect; repeated/rapid navigation; long errors; logs | Targeted native PASS: unavailable/corrupt/unsupported/read-only sources, validation/long errors, provider save failure and engine recovery; final regression pending |
| PERS | Persistence | Preferences; playlists/order/dirs; favorites/history; saved EQ/theme/visualizer; resume where supported; app-owned vs attached close; window/view/filter reset behavior | Targeted native PASS: plugin restart retains queue/45-second position/pause/repeat/play-next; preferences save/reopen; separate-process library/history/preferences retest pending |

## Preference field inventory

The actual engine schema exposes 69 fields. Each must be reached and edited through the Preferences UI; a schema read alone is not a pass.

| Key | Label | Type | Options | Status |
|---|---|---|---|---|
| volume | Volume | number |  | PASS: native edit; final regression pending |
| volume_min | Volume min | number |  | PASS: native edit; final regression pending |
| repeat | Repeat | string | off, all, one | PASS: native edit; final regression pending |
| shuffle | Shuffle | bool |  | PASS: native edit; final regression pending |
| mono | Mono | bool |  | PASS: native edit; final regression pending |
| speed | Speed | number |  | PASS: native edit; final regression pending |
| auto_play | Auto play | bool |  | PASS: native edit; final regression pending |
| seek_large_step_sec | Seek large step sec | integer |  | PASS: native edit; final regression pending |
| lyrics_offset_ms | Lyrics offset ms | integer |  | PASS: native edit; final regression pending |
| provider | Provider | string |  | PASS: native edit; final regression pending |
| initial_directory | Initial directory | string |  | PASS: native edit; final regression pending |
| downloads.directory | Directory | string |  | PASS: native edit; final regression pending |
| sample_rate | Sample rate | integer | 0, 22050, 44100, 48000, 96000, 192000 | PASS: native edit; final regression pending |
| buffer_ms | Buffer ms | integer |  | PASS: native edit; final regression pending |
| resample_quality | Resample quality | integer |  | PASS: native edit; final regression pending |
| bit_depth | Bit depth | integer | 16, 32 | PASS: native edit; final regression pending |
| audio_device | Audio device | string |  | PASS: native edit; final regression pending |
| eq_preset | Eq preset | string |  | PASS: native edit; final regression pending |
| eq | Eq | equalizer |  | PASS: native edit; final regression pending |
| theme | Theme | string |  | PASS: native edit; final regression pending |
| visualizer | Visualizer | string |  | PASS: native edit; final regression pending |
| vis_rows | Vis rows | integer |  | PASS: native edit; final regression pending |
| vis_volume_linked | Vis volume linked | bool |  | PASS: native edit; final regression pending |
| simplified | Simplified | bool |  | PASS: native edit; final regression pending |
| hide_help_bar | Hide help bar | bool |  | PASS: native edit; final regression pending |
| hide_settings_pane | Hide settings pane | bool |  | PASS: native edit; final regression pending |
| show_metadata | Show metadata | bool |  | PASS: native edit; final regression pending |
| expanded | Expanded | bool |  | PASS: native edit; final regression pending |
| padding_horizontal | Padding horizontal | integer |  | PASS: native edit; final regression pending |
| padding_vertical | Padding vertical | integer |  | PASS: native edit; final regression pending |
| log_level | Log level | string | debug, info, warn, error | PASS: native edit; final regression pending |
| low_power | Low power | bool |  | PASS: native edit; final regression pending |
| plugins.disabled | Disabled | list |  | PASS: native edit; final regression pending |
| plugins.allowed_binaries | Allowed binaries | list |  | PASS: native edit; final regression pending |
| radio.country | Country | string |  | PASS: native edit; final regression pending |
| podcast.country | Country | string |  | PASS: native edit; final regression pending |
| navidrome.browse_sort | Browse sort | string |  | PASS: native edit; final regression pending |
| navidrome.format | Format | string |  | PASS: native edit; final regression pending |
| navidrome.scrobble | Scrobble | bool |  | PASS: native edit; final regression pending |
| lyrion.show_unplayable | Show unplayable | bool |  | PASS: native edit; final regression pending |
| spotify.enabled | Enabled | bool |  | PASS: native edit; final regression pending |
| spotify.client_id | Client id | string |  | PASS: native edit; final regression pending |
| spotify.bitrate | Bitrate | integer | 96, 160, 320 | PASS: native edit; final regression pending |
| qobuz.enabled | Enabled | bool |  | PASS: native edit; final regression pending |
| qobuz.quality | Quality | integer | 5, 6, 7, 27 | PASS: native edit; final regression pending |
| tidal.enabled | Enabled | bool |  | PASS: native edit; final regression pending |
| tidal.client_id | Client id | string |  | PASS: native edit; final regression pending |
| tidal.quality | Quality | string | , low, high, lossless, hires | PASS: native edit; final regression pending |
| ytmusic.enabled | Enabled | bool |  | PASS: native edit; final regression pending |
| ytmusic.client_id | Client id | string |  | PASS: native edit; final regression pending |
| ytmusic.cookies_from | Cookies from | string |  | PASS: native edit; final regression pending |
| ytmusic.expand_playlist | Expand playlist | bool |  | PASS: native edit; final regression pending |
| soundcloud.enabled | Enabled | bool |  | PASS: native edit; final regression pending |
| soundcloud.user | User | string |  | PASS: native edit; final regression pending |
| soundcloud.cookies_from | Cookies from | string |  | PASS: native edit; final regression pending |
| mixcloud.enabled | Enabled | bool |  | PASS: native edit; final regression pending |
| mixcloud.username | Username | string |  | PASS: native edit; final regression pending |
| mixcloud.cookies_from | Cookies from | string |  | PASS: native edit; final regression pending |
| mixcloud.styles | Styles | list |  | PASS: native edit; final regression pending |
| mixcloud.max_items | Max items | integer |  | PASS: native edit; final regression pending |
| mixcloud.stream_creators | Stream creators | integer |  | PASS: native edit; final regression pending |
| netease.enabled | Enabled | bool |  | PASS: native edit; final regression pending |
| netease.cookies_from | Cookies from | string |  | PASS: native edit; final regression pending |
| netease.user_id | User id | string |  | PASS: native edit; final regression pending |
| yandex.enabled | Enabled | bool |  | PASS: native edit; final regression pending |
| plex.libraries | Libraries | list |  | PASS: native edit; final regression pending |
| jellyfin.user_id | User id | string |  | PASS: native edit; final regression pending |
| emby.user_id | User id | string |  | PASS: native edit; final regression pending |
| audiobookshelf.libraries | Libraries | list |  | PASS: native edit; final regression pending |

## Service setup inventory

| Service | Key | Form / validation status | Live account status |
|---|---|---|---|
| Navidrome / Subsonic | navidrome | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Lyrion Music Server | lyrion | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Plex Media Server | plex | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Jellyfin | jellyfin | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Emby | emby | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Audiobookshelf | audiobookshelf | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Spotify (Premium) | spotify | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Qobuz | qobuz | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Tidal | tidal | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| NetEase Cloud Music | netease | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Mixcloud | mixcloud | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| YouTube Music | ytmusic | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| SoundCloud | soundcloud | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
| Yandex Music | yandex | PASS: all methods and input fields; native minimum size | Not available: no account credentials configured in this environment |
