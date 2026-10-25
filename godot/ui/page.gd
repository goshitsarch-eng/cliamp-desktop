class_name Page
extends MarginContainer
## Base class of every library page. A MarginContainer so its child fills it. The shell creates one instance per page,
## keeps it alive, and calls activate() each time the user navigates to it.
## Pages build their UI in code from containers and read shared state from Store.


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


## The page became visible: load its data.
func activate() -> void:
	pass


## The page was hidden. Stop timers and polling here.
func deactivate() -> void:
	pass


## Reload the visible list without clearing it (Ctrl+R, the refresh button).
func refresh() -> void:
	pass


## Ctrl+Z.
func undo() -> void:
	pass


## True while the page has an unsaved or running edit that Escape should not clear.
func handles_escape() -> bool:
	return false
