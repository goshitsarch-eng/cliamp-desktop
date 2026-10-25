class_name AnsiParser
extends RefCounted
## Parses cursor-free ANSI text frames into a grid of cells. Only SGR sequences
## (colors, bold, reset) are interpreted; every other escape sequence is dropped.
## Colors are 0xRRGGBB ints, DEFAULT meaning "use the view's default".

const DEFAULT := -1
const PALETTE: PackedInt32Array = [
	0x000000, 0xcc4444, 0x44bb77, 0xddbb55, 0x5577dd, 0xbb66cc, 0x55bbbb, 0xdddddd,
	0x777777, 0xff6666, 0x77ee99, 0xffee88, 0x88aaff, 0xee99ff, 0x88eeee, 0xffffff,
]


class Row extends RefCounted:
	var chars := PackedStringArray()
	var fg := PackedInt32Array()
	var bg := PackedInt32Array()
	var bold := PackedByteArray()

	func add(ch: String, fg_color: int, bg_color: int, is_bold: bool) -> void:
		chars.append(ch)
		fg.append(fg_color)
		bg.append(bg_color)
		bold.append(1 if is_bold else 0)

	func text() -> String:
		return "".join(chars)


## 256-color palette index to 0xRRGGBB.
static func color256(code: int) -> int:
	code = clampi(code, 0, 255)
	if code < 16:
		return PALETTE[code]
	if code >= 232:
		var gray := clampi(8 + (code - 232) * 10, 0, 255)
		return (gray << 16) | (gray << 8) | gray
	var value := code - 16
	return (_channel(value / 36) << 16) | (_channel((value / 6) % 6) << 8) | _channel(value % 6)


static func _channel(n: int) -> int:
	return 0 if n == 0 else 55 + n * 40


## Returns Array of Row. A trailing empty line after a final newline is dropped.
static func parse(input: String) -> Array:
	var rows: Array = []
	var row := Row.new()
	var fg := DEFAULT
	var bg := DEFAULT
	var bold := false
	var i := 0
	var n := input.length()
	var pending_row := true
	while i < n:
		var ch := input[i]
		if ch == "\u001b":
			i += 1
			if i < n and input[i] == "[":
				i += 1
				var start := i
				# Parameter bytes 0x30-0x3f, intermediate 0x20-0x2f, final 0x40-0x7e.
				while i < n and input.unicode_at(i) >= 0x30 and input.unicode_at(i) <= 0x3f:
					i += 1
				while i < n and input.unicode_at(i) >= 0x20 and input.unicode_at(i) <= 0x2f:
					i += 1
				if i >= n:
					break
				var final := input[i]
				var params_text := input.substr(start, i - start)
				i += 1
				if final == "m":
					var state := _apply_sgr(params_text, fg, bg, bold)
					fg = state[0]
					bg = state[1]
					bold = state[2]
			continue
		if ch == "\n":
			rows.append(row)
			row = Row.new()
			pending_row = false
		elif ch == "\r":
			pass
		else:
			row.add(ch, fg, bg, bold)
			pending_row = true
		i += 1
	if pending_row and (row.chars.size() > 0 or rows.is_empty()):
		rows.append(row)
	return rows


static func _apply_sgr(params_text: String, fg: int, bg: int, bold: bool) -> Array:
	var params: Array[int] = []
	for part in params_text.replace(":", ";").split(";", true):
		params.append(int(part) if part.is_valid_int() else 0)
	if params.is_empty():
		params.append(0)
	var k := 0
	while k < params.size():
		var v := params[k]
		if v == 0:
			fg = DEFAULT
			bg = DEFAULT
			bold = false
		elif v == 1:
			bold = true
		elif v == 22:
			bold = false
		elif v == 39:
			fg = DEFAULT
		elif v == 49:
			bg = DEFAULT
		elif v >= 30 and v <= 37:
			fg = PALETTE[v - 30]
		elif v >= 90 and v <= 97:
			fg = PALETTE[v - 90 + 8]
		elif v >= 40 and v <= 47:
			bg = PALETTE[v - 40]
		elif v >= 100 and v <= 107:
			bg = PALETTE[v - 100 + 8]
		elif (v == 38 or v == 48) and k + 2 < params.size():
			var color := DEFAULT
			if params[k + 1] == 5:
				color = color256(params[k + 2])
				k += 2
			elif params[k + 1] == 2 and k + 4 < params.size():
				color = (clampi(params[k + 2], 0, 255) << 16) | (clampi(params[k + 3], 0, 255) << 8) | clampi(params[k + 4], 0, 255)
				k += 4
			if v == 38:
				fg = color
			else:
				bg = color
		k += 1
	return [fg, bg, bold]
