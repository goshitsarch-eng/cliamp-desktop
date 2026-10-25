# Interactive audit scenarios

Scenarios that drive the real shell against a real `cliamp` engine in a window
(not `--headless`), with mouse and key events, layout lint and screenshots. They are
tools, not CI tests: see "Validate" in `docs/desktop.md` for how to run them.

Each scenario extends `tests/audit_kit.gd`. Output goes to `SHOT_DIR`
(screenshots and `findings.txt`). `MUSIC` is a folder of a few audio files and
`SHOT_WAV` one WAV file. Use a fresh `CLIAMP_CONFIG_DIR` per run, because the
engine persists shuffle, repeat and volume.
