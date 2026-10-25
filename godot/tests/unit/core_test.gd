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
