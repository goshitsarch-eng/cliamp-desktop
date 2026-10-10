# Native desktop audit inventory

Baseline: `261ead0` (desktop 0.1.0+1). Final application: `f0bf245`. The complete post-fix Linux walkthrough and relaunch phases pass: 266 native stages. [Verification evidence](verification.json) records the results. Source inventory alone is not execution evidence; authenticated accounts, native Windows/macOS, physical audio/GPU and ENV-001 remain explicitly outside a clean verification claim.

| ID | Area | Reachable controls / states to exercise | Status |
|---|---|---|---|
| NAV | Navigation | Queue; Play next; Providers; Playlists; Favorites; History; Lyrics; Visualizer; Equalizer; Plugins; Settings; sidebar scrolling; compact rail; Open library | PASS: all 11 pages and compact return; final combined run PASS |
| HDR | Header | Search; Clear search; Background activity; Commands and shortcuts; Add music | PASS: all header actions; final combined run PASS |
| SRC | Add music | Add to queue; Replace queue; Choose files; Choose folders; multi-line paths; Continue; Cancel; replacement confirmation; native picker select/cancel/location/multiple selection | PASS: multiline Unicode/import modes, native multiple/select/cancel and focus return; final combined run PASS |
| QUE | Queue | Play row; double-click row; favorite; refresh; select tracks; checkbox; Shift-range; Select visible; Append; Play next; Replace queue; Save to playlist; Remove; Finish selecting; Undo; Save queue; Clear queue; Load more | PASS: selection/actions/undo, 205 rows, pagination and Shift range; final combined run PASS |
| TRK | Track menu | Play next; Add to playlist; Move up; Move down; Remove from list; Related tracks; Go to artist; Track details; additional metadata | PASS: details, play-next, moves/removal, save; local related/artist feedback; remote recommendations require account |
| NXT | Play next | All queue controls applicable to play-next; reorder; remove; clear and cancel; Undo; empty state | PASS: batch/reorder/remove/clear/cancel/undo; final combined run PASS |
| PLS | Playlists | Provider selector; New playlist; create/cancel/duplicate/invalid name; open collection; Load collection; back; card menu Load/favorite/rename/delete; confirmation cancel; list Undo; track menu and selection | PASS: create/open/load/favorite/rename/delete/undo and invalid names; final combined run PASS |
| SAV | Save picker | Destinations; new playlist; name validation; place at beginning; save/append; cancel; empty/read-only destinations | PASS: existing/new destination, prepend/save/cancel; final combined run PASS |
| TLS | Playlist tools | Add files; Add folder; native selection/cancel; recursive switch; remove source confirmation; all six sort modes; Sort and save; move up/down; previous/next page; Undo; Refresh; Done | PASS: six sorts, moves/undo, native files/folders, recursive/remove and 205-row paging; final combined run PASS |
| FAV | Favorites | Favorite/unfavorite via queue and current player; row playback/actions; empty state; refresh | PASS: queue/current toggle, open/play/refresh and empty state; final combined run PASS |
| HIS | History | Play historical entry; actions; search; Clear history and cancellation; empty state; restart retention | PASS: playback/actions, clear/cancel/repopulate; process-relaunch retention PASS |
| PRV | Provider browser | Provider picker; service setup; refresh; search/filter/clear; every advertised browse mode/route; back; playlists/artists/albums/genres; sort; play and append collection; Load more; retry; pin/favorite; details/artist/related | PASS: local, Cliamp channels, public radio, podcast controls; private providers need credentials; final combined run PASS |
| RAD | Radio | Location allow/deny; country/category; pinned only; station favorite; list/play/append; unavailable catalog error | PASS: 241-country catalog, tags, pin/filter/sort/load/play/append/search, consent dismiss/deny/allow; physical audio unverified |
| SUB | Subscriptions | Subscribed shows; subscribe/unsubscribe; play/append/queue show; newest episode; newest all; per-feed errors; played/resume badges | PASS: fixture RSS search/subscribe, episode details/play/append/play-next, all five subscription actions, unsubscribe; final combined run PASS |
| PLY | Player | Play/pause; previous/next; shuffle; repeat all/one/off; favorite; seek drag; exact time click/dialog; volume drag; all seven speeds; download; lyrics; playback options | PASS: all transport/options, seven speeds, seek/time, volume, download and lyrics; physical audio unverified |
| POP | Playback menu | Stop playback; Download track; Adjust volume + slider/apply/cancel; mono/stereo; shuffle; repeat | PASS: stop/download/volume apply/cancel/mono/shuffle/repeat; final combined run PASS |
| LYR | Lyrics | Refresh/retry; no-track/no-result/error; synced/untimed/live; click line; scroll; follow toggle; delay/advance and bounds | PASS: synced/untimed/live-labeled states, seek, both offset limits, follow, refresh and resize-follow |
| VIS | Visualizer | Mode picker every entry; theme picker every entry; Next; preview/apply/cancel; fullscreen; title toggle; fullscreen transport/seek/volume/keys; errors/retry | PASS: all 34 modes and 23 themes verified against engine; preview/apply/cancel/fullscreen controls and keys; final combined run PASS |
| EQU | Equalizer | Every preset including Custom; all ten gain sliders; live saved curve; reset/return/reopen | PASS: all presets including Custom, ten sliders, reset and reopen |
| SET | Settings | All preferences; mono; speed; output device picker; connected providers; Connect service; Setup instructions; Engine operations | PASS: preferences, mono/speed, device list/help/setup/operations; actual hardware device switching unverified |
| PREF | Preferences | Search/group filter; every schema field below; booleans/options/text/numbers; validation; save; Done; restart/cancel; dirty close and reopen | PASS: 69 fields, all section collapse/expand controls and invalid/save/reopen checks; final combined run PASS |
| AUTH | Provider setup/auth | Every service schema below; conditional auth choice; every field; masks; empty/invalid/long/Unicode; save failure; explicit offline save; restart/cancel; browser link/copy; auth cancel/retry/close | PASS: 14 service forms/all methods; live accounts unavailable |
| PLG | Plugins | Manage; source field; Review source; invalid source; source/hash/permissions display; approve checkbox; Install/trust/cancel; enable/disable; configure key/value/add/save/cancel; remove/cancel; restart; command and key action | PASS: reviewed fixture install/restart/configure/toggle/remove and command/key action; final combined run PASS |
| JOB | Activity | Running/completed/failed/canceled jobs; expand result; cancel; dialog close; status badge; elapsed time; long error | PASS: result expansion/status/close, failed/completed jobs, live HTTP import cancellation; final combined run PASS |
| CMD | Command palette | Search; every desktop action; plugin actions; Enter selection; Escape/Close; focus return | PASS: all 14 desktop actions, search/Return/Escape, plugin command; final combined run PASS |
| OPS | Engine operations | Operation selector/search; each parameter input; JSON validation; Run; success/error result; cancel/close; dangerous operations isolated | PASS: all 123 selector entries; JSON validation and queue query; final combined run PASS |
| KEY | Keyboard | Tab/ShiftTab; Enter; Escape; arrows; Space; Delete/Backspace text; Ctrl/Cmd O/F/J/Z/S/K; F1; CtrlX; Ctrl arrows; Alt arrows; plugin keys; fullscreen keys; focus trap/release | PASS: focus/search/palette/compact, text editing, transport/fullscreen/plugin shortcuts and Linux MPRIS calls; Cmd shortcuts and platform hardware keys unverified |
| WIN | Window/layout | Fresh/empty/populated; 400x300; 640x480; 900x650; 1280x940; wide/short; tall/narrow; maximize/restore; move; close/reopen; scaling; every dialog at small size | PASS: 11 screens at six requested sizes, dialogs, native maximize/restore, final release relaunch and 200% scaling; ENV-001 documented |
| ERR | Failures | Unavailable/corrupt/unsupported/read-only sources; canceled edits; failed auth; stopped engine/reconnect; repeated/rapid navigation; long errors; logs | PASS: unavailable/corrupt/unsupported/read-only sources, validation/long errors, provider save failure and engine recovery; final combined run PASS |
| PERS | Persistence | Preferences; playlists/order/dirs; favorites/history; saved EQ/theme/visualizer; resume where supported; app-owned shutdown; external-engine ownership (backend tests); window/view/filter reset behavior | PASS: plugin restart retains queue/45-second position/pause/repeat/play-next; preferences save/reopen; separate-process library/history/preferences PASS; window/view reset observed and documented |

