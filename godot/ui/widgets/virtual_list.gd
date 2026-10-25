class_name VirtualList
extends Container
## Fixed-row-height list that keeps only the visible rows as nodes. Rows are
## pooled: scrolling rebinds a row only when it is reused for another item, and
## nothing runs per frame. The owner supplies make_row() -> Control and
## bind_row(row, index).

var row_height := 66.0
var content_margin_left := 24.0
var content_margin_right := 24.0
var content_margin_bottom := 14.0
var make_row: Callable
var bind_row: Callable

var _count := 0
var _scroll := VScrollBar.new()
var _pool: Array[Control] = []
var _assigned: Array[int] = []
var _first := 0
var _bar_width := 0.0
var _mapped_size := 0


func _init() -> void:
	clip_contents = true
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.step = 1.0
	_scroll.value_changed.connect(func(_v: float) -> void: _sync())
	add_child(_scroll)
	_scroll.hide()


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(_on_focus_changed)


func count() -> int:
	return _count


## Sets the number of items. Keeps the scroll offset (clamped) unless `to_top`.
func set_count(n: int, to_top := false) -> void:
	_count = n
	if to_top:
		_scroll.value = 0.0
	_update_range()
	_invalidate()
	_sync()


## Binds every visible row again after the data or palette changed.
func rebind() -> void:
	_invalidate()
	_sync()


func scroll_to_top() -> void:
	_scroll.value = 0.0


## Scrolls so that item `index` is fully visible.
func ensure_visible(index: int) -> void:
	var top := index * row_height
	if top < _scroll.value:
		_scroll.value = top
	elif top + row_height > _scroll.value + size.y:
		_scroll.value = top + row_height - size.y


func visible_rows() -> int:
	var n := 0
	for i in _pool.size():
		if _pool[i].visible:
			n += 1
	return n


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_update_range()
		_sync()
	elif what == NOTIFICATION_SORT_CHILDREN:
		_layout()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var step := row_height * 0.75 * maxf(event.factor, 1.0)
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_scroll.value -= step
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_scroll.value += step
			accept_event()


func _update_range() -> void:
	var total := _count * row_height + content_margin_bottom
	_scroll.max_value = total
	_scroll.page = size.y
	var needs := total > size.y + 0.5
	if needs != _scroll.visible:
		_scroll.visible = needs
	_bar_width = _scroll.get_combined_minimum_size().x if needs else 0.0


func _invalidate() -> void:
	for i in _assigned.size():
		_assigned[i] = -1


## Reassigns pooled rows to the items in view and binds the ones that changed.
func _sync() -> void:
	if not make_row.is_valid() or not bind_row.is_valid():
		return
	var wanted := 0
	if size.y > 0.0 and _count > 0:
		wanted = mini(_count, int(ceil(size.y / row_height)) + 2)
	while _pool.size() < wanted:
		var row: Control = make_row.call()
		row.hide()
		add_child(row)
		_pool.append(row)
		_assigned.append(-1)
	_first = clampi(int(_scroll.value / row_height), 0, maxi(0, _count - 1))
	var pool_size := maxi(wanted, 1)
	if pool_size != _mapped_size:
		_mapped_size = pool_size
		_invalidate()
	for k in range(_first, mini(_count, _first + wanted)):
		var slot := k % pool_size
		var row := _pool[slot]
		if _assigned[slot] != k:
			_assigned[slot] = k
			bind_row.call(row, k)
		row.show()
	# Rows past the wanted count, or not holding an item in view, stay hidden.
	for slot in _pool.size():
		var k := _assigned[slot]
		if slot >= wanted or k < _first or k >= _first + wanted or k >= _count:
			_pool[slot].hide()
			_assigned[slot] = -1
	queue_sort()


func _layout() -> void:
	if _scroll.visible:
		fit_child_in_rect(_scroll, Rect2(size.x - _bar_width, 0, _bar_width, size.y))
	var width := maxf(0.0, size.x - _bar_width - content_margin_left - content_margin_right)
	for slot in _pool.size():
		var k := _assigned[slot]
		if k < 0:
			continue
		var y := k * row_height - _scroll.value
		fit_child_in_rect(_pool[slot], Rect2(content_margin_left, y, width, row_height - 4.0))


func _on_focus_changed(control: Control) -> void:
	if control == null or not is_ancestor_of(control):
		return
	for slot in _pool.size():
		if _assigned[slot] >= 0 and _pool[slot].is_ancestor_of(control):
			ensure_visible(_assigned[slot])
			return
