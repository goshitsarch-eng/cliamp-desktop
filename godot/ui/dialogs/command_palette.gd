class_name CommandPalette
extends VBoxContainer
## "Commands & keyboard shortcuts": a fuzzy-filtered list of actions.
## Up/Down move, Enter or a click runs the command.

var _actions: Array = []
var _edit: LineEdit
var _tree: Tree
var _empty: Label
var _visible: PackedInt32Array = PackedInt32Array()
var _chosen := -1


## `actions` is an array of [title: String, shortcut: String, callback: Callable].
## Returns the chosen Callable, or null when closed.
static func open(host: Node, actions: Array) -> Variant:
	var palette := CommandPalette.new(actions)
	await Dialogs.open(host, "Commands & keyboard shortcuts", palette, ["Close"], Vector2i(560, 0))
	if palette._chosen >= 0 and palette._chosen < actions.size():
		return actions[palette._chosen][2]
	return null


func _init(actions: Array = []) -> void:
	_actions = actions
	custom_minimum_size = Vector2(540, 420)
	add_theme_constant_override("separation", 12)
	_edit = LineEdit.new()
	_edit.placeholder_text = "Find a command"
	_edit.accessibility_name = "Find a command"
	_edit.clear_button_enabled = true
	_edit.text_changed.connect(_refilter)
	_edit.text_submitted.connect(func(_t: String) -> void: _activate())
	_edit.gui_input.connect(_on_edit_input)
	add_child(_edit)
	_tree = Tree.new()
	_tree.columns = 2
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.set_column_expand(1, false)
	_tree.set_column_custom_minimum_width(1, 140)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.accessibility_name = "Commands"
	_tree.item_mouse_selected.connect(func(_pos: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_activate())
	_tree.item_activated.connect(_activate)
	add_child(_tree)
	_empty = Label.new()
	_empty.text = "No matching commands"
	_empty.add_theme_color_override("font_color", ThemeBuilder.palette.muted)
	_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_empty)
	_refilter("")


func _ready() -> void:
	_edit.call_deferred("grab_focus")


func _refilter(text: String) -> void:
	_visible = Fuzzy.rank(text, _actions, func(a: Array) -> String: return a[0])
	_tree.clear()
	var root := _tree.create_item()
	var muted := ThemeBuilder.palette.muted
	for index in _visible:
		var item := _tree.create_item(root)
		item.set_text(0, _actions[index][0])
		item.set_text(1, _actions[index][1])
		item.set_text_alignment(1, HORIZONTAL_ALIGNMENT_RIGHT)
		item.set_custom_color(1, muted)
	_empty.visible = _visible.is_empty()
	_tree.visible = not _visible.is_empty()
	if not _visible.is_empty():
		root.get_child(0).select(0)


func _selected_row() -> int:
	var item := _tree.get_selected()
	return item.get_index() if item != null else 0


func _move(delta: int) -> void:
	if _visible.is_empty():
		return
	var row := posmod(_selected_row() + delta, _visible.size())
	var item := _tree.get_root().get_child(row)
	item.select(0)
	_tree.scroll_to_item(item)


func _activate() -> void:
	if _visible.is_empty():
		return
	_chosen = _visible[clampi(_selected_row(), 0, _visible.size() - 1)]
	DialogUtil.accept(self)


func _on_edit_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	match (event as InputEventKey).keycode:
		KEY_DOWN:
			_move(1)
			_edit.accept_event()
		KEY_UP:
			_move(-1)
			_edit.accept_event()
