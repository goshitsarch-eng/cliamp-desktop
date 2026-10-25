class_name AnsiView
extends Control
## Draws an ANSI text frame as a monospace cell grid. It redraws only when a new
## frame arrives or the control changes size. grid_size() is the number of
## columns and rows to request from the engine for the current size.

signal grid_changed(columns: int, rows: int)

const MAX_COLUMNS := 240
const MAX_ROWS := 80

var default_fg := Color.WHITE
var default_bg := Color("0b0d12")
var font_size := 14:
	set(value):
		font_size = value
		_measure()
		queue_redraw()

var _rows: Array = []
var _regular: SystemFont
var _bold: SystemFont
var _cell := Vector2(8, 16)
var _grid := Vector2i(80, 24)


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(160, 80)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var names := PackedStringArray(["Cascadia Mono", "Menlo", "DejaVu Sans Mono", "monospace"])
	_regular = SystemFont.new()
	_regular.font_names = names
	_bold = SystemFont.new()
	_bold.font_names = names
	_bold.font_weight = 700
	_measure()
	resized.connect(_on_resized)


func _measure() -> void:
	_cell = Vector2(maxf(1.0, _regular.get_char_size("M".unicode_at(0), font_size).x), maxf(1.0, ceilf(_regular.get_height(font_size) * 1.05)))


func _on_resized() -> void:
	var g := _compute_grid()
	if g != _grid:
		_grid = g
		grid_changed.emit(g.x, g.y)
	queue_redraw()


func _compute_grid() -> Vector2i:
	return Vector2i(clampi(int(size.x / _cell.x), 1, MAX_COLUMNS), clampi(int(size.y / _cell.y), 1, MAX_ROWS))


## Columns and rows that fill the control, within the engine's limits.
func grid_size() -> Vector2i:
	if size.x < _cell.x or size.y < _cell.y:
		return Vector2i(80, 24)
	return _compute_grid()


func set_frame(frame: String) -> void:
	_rows = AnsiParser.parse(frame)
	queue_redraw()


func set_colors(fg: Color, bg: Color) -> void:
	default_fg = fg
	default_bg = bg
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), default_bg)
	# Center the frame in the control so a slightly larger control stays balanced.
	var widest := 0
	for r: AnsiParser.Row in _rows:
		widest = maxi(widest, r.chars.size())
	var origin := Vector2(maxf(0.0, floorf((size.x - widest * _cell.x) / 2.0)), maxf(0.0, floorf((size.y - _rows.size() * _cell.y) / 2.0)))
	var ascent := _regular.get_ascent(font_size)
	for y in _rows.size():
		var row: AnsiParser.Row = _rows[y]
		var top := origin.y + y * _cell.y
		if top > size.y:
			break
		for x in row.chars.size():
			var left := origin.x + x * _cell.x
			if left > size.x:
				break
			var cell_rect := Rect2(left, top, _cell.x, _cell.y)
			if row.bg[x] != AnsiParser.DEFAULT:
				draw_rect(cell_rect, _color(row.bg[x]))
			var ch := row.chars[x]
			if ch == " ":
				continue
			var color := default_fg if row.fg[x] == AnsiParser.DEFAULT else _color(row.fg[x])
			if _draw_block(ch, cell_rect, color):
				continue
			var font := _bold if row.bold[x] == 1 else _regular
			draw_string(font, Vector2(left, top + (_cell.y - _regular.get_height(font_size)) / 2.0 + ascent), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


## Block elements are drawn as rectangles so adjacent cells join without seams.
func _draw_block(ch: String, r: Rect2, color: Color) -> bool:
	match ch:
		"█":
			draw_rect(r, color)
		"▀":
			draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y / 2.0)), color)
		"▄":
			draw_rect(Rect2(r.position + Vector2(0, r.size.y / 2.0), Vector2(r.size.x, r.size.y / 2.0)), color)
		"▌":
			draw_rect(Rect2(r.position, Vector2(r.size.x / 2.0, r.size.y)), color)
		"▐":
			draw_rect(Rect2(r.position + Vector2(r.size.x / 2.0, 0), Vector2(r.size.x / 2.0, r.size.y)), color)
		_:
			return false
	return true


static func _color(rgb: int) -> Color:
	return Color((rgb >> 16 & 0xff) / 255.0, (rgb >> 8 & 0xff) / 255.0, (rgb & 0xff) / 255.0)
