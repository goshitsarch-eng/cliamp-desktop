extends Node
## Loads every script and scene under res:// and exits non-zero on any failure.
## Autoloads only exist when a scene runs, so this is a scene, not a --script.
## Run: godot --headless --path godot res://tools/check.tscn

var _failures := 0


func _ready() -> void:
	_walk("res://")
	print("check: %d failure(s)" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _walk(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_directories():
		if not name.begins_with(".") and name != "addons" and name != "build":
			_walk(dir_path.path_join(name))
	for file in dir.get_files():
		var path := dir_path.path_join(file)
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			if ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) == null:
				printerr("FAIL: ", path)
				_failures += 1
