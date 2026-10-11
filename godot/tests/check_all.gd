## Load (compile) every GDScript file in the project. The engine prints parse
## and compile errors; exit status 1 if any script failed, 2 if the checker
## itself crashed.
## usage: godot --headless --path godot --script res://tests/check_all.gd
extends SceneTree

var _exit_code := 2


func _initialize() -> void:
	var failed := 0
	var files := _scan("res://")
	for f in files:
		var s: Variant = load(f)
		if not (s is GDScript):
			failed += 1
			printerr("FAILED: ", f)
	print("checked %d scripts, %d failed" % [files.size(), failed])
	_exit_code = 1 if failed else 0


func _process(_delta: float) -> bool:
	quit(_exit_code)
	return true


func _scan(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			out.append_array(_scan(dir.path_join(sub)))
	return out
