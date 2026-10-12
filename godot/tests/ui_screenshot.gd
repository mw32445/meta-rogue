## UI smoke test: runs the main scene in a real window, types some keys and
## saves screenshots. Needs a display (e.g. xvfb-run):
##   xvfb-run -s "-screen 0 1280x800x24" godot --path godot \
##       --script res://tests/ui_screenshot.gd -- --out=/tmp/shot [--keys="lll i"] [--guild]
##       [--sample-hof=N] [--shot-at=K,...] [--video-cfg=PATH] [ROGUE ARGS]
## Keys: characters are typed as is; "\e" is Escape, "\n" Enter, "\f" F10 (the video
## settings) and "\a" Alt+Enter (fullscreen on and off). Arguments that do not start
## with -- are Rogue's (e.g. -d), as for the game itself.
## A new game starts at once, without the Fighters' Guild, unless --guild is given:
## then the keys go to the Guild screen first. --sample-hof=N first replaces the
## Hall of Fame (the score file in the user data folder) with N sample entries.
## The window keeps the project's size (1280x720) unless --video-cfg=PATH names a
## video settings file (VideoSettings): the game then applies it, and with no file
## there it starts as on a first launch (borderless fullscreen; fullscreen needs a
## window manager: run it under godot/tests/with_display.sh, which also gives it an
## empty user data folder).
## Screenshots: one before the keys, one after them, and one after each key
## number K (1-based) of --shot-at.
extends SceneTree

## Stand-ins in the key string for the two keys that are not characters.
const F10 := "\u000c"
const ALT_ENTER := "\u0007"

var _main: Node
var _frame := 0
var _out := "user://shot"
var _keys := "lllljjj i"
var _shots := 0
var _shot_at: Array[int] = []


func _initialize() -> void:
	var guild := false
	var video := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--keys="):
			_keys = a.substr(7).replace("\\e", char(27)).replace("\\n", "\n") \
				.replace("\\f", F10).replace("\\a", ALT_ENTER)
		elif a == "--guild":
			guild = true
		elif a.begins_with("--sample-hof="):
			_sample_hof(int(a.substr(13)))
		elif a.begins_with("--shot-at="):
			for k in a.substr(10).split(",", false):
				_shot_at.append(int(k))
		elif a.begins_with("--video-cfg="):
			video = a.substr(12)
	load("res://ui/main.gd").skip_guild = not guild
	load("res://ui/main.gd").video_path = video
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 20:
		_shot()
	elif _frame >= 30 and _frame < 30 + _keys.length() * 4 and (_frame - 30) % 4 == 0:
		var k := (_frame - 30) / 4
		_type(_keys[k])
		if _shot_at.has(k + 1):
			_pending = 3
	elif _frame == 40 + _keys.length() * 4:
		_shot()
		quit(0)
	if _pending > 0:
		_pending -= 1
		if _pending == 0:
			_shot()
	return false


var _pending := 0


func _type(c: String) -> void:
	var e := InputEventKey.new()
	e.pressed = true
	if c == char(27):
		e.keycode = KEY_ESCAPE
	elif c == "\n":
		e.keycode = KEY_ENTER
	elif c == F10:
		e.keycode = KEY_F10
	elif c == ALT_ENTER:
		e.keycode = KEY_ENTER
		e.alt_pressed = true
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


## Replace the Hall of Fame in the user data folder with n sample heroes (the
## game's score file format, written by Save.wr_score).
func _sample_hof(n: int) -> void:
	var names := ["Aldric", "Brunhild", "Cedric", "Dagny", "Eamon", "Freya", "Gunnar", "Hild",
		"Ivar", "Jorunn", "Kettil", "Liv", "Magnus", "Nanna", "Olaf", "Ragna", "Sigurd", "Thora",
		"Ulf", "Vigdis"]
	RogueBase.reset()
	RogueBase.numscores = 20
	var f := FileAccess.open(OS.get_user_data_dir().path_join("rogue.scr"), FileAccess.WRITE_READ)
	RogueBase.scoreboard = f
	var top: Array = []
	for i in 20:
		var sc := Rip.Score.new()
		if i < n:
			sc.sc_score = 2400 - i * 120
			sc.sc_name = names[i % names.size()]
			sc.sc_flags = 2 if i == 0 else (1 if i % 5 == 4 else 0)
			sc.sc_level = 26 if i == 0 else 3 + (n - i) % 12
			sc.sc_monster = ord("A") + (i * 7) % 26
			sc.sc_uid = 1000
		top.append(sc)
	Save.wr_score(top)
	f.close()
	RogueBase.scoreboard = null
	RogueBase.reset()
