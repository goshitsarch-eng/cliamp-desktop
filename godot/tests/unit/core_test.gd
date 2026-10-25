extends GdUnitTestSuite

const BS := "\\"
## GdUnit4 suite for the pure logic in core/.


func test_fuzzy_prefers_word_starts_and_runs() -> void:
	assert_int(Fuzzy.score("", "anything")).is_equal(0)
	assert_int(Fuzzy.score("xyz", "abc")).is_equal(-1)
	assert_bool(Fuzzy.score("ab", "ab cd") > Fuzzy.score("ab", "xaxb")).is_true()


func test_fuzzy_rank_keeps_source_order_for_ties() -> void:
	var ranked := Fuzzy.rank("a", ["a", "a", "b"], func(item: String) -> String: return item)
	assert_array(Array(ranked)).is_equal([0, 1])


func test_duration_formats_minutes_and_hours() -> void:
	assert_str(Util.duration(75)).is_equal("1:15")
	assert_str(Util.duration(3725)).is_equal("1:02:05")
	assert_str(Util.duration(null)).is_equal("0:00")


func test_unknown_duration_is_not_shown_as_zero() -> void:
	assert_str(Util.duration_or_unknown(null)).is_equal("--:--")
	assert_str(Util.duration_or_unknown(0)).is_equal("--:--")
	assert_str(Util.duration_or_unknown(20.0)).is_equal("0:20")


func test_count_of_rounds_json_floats_and_pluralizes() -> void:
	assert_str(Util.count_of(2.0, "track")).is_equal("2 tracks")
	assert_str(Util.count_of(1.0, "track")).is_equal("1 track")
	assert_str(Util.count_of(0, "album")).is_equal("0 albums")
	assert_str(Util.count_of(null, "play", "plays")).is_equal("0 plays")
	assert_str(LibraryLogic.collection_subtitle({"track_count": 2.0}, "local")).is_equal("2 tracks")
	assert_str(ProviderBrowse.item_subtitle({"track_count": 1.0})).is_equal("1 track")


func test_util_coerces_untyped_json() -> void:
	assert_float(Util.number("x", 4.0)).is_equal(4.0)
	assert_str(Util.text(null, "fallback")).is_equal("fallback")
	assert_int(Util.objects([{}, 3, {"a": 1}]).size()).is_equal(2)


func test_seek_time_parsing() -> void:
	assert_float(SeekDialog.parse_time("1:05")).is_equal(65.0)
	assert_float(SeekDialog.parse_time("1:00:00")).is_equal(3600.0)
	assert_float(SeekDialog.parse_time("90")).is_equal(90.0)
	assert_float(SeekDialog.parse_time("1:75")).is_equal(-1.0)
	assert_float(SeekDialog.parse_time("nope")).is_equal(-1.0)


func test_windows_argument_escaping_round_trips_quotes() -> void:
	assert_str(Proc.windows_escape('{"a":1}')).is_equal('{' + BS + '"a' + BS + '":1}')
	assert_str(Proc.windows_escape("C:" + BS + "dir" + BS)).is_equal("C:" + BS + "dir" + BS + BS)
	assert_array(Array(Proc.escape_arguments(PackedStringArray(["x"]), false))).is_equal(["x"])


func test_backend_sends_whole_numbers_as_integers() -> void:
	assert_str(Backend.encode_json({"if_revision": 7.0, "speed": 1.5})).is_equal('{"if_revision":7,"speed":1.5}')


func test_palette_keeps_contrast() -> void:
	var p := Palette.from_engine({"bg": "#ffffff", "fg": "#f0f0f0", "accent": "#fafafa"})
	assert_bool(p.dark).is_false()
	assert_bool(p.accent.get_luminance() < 0.9).is_true()


func test_palette_muted_text_stays_distinct_from_foreground() -> void:
	# catppuccin-latte: dark text on a light background, fg is a softer gray.
	var p := Palette.from_engine({"bg": "#eff1f5", "fg": "#686b80", "bright_fg": "#4c4f69", "accent": "#1a5cc8"})
	assert_bool(p.dark).is_false()
	assert_bool(p.muted.is_equal_approx(p.foreground)).is_false()
	assert_bool(Palette.relative_luminance(p.muted) > Palette.relative_luminance(p.foreground)).is_true()
	assert_float(Palette.relative_luminance(Color.WHITE)).is_equal_approx(1.0, 0.001)
	assert_float(Palette.relative_luminance(Color.BLACK)).is_equal_approx(0.0, 0.001)


func test_window_is_never_restored_minimized() -> void:
	assert_int(Prefs.persisted_mode(Window.MODE_MINIMIZED, Window.MODE_MAXIMIZED)).is_equal(Window.MODE_MAXIMIZED)
	assert_int(Prefs.persisted_mode(Window.MODE_MINIMIZED, Window.MODE_MINIMIZED)).is_equal(Window.MODE_WINDOWED)
	assert_int(Prefs.persisted_mode(Window.MODE_MAXIMIZED, Window.MODE_WINDOWED)).is_equal(Window.MODE_MAXIMIZED)


