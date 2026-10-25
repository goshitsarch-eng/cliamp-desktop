class_name Artwork
extends PanelContainer
## Track artwork, or a gradient with an icon when there is none. Remote images
## load once and are cached by URL. Rounded by clipping to the panel style.

const GRADIENTS: Array = [
	["326b63", "253044"], ["675087", "293345"], ["86614c", "3e344c"], ["315b7e", "35444c"],
]
const MAX_BYTES := 8 * 1024 * 1024

static var _cache: Dictionary = {}

var large := false
var icon_name := "music_note"
var _track: Dictionary = {}
var _texture: Texture2D
var _canvas: Control
var _request: HTTPRequest
var _url := ""


func _init(is_large := false, icon := "music_note") -> void:
	large = is_large
	icon_name = icon
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(12 if large else 7)
	box.bg_color = Color.BLACK
	add_theme_stylebox_override("panel", box)
	custom_minimum_size = Vector2(46, 46) if large else Vector2(24, 24)
	_canvas = Control.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas.draw.connect(_draw_art)
	_canvas.resized.connect(_canvas.queue_redraw)
	add_child(_canvas)


## For use inside a parent that already clips its children: Godot does not
## support nested clip_children, so the art then keeps square corners.
func disable_clip() -> void:
	clip_children = CanvasItem.CLIP_CHILDREN_DISABLED
	var box := StyleBoxFlat.new()
	box.draw_center = false
	add_theme_stylebox_override("panel", box)


func set_track(track: Dictionary) -> void:
	if track.hash() == _track.hash():
		return
	_track = track
	_texture = null
	var url := Util.text(track.get("album_art_url"))
	_url = url
	if _cache.has(url):
		_texture = _cache[url]
	elif url.begins_with("http://") or url.begins_with("https://"):
		_fetch(url)
	elif url.begins_with("file://"):
		_load_file(url)
	_canvas.queue_redraw()


func _seed() -> int:
	var total := 0
	for byte in Util.text(_track.get("title"), Util.text(_track.get("path"), "cliamp")).to_utf16_buffer():
		total += byte
	return total


func _draw_art() -> void:
	var rect := Rect2(Vector2.ZERO, _canvas.size)
	if _texture != null:
		_canvas.draw_texture_rect(_texture, rect, false)
		return
	var pair: Array = GRADIENTS[_seed() % 4]
	var a := Color(pair[0])
	var b := Color(pair[1])
	_canvas.draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([a, a.lerp(b, 0.5), b, a.lerp(b, 0.5)]))
	if large:
		_canvas.draw_arc(Vector2(rect.size.x - 4, 4), 52, 0, TAU, 40, Color(1, 1, 1, 0.07), 20.0)
	var size := 46 if large else 21
	var font := Icons.font()
	var glyph := Icons.glyph(icon_name)
	var extent := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	_canvas.draw_string(font, Vector2((rect.size.x - extent.x) / 2.0, (rect.size.y + font.get_ascent(size) - font.get_descent(size)) / 2.0),
		glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 0.65))


func _fetch(url: String) -> void:
	if _request == null:
		_request = HTTPRequest.new()
		_request.body_size_limit = MAX_BYTES
		_request.request_completed.connect(_on_request_completed)
		add_child(_request)
	_request.cancel_request()
	_request.request(url)


func _on_request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	var kind := ""
	for h in headers:
		if h.to_lower().begins_with("content-type:"):
			kind = h.to_lower()
	if kind.contains("png"):
		err = image.load_png_from_buffer(body)
	elif kind.contains("webp"):
		err = image.load_webp_from_buffer(body)
	else:
		err = image.load_jpg_from_buffer(body)
		if err != OK:
			err = image.load_png_from_buffer(body)
	if err == OK:
		_store(_url, image)


func _load_file(url: String) -> void:
	var path := url.trim_prefix("file://").uri_decode()
	if OS.get_name() == "Windows" and path.length() > 2 and path[0] == "/" and path[2] == ":":
		path = path.substr(1)
	var image := Image.load_from_file(path)
	if image != null:
		_store(url, image)


func _store(url: String, image: Image) -> void:
	var texture := ImageTexture.create_from_image(image)
	if _cache.size() > 200:
		_cache.clear()
	_cache[url] = texture
	if url == _url:
		_texture = texture
		_canvas.queue_redraw()
