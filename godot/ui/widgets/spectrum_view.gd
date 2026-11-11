class_name SpectrumView
extends Control
## Forty rounded bars from the engine's spectrum bands, accent to secondary.
## Redraws only when new bands arrive, which suits low-processor mode.

const COUNT := 40

var bands := PackedFloat32Array()
var playing := false
var _box := StyleBoxFlat.new()


func _init() -> void:
	_box.set_corner_radius_all(3)


func _ready() -> void:
	custom_minimum_size = Vector2(160, 82)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Store.bands_changed.connect(_on_bands)
	Store.state_changed.connect(_on_state)
	ThemeBuilder.palette_changed.connect(func(_p: Palette) -> void: queue_redraw())
	bands = Store.bands
	playing = Store.is_playing()


func _on_bands(values: PackedFloat32Array) -> void:
	bands = values
	if is_visible_in_tree():
		queue_redraw()


func _on_state(_state: Dictionary) -> void:
	var now := Store.is_playing()
	if now != playing:
		playing = now
		queue_redraw()


func _draw() -> void:
	var palette := ThemeBuilder.palette
	var bar := size.x / COUNT
	for i in COUNT:
		var value := 0.0
		if not bands.is_empty() and playing:
			value = clampf(bands[clampi(i * bands.size() / COUNT, 0, bands.size() - 1)], 0.0, 1.0)
		var h := maxf(2.0, value * size.y)
		var color := palette.accent.lerp(palette.secondary, float(i) / (COUNT - 1))
		_box.bg_color = color
		draw_style_box(_box, Rect2(i * bar, (size.y - h) / 2.0, maxf(1.0, bar - 3.0), h))