## Preference field inventory

The actual engine schema exposes 69 fields. Each must be reached and edited through the Preferences UI; a schema read alone is not a pass.

| Key | Label | Type | Options | Status |
|---|---|---|---|---|
| volume | Volume | number |  | PASS: edited in the final native run |
| volume_min | Volume min | number |  | PASS: edited in the final native run |
| repeat | Repeat | string | off, all, one | PASS: edited in the final native run |
| shuffle | Shuffle | bool |  | PASS: edited in the final native run |
| mono | Mono | bool |  | PASS: edited in the final native run |
| speed | Speed | number |  | PASS: edited in the final native run |
| auto_play | Auto play | bool |  | PASS: edited in the final native run |
| seek_large_step_sec | Seek large step sec | integer |  | PASS: edited in the final native run |
| lyrics_offset_ms | Lyrics offset ms | integer |  | PASS: edited in the final native run |
| provider | Provider | string |  | PASS: edited in the final native run |
| initial_directory | Initial directory | string |  | PASS: edited in the final native run |
| downloads.directory | Directory | string |  | PASS: edited in the final native run |
| sample_rate | Sample rate | integer | 0, 22050, 44100, 48000, 96000, 192000 | PASS: edited in the final native run |
| buffer_ms | Buffer ms | integer |  | PASS: edited in the final native run |
| resample_quality | Resample quality | integer |  | PASS: edited in the final native run |
| bit_depth | Bit depth | integer | 16, 32 | PASS: edited in the final native run |
| audio_device | Audio device | string |  | PASS: edited in the final native run |
| eq_preset | Eq preset | string |  | PASS: edited in the final native run |
| eq | Eq | equalizer |  | PASS: edited in the final native run |
| theme | Theme | string |  | PASS: edited in the final native run |
| visualizer | Visualizer | string |  | PASS: edited in the final native run |
| vis_rows | Vis rows | integer |  | PASS: edited in the final native run |
| vis_volume_linked | Vis volume linked | bool |  | PASS: edited in the final native run |
| simplified | Simplified | bool |  | PASS: edited in the final native run |
| hide_help_bar | Hide help bar | bool |  | PASS: edited in the final native run |
| hide_settings_pane | Hide settings pane | bool |  | PASS: edited in the final native run |
| show_metadata | Show metadata | bool |  | PASS: edited in the final native run |
| expanded | Expanded | bool |  | PASS: edited in the final native run |
| padding_horizontal | Padding horizontal | integer |  | PASS: edited in the final native run |
| padding_vertical | Padding vertical | integer |  | PASS: edited in the final native run |
| log_level | Log level | string | debug, info, warn, error | PASS: edited in the final native run |
| low_power | Low power | bool |  | PASS: edited in the final native run |
| plugins.disabled | Disabled | list |  | PASS: edited in the final native run |
| plugins.allowed_binaries | Allowed binaries | list |  | PASS: edited in the final native run |
| radio.country | Country | string |  | PASS: edited in the final native run |
| podcast.country | Country | string |  | PASS: edited in the final native run |
| navidrome.browse_sort | Browse sort | string |  | PASS: edited in the final native run |
| navidrome.format | Format | string |  | PASS: edited in the final native run |
| navidrome.scrobble | Scrobble | bool |  | PASS: edited in the final native run |
| lyrion.show_unplayable | Show unplayable | bool |  | PASS: edited in the final native run |
| spotify.enabled | Enabled | bool |  | PASS: edited in the final native run |
| spotify.client_id | Client id | string |  | PASS: edited in the final native run |
| spotify.bitrate | Bitrate | integer | 96, 160, 320 | PASS: edited in the final native run |
| qobuz.enabled | Enabled | bool |  | PASS: edited in the final native run |
| qobuz.quality | Quality | integer | 5, 6, 7, 27 | PASS: edited in the final native run |
| tidal.enabled | Enabled | bool |  | PASS: edited in the final native run |
| tidal.client_id | Client id | string |  | PASS: edited in the final native run |
| tidal.quality | Quality | string | , low, high, lossless, hires | PASS: edited in the final native run |
| ytmusic.enabled | Enabled | bool |  | PASS: edited in the final native run |
| ytmusic.client_id | Client id | string |  | PASS: edited in the final native run |
| ytmusic.cookies_from | Cookies from | string |  | PASS: edited in the final native run |
| ytmusic.expand_playlist | Expand playlist | bool |  | PASS: edited in the final native run |
| soundcloud.enabled | Enabled | bool |  | PASS: edited in the final native run |
| soundcloud.user | User | string |  | PASS: edited in the final native run |
| soundcloud.cookies_from | Cookies from | string |  | PASS: edited in the final native run |
| mixcloud.enabled | Enabled | bool |  | PASS: edited in the final native run |
| mixcloud.username | Username | string |  | PASS: edited in the final native run |
| mixcloud.cookies_from | Cookies from | string |  | PASS: edited in the final native run |
| mixcloud.styles | Styles | list |  | PASS: edited in the final native run |
| mixcloud.max_items | Max items | integer |  | PASS: edited in the final native run |
| mixcloud.stream_creators | Stream creators | integer |  | PASS: edited in the final native run |
| netease.enabled | Enabled | bool |  | PASS: edited in the final native run |
| netease.cookies_from | Cookies from | string |  | PASS: edited in the final native run |
| netease.user_id | User id | string |  | PASS: edited in the final native run |
| yandex.enabled | Enabled | bool |  | PASS: edited in the final native run |
| plex.libraries | Libraries | list |  | PASS: edited in the final native run |
| jellyfin.user_id | User id | string |  | PASS: edited in the final native run |
| emby.user_id | User id | string |  | PASS: edited in the final native run |
| audiobookshelf.libraries | Libraries | list |  | PASS: edited in the final native run |

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