func test_playlist_name_validation_matches_the_engine() -> void:
	assert_str(LibraryLogic.playlist_name_error("Road trip")).is_equal("")
	assert_str(LibraryLogic.playlist_name_error("Café ☕ 日本語")).is_equal("")
	for bad in ["", "   ", ".", "..", "a/b", "a" + BS + "b", "x*y?", "a:b", "<a>", "p|q", "say \"hi\""]:
		assert_bool(LibraryLogic.playlist_name_error(bad) != "").is_true()


func test_header_count_line_pluralizes() -> void:
	assert_str(LibraryLogic.count_line(true, "tracks", 0, 1.0)).is_equal("1 track in queue")
	assert_str(LibraryLogic.count_line(true, "tracks", 0, 4.0)).is_equal("4 tracks in queue")
	assert_str(LibraryLogic.count_line(false, "history", 1, 0.0)).is_equal("1 play")
	assert_str(LibraryLogic.count_line(false, "playlists", 5, 0.0)).is_equal("5 playlists")
	assert_str(LibraryLogic.count_line(false, "albums", 1, 0.0)).is_equal("1 album")


func test_flat_bands_are_not_reported_as_custom() -> void:
	var flat := {"eq_preset": "Custom", "eq_bands": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]}
	assert_str(EqLogic.preset_or_flat(flat)).is_equal("Flat")
	var shaped := {"eq_preset": "Custom", "eq_bands": [3, 0, 0, 0, 0, 0, 0, 0, 0, 0]}
	assert_str(EqLogic.preset_or_flat(shaped)).is_equal("Custom")
	assert_str(EqLogic.preset_or_flat({"eq_preset": "Rock", "eq_bands": []})).is_equal("Rock")


func test_plugin_source_validation_mirrors_the_resolver() -> void:
	for good in ["bjarneo/cliamp-plugin-lastfm", "bjarneo/cliamp-plugin-lastfm@v1.0", "gitlab:user/my-visualizer", "codeberg:user/my-plugin@v1",
			"https://example.com/my-plugin.lua", "http://127.0.0.1:8000/a.lua?x=1"]:
		assert_str(PluginLogic.source_error(good)).is_equal("")
	for bad in ["", "   ", "not a url", "owner", "owner/", "/repo", "a/b/c", "ftp:user/repo", "https://example.com/", "https://example.com"]:
		assert_bool(PluginLogic.source_error(bad) != "").is_true()


func test_title_with_artist_drops_missing_artist() -> void:
	assert_str(LibraryLogic.title_with_artist("alpha", "")).is_equal("alpha")
	assert_str(LibraryLogic.title_with_artist("alpha", "  ")).is_equal("alpha")
	assert_str(LibraryLogic.title_with_artist("alpha", "Band")).is_equal("alpha · Band")


func test_theme_styles_switches_icon_buttons_and_dialogs() -> void:
	var dark := ThemeBuilder.build(Palette.new())
	assert_bool(dark.has_icon("checked", "CheckButton")).is_true()
	assert_bool(dark.has_icon("unchecked", "CheckButton")).is_true()
	assert_bool(dark.get_icon("checked", "CheckButton").get_width() > 16).is_true()
	assert_str(dark.get_type_variation_base("IconButton")).is_equal("Button")
	var icon_pad := (dark.get_stylebox("normal", "IconButton") as StyleBoxFlat).content_margin_left
	var text_pad := (dark.get_stylebox("normal", "Button") as StyleBoxFlat).content_margin_left
	assert_bool(icon_pad < text_pad).is_true()
	assert_bool(dark.has_stylebox("panel", "AcceptDialog")).is_true()
	assert_bool(dark.has_stylebox("panel", "PopupMenu")).is_true()


func test_light_theme_text_controls_follow_the_palette() -> void:
	var light := Palette.from_engine({"bg": "#eff1f5", "fg": "#686b80", "bright_fg": "#4c4f69", "accent": "#1a5cc8"})
	var theme := ThemeBuilder.build(light)
	for type_name in ["OptionButton", "MenuButton", "CheckButton", "TextEdit", "PopupMenu"]:
		assert_bool(theme.get_color("font_color", type_name).is_equal_approx(light.foreground)).is_true()
	assert_bool(theme.get_color("font_readonly_color", "TextEdit").is_equal_approx(light.foreground)).is_true()
	assert_bool(light.error.is_equal_approx(Palette.new().error)).is_false()
	assert_bool(Palette.relative_luminance(light.error) < 0.3).is_true()


func test_dialog_wrapping_labels_get_a_minimum_width() -> void:
	var box := VBoxContainer.new()
	var wrapped := Label.new()
	wrapped.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var fixed := Label.new()
	fixed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fixed.custom_minimum_size.x = 300
	var plain := Label.new()
	box.add_child(wrapped)
	box.add_child(fixed)
	box.add_child(plain)
	Dialogs._bound_wrapping_labels(box, 460.0)
	assert_float(wrapped.custom_minimum_size.x).is_equal(460.0)
	assert_float(fixed.custom_minimum_size.x).is_equal(300.0)
	assert_float(plain.custom_minimum_size.x).is_equal(0.0)
	box.free()
