## UI smoke test: runs the main scene in a real window, types some keys and
## saves screenshots. Needs a display (e.g. xvfb-run):
##   xvfb-run -s "-screen 0 1280x800x24" godot --path godot \
##       --script res://tests/ui_screenshot.gd -- --out=/tmp/shot [--keys="lll i"] [ROGUE ARGS]
## Keys: characters are typed as is; "\e" is Escape, "\n" Enter. Arguments that
## do not start with -- are Rogue's (e.g. -d), as for the game itself.
extends SceneTree

var _main: Node
var _frame := 0
var _out := "user://shot"
var _keys := "lllljjj i"
var _shots := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--keys="):
			_keys = a.substr(7).replace("\\e", char(27)).replace("\\n", "\n")
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 20:
		_shot()
	elif _frame >= 30 and _frame < 30 + _keys.length() * 4 and (_frame - 30) % 4 == 0:
		_type(_keys[(_frame - 30) / 4])
	elif _frame == 40 + _keys.length() * 4:
		_shot()
		quit(0)
	return false


func _type(c: String) -> void:
	var e := InputEventKey.new()
	e.pressed = true
	if c == char(27):
		e.keycode = KEY_ESCAPE
	elif c == "\n":
		e.keycode = KEY_ENTER
	else:
		e.unicode = c.unicode_at(0)
		e.keycode = OS.find_keycode_from_string(c.to_upper()) if c != " " else KEY_SPACE
	Input.parse_input_event(e)
	var r := e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)


func _shot() -> void:
	_shots += 1
	var img := root.get_texture().get_image()
	var path := "%s%d.png" % [_out, _shots]
	img.save_png(path)
	print("saved ", path)
