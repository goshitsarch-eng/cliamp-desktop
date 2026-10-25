# Godot client architecture

A GDScript port of the Flutter app in `../desktop/lib/src/`. The Go `cliamp`
engine is unchanged; the client drives it through `autoload/backend.gd`.

## Layers

- `autoload/backend.gd` (`Backend`): runs `cliamp` commands. Failures are returned,
  not thrown: `Backend.failed(result)` then `result["error"]["code"|"message"]`.
  `await Backend.call_op(op, params)`, `setup_schema`, `save_provider`,
  `preferences_schema`, `save_preferences`, `plugin_action`, `read_frame`,
  `capabilities`, `snapshot`, `cancel_job`, `current_jobs()`, `owns_daemon()`,
  `restart_owned_engine()`. Signals: `jobs_changed(jobs: Array)` of `BackendJob`,
  `event_received(envelope)`, `spectrum_received`, `connection_lost`.
- `autoload/store.gd` (`Store`): shared UI state and `await Store.run(op, params,
  message)`, which returns the result Dictionary or `null` (error already toasted,
  state refreshed). Read `Store.state`, `Store.track()`, `Store.is_playing()`,
  `Store.position()`, `Store.supports(op)`, `Store.providers`, `Store.revision()`,
  `Store.filter`. Signals in the file header. `Store.notify(msg, is_error)`.
- `autoload/theme_builder.gd` (`ThemeBuilder.palette`: `Palette` with `background,
  surface, sidebar, foreground, muted, accent, secondary, on_accent()`),
  `palette_changed` signal. Use palette colors, never hard-coded colors.
- `autoload/prefs.gd` (`Prefs`): window state, `ui_scale`.
- `core/`: pure logic, no nodes (`Util`, `Fuzzy`, `Icons`, `Palette`, `BackendJob`).
  Put parsers and list logic here so they can be unit tested.
- `ui/`: `page.gd` (`Page` base), `pages.gd` (navigation table, defines each page's
  script path), `pages/*_page.gd`, `widgets/`, `dialogs.gd`.

## Conventions

- Build UI in code from Containers (`VBoxContainer`, `HBoxContainer`, `GridContainer`,
  `ScrollContainer`, `MarginContainer`, `PanelContainer`, `HSplitContainer`). No manual
  positioning except inside custom `_draw` widgets. Set `size_flags_*` for expansion.
- Every interactive control needs `accessibility_name` (and description if useful).
  `Icons.button(name, tooltip, callback)` sets it from the tooltip.
- Icons come from `Icons` (Material Icons Round, same names as Flutter's `Icons.*`
  without `_rounded`). Check a name exists: `IconGlyphs.CODEPOINTS`.
- Dialogs: `Dialogs.open/confirm/prompt/message/pick_paths` (native windows). Await them.
- Low-processor mode is on: only call `queue_redraw()` or update nodes when data
  changes. Never `_process` poll unless a visible animation needs it; use a `Timer`
  and stop it in `deactivate()`.
- Typed GDScript (`var x: int`, `-> void`). Use `Util.objects/object/number/text` to
  read engine JSON. Dictionary `.get()` on untyped JSON returns Variant.
- Match engine behavior of the Dart original exactly (operation names, params,
  revision guards). Dart file is the spec.
- No emojis in code or docs. Tabs for indentation. Comments only for non-obvious why.
- Long async work: guard against the page being freed or the user navigating away
  with a generation counter, like the Dart `_loadGeneration`.

## GDScript gotchas

- Lambdas cannot assign to captured locals; capture a Dictionary/Array and mutate it.
- `await` inside signal handlers is fine; the handler returns at the first await.
- `class_name` classes are global; nested `class` is allowed for local helpers.
- A script that does not parse prints an error and returns null from `load()`.

## Check your work

From `godot/`:

    GODOT="$LOCALAPPDATA/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7.2-stable_win64_console.exe"
    "$GODOT" --headless --path . --import --quit        # after adding class_name files
    "$GODOT" --headless --path . res://tools/check.tscn  # every .gd/.tscn must load; prints "check: 0 failure(s)"
    "$GODOT" --headless --path . --quit-after 30         # the app starts without script errors

Pages that need a running engine can be tried against a real `cliamp` build: set
`CLIAMP_BINARY`. The root Go package needs cgo audio codecs and does not build on
this Windows machine, so a binary may be unavailable; unit-test logic in `core/`
instead and keep UI code defensive.
