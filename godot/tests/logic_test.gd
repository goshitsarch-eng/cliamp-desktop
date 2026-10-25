extends Node
## Headless checks for ANSI parsing, lyric timing and EQ mapping.
## Run: godot --headless --path godot res://tests/logic_test.tscn

var _failures := 0


func _ok(cond: bool, label: String) -> void:
	if not cond:
		printerr("FAIL: ", label)
		_failures += 1


func _ready() -> void:
	_ansi()
	_lyrics()
	_eq()
	print("logic_test: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _ansi() -> void:
	var rows := AnsiParser.parse("\u001b[31mab\u001b[0m c\n\u001b[1;38;2;1;2;3mX\u001b[48;5;196mY\u001b[39;49m\u001b[2J\u001b[Hz\n")
	_ok(rows.size() == 2, "ansi row count")
	var r0: AnsiParser.Row = rows[0]
	_ok(r0.text() == "ab c", "ansi text")
	_ok(r0.fg[0] == 0xcc4444 and r0.fg[1] == 0xcc4444, "ansi 16 fg")
	_ok(r0.fg[2] == AnsiParser.DEFAULT, "ansi reset")
	var r1: AnsiParser.Row = rows[1]
	_ok(r1.text() == "XYz", "ansi unknown csi dropped")
	_ok(r1.fg[0] == 0x010203 and r1.bold[0] == 1, "ansi truecolor bold")
	_ok(r1.bg[1] == AnsiParser.color256(196) and r1.bg[1] == 0xff0000, "ansi 256 bg")
	_ok(r1.fg[2] == AnsiParser.DEFAULT and r1.bg[2] == AnsiParser.DEFAULT, "ansi default colors")
	_ok(AnsiParser.color256(232) == 0x080808 and AnsiParser.color256(15) == 0xffffff, "ansi grays")
	_ok(AnsiParser.parse("").size() == 1, "ansi empty frame has one row")


func _lyrics() -> void:
	var lines: Array = [{"start": 0.0, "text": "a"}, {"start": 5.0, "text": "b"}, {"start": 10.0, "text": "c"}]
	_ok(LyricsLogic.is_synced(lines, false), "lyrics synced")
	_ok(not LyricsLogic.is_synced(lines, true), "lyrics realtime")
	_ok(not LyricsLogic.is_synced([{"start": 0.0}, {"text": "x"}], false), "lyrics untimed")
	_ok(LyricsLogic.active_index(lines, 4.9, 0) == 0, "lyrics before second")
	_ok(LyricsLogic.active_index(lines, 5.0, 0) == 1, "lyrics at second")
	_ok(LyricsLogic.active_index(lines, 4.9, 250) == 1, "lyrics offset advances")
	_ok(LyricsLogic.active_index(lines, 20.0, 0) == 2, "lyrics last")
	_ok(LyricsLogic.active_index(lines, -1.0, 0) == -1, "lyrics none")
	_ok(is_equal_approx(LyricsLogic.seek_target(lines[1], 500), 4.5), "lyrics seek target")
	_ok(LyricsLogic.seek_target({"start": 0.2}, 500) == 0.0, "lyrics seek clamp")
	_ok(LyricsLogic.clamp_offset(20000) == 10000 and LyricsLogic.clamp_offset(-20000) == -10000, "lyrics offset clamp")
	_ok(LyricsLogic.offset_text(250) == "+250 ms" and LyricsLogic.offset_text(-250) == "-250 ms", "lyrics offset text")
	_ok(LyricsLogic.track_changed({"path": "a"}, {"path": "b"}) and not LyricsLogic.track_changed({"path": "a", "x": 1}, {"path": "a"}), "lyrics track change")


func _eq() -> void:
	_ok(EqLogic.band_values({}).size() == 10, "eq default bands")
	_ok(EqLogic.band_values({"eq_bands": [1, 2.5]})[1] == 2.5 and EqLogic.band_values({"eq_bands": [1]})[5] == 0.0, "eq band padding")
	_ok(EqLogic.snap_db(3.4) == 3.0 and EqLogic.snap_db(99.0) == 12.0 and EqLogic.snap_db(-99.0) == -12.0, "eq snap")
	_ok(EqLogic.db_at(0.0, 100.0) == 12.0 and EqLogic.db_at(100.0, 100.0) == -12.0 and EqLogic.db_at(50.0, 100.0) == 0.0, "eq db_at")
	_ok(EqLogic.y_of(12.0, 100.0) == 0.0 and EqLogic.y_of(-12.0, 100.0) == 100.0, "eq y_of")
	_ok(EqLogic.db_text(-3.4) == "-3 dB", "eq text")
	_ok(EqLogic.preset_or_flat({"eq_preset": "Rock"}) == "Rock" and EqLogic.preset_or_flat({"eq_preset": "x"}) == "Flat", "eq preset")
