## UI test of the video settings in a real window:
##   1. the first launch goes borderless fullscreen at the screen's resolution and
##      saves the detected settings (the windowed size is the screen's default);
##   2. F10 opens OPTIONS - VIDEO over the game;
##   3. h makes it windowed: the default size, centred in the usable area, saved; the
##      game does not see the key (the hero stays put);
##   4. Alt+Enter goes back to fullscreen, saved;
##   5. Escape gives the game its screen back, and its keys ('v' shows the version);
##   6. Alt+Enter during the game makes the window windowed again;
##   7. the player resizes and moves the window: F10 shows it as it is, a VSync change
##      leaves it there, a size from the list centres it;
##   8. a maximized window counts as windowed and stays maximized;
##   9. with several monitors: the window moves to the second one (its size fitted to
##      it, centred), goes fullscreen there, and comes back fullscreen on the first.
## With --windowed (the game's option: this run only) it checks the first launch
## alone: a window of the default size, while the file keeps fullscreen.
## Needs a display whose window manager handles fullscreen, e.g.
##   godot/tests/with_display.sh --workarea=0,0,1920,1040 -- godot --path godot \
##       --script res://tests/ui_video.gd -- --out=/tmp/video
##   godot/tests/with_display.sh --screen=1920x1080 --screen=1280x1024 -- godot ...
## (with_display.sh also gives it an empty user data folder). Prints "ui_video: OK"
## or the failed checks and "ui_video: FAILED" (exit status 1). --out=PREFIX saves a
## screenshot after each step (PREFIX1.png ...). The settings file is ui_video.cfg in
## the user data folder (removed before and after); a saved game there stops the test
## (the game would restore it).
extends SceneTree

var _main: Node
var _out := ""
var _shots := 0
var _failed := 0
var _cfg := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	var data := OS.get_user_data_dir()
	if FileAccess.file_exists(data.path_join("rogue.save")):
		print("ui_video: FAILED: a saved game is in %s (with_display.sh gives an empty folder)" % data)
		quit(1)
		return
	_cfg = data.path_join("ui_video.cfg")
	DirAccess.remove_absolute(_cfg)
	var main_script: GDScript = load("res://ui/main.gd")
	main_script.skip_guild = true	# a new game at once
	main_script.video_path = _cfg
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	_run()


func _run() -> void:
	await _frames(20)
	var w := root
	var screen := DisplayServer.screen_get_size(0)
	var usable := DisplayServer.screen_get_usable_rect(0)
	var want := VideoSettings.default_size(screen, usable)
	var view: TerminalView = _main.view
	var centred := usable.position + (usable.size - want) / 2
	if OS.get_cmdline_user_args().has("--windowed"):
		_expect("--windowed: a window of the default size, centred", w.mode == Window.MODE_WINDOWED
			and w.size == want and w.position == centred, "%d %s at %s" % [w.mode, w.size, w.position])
		_expect("--windowed: not saved", _saved("mode", "\"fullscreen\""), _text())
		_shot()
		_finish()
		return

	# 1. first launch
	_expect("first launch: fullscreen at the screen's size", w.mode == Window.MODE_FULLSCREEN
		and w.size == screen and w.position == DisplayServer.screen_get_position(0),
		"%d %s at %s" % [w.mode, w.size, w.position])
	_expect("first launch: the terminal fills the window", view.size == Vector2(w.size)
		and view.font_size >= int(screen.y / 30.0), "%s, font %d" % [view.size, view.font_size])
	_expect("first launch: the settings saved", _saved("mode", "\"fullscreen\"")
		and _saved("size", "Vector2i(%d, %d)" % [want.x, want.y]) and _saved("vsync", "true"), _text())
	_shot()

	# 2. F10 over the game
	var game_cs: Curses = view.cs
	var hero := Vector2i(RogueBase.hero.x, RogueBase.hero.y)
	_key(KEY_F10)
	await _frames(4)
	_expect("F10: OPTIONS - VIDEO", view.cs != game_cs and _row(view.cs, 0).contains("OPTIONS - VIDEO")
		and _row(view.cs, 1).contains("Screen 1 of %d: %d x %d" % [DisplayServer.get_screen_count(),
		screen.x, screen.y]), _row(view.cs, 1))
	_shot()

	# 3. windowed
	_type("h")
	await _frames(12)
	_expect("h: windowed, the default size, centred", w.mode == Window.MODE_WINDOWED and w.size == want
		and w.position == centred, "%d %s at %s" % [w.mode, w.size, w.position])
	_expect("h: saved", _saved("mode", "\"windowed\""), _text())
	_expect("h: the game did not get the key", Vector2i(RogueBase.hero.x, RogueBase.hero.y) == hero
		and RogueBase.cs._queue.is_empty())
	_expect("h: the settings screen fills the smaller window", view.size == Vector2(w.size)
		and _row(view.cs, 4).contains("Windowed"))
	_shot()

	# 4. Alt+Enter over the settings
	_key(KEY_ENTER, true)
	await _frames(12)
	_expect("Alt+Enter: fullscreen again", w.mode == Window.MODE_FULLSCREEN and w.size == screen,
		"%d %s" % [w.mode, w.size])
	_expect("Alt+Enter: saved", _saved("mode", "\"fullscreen\""), _text())

	# 5. Escape: the game again
	_type(char(27))
	await _frames(4)
	_expect("Escape: the game's screen", view.cs == game_cs)
	_type("v")
	await _frames(4)
	_expect("the game has its keys again", _row(game_cs, 0).contains("Version 5.4.4"), _row(game_cs, 0))
	_shot()

	# 6. Alt+Enter during the game
	_key(KEY_ENTER, true)
	await _frames(12)
	_expect("Alt+Enter in the game: windowed", w.mode == Window.MODE_WINDOWED and w.size == want
		and view.cs == game_cs, "%d %s" % [w.mode, w.size])
	_shot()

	# 7. the player resizes and moves the window: F10 shows it as it is, and a VSync
	# change leaves it there
	var dragged := want - Vector2i(100, 50)
	var spot := usable.position + Vector2i(20, 20)
	w.size = dragged
	w.position = spot
	await _frames(6)
	_key(KEY_F10)
	await _frames(4)
	_expect("dragged: the settings show the window's size", _row(view.cs, 5).contains("%d x %d" % [
		dragged.x, dragged.y]), _row(view.cs, 5))
	for c in "jjjl":	# down to VSync (the last row), off
		_type(c)
	await _frames(8)
	_expect("dragged: a VSync change leaves the window alone", w.size == dragged and w.position == spot,
		"%s at %s" % [w.size, w.position])
	_expect("dragged: saved with the window's size", _saved("vsync", "false")
		and _saved("size", "Vector2i(%d, %d)" % [dragged.x, dragged.y]), _text())
	for c in "kkkjh":	# the window size (second row), back to a preset: placed again
		_type(c)
	await _frames(8)
	_expect("dragged: a size from the list centres the window", w.size != dragged
		and w.position == usable.position + (usable.size - w.size) / 2, "%s at %s" % [w.size, w.position])
	_type(char(27))
	await _frames(4)

	# 8. maximized counts as windowed: F10 shows its size, a VSync change leaves it so
	w.mode = Window.MODE_MAXIMIZED
	await _frames(8)
	var big := w.size
	_expect("maximized: the usable area", w.mode == Window.MODE_MAXIMIZED and big == usable.size,
		"%d %s" % [w.mode, big])
	_key(KEY_F10)
	await _frames(4)
	_expect("maximized: the settings show its size", _row(view.cs, 5).contains("%d x %d" % [big.x, big.y]),
		_row(view.cs, 5))
	for c in "jjjl":	# VSync on again
		_type(c)
	await _frames(8)
	_expect("maximized: a VSync change leaves it maximized", w.mode == Window.MODE_MAXIMIZED
		and w.size == big and _saved("vsync", "true"), "%d %s" % [w.mode, w.size])
	_type(char(27))
	await _frames(4)
	w.mode = Window.MODE_WINDOWED
	await _frames(8)
	if DisplayServer.get_screen_count() > 1:
		await _second_monitor()
	_finish()


## 7. Windowed on the first monitor: to the second and back.
func _second_monitor() -> void:
	var w := root
	var at := DisplayServer.screen_get_position(1)
	var screen := DisplayServer.screen_get_size(1)
	var usable := DisplayServer.screen_get_usable_rect(1)
	var size := w.size
	if not VideoSettings.suits(size, screen, usable):
		size = VideoSettings.default_size(screen, usable)
	_key(KEY_F10)
	await _frames(4)
	for c in "jjl":	# windowed: mode, size, monitor
		_type(c)
	await _frames(12)
	_expect("monitor 2: the window moves there, its size fitted, centred", w.current_screen == 1
		and w.mode == Window.MODE_WINDOWED and w.size == size
		and w.position == usable.position + (usable.size - size) / 2,
		"screen %d, %d %s at %s" % [w.current_screen, w.mode, w.size, w.position])
	_expect("monitor 2: saved", _saved("screen", "1") and _saved("size", "Vector2i(%d, %d)" % [size.x,
		size.y]), _text())
	_shot()
	_key(KEY_ENTER, true)
	await _frames(12)
	_expect("monitor 2: fullscreen there", w.mode == Window.MODE_FULLSCREEN and w.position == at
		and w.size == screen, "%d %s at %s" % [w.mode, w.size, w.position])
	_shot()
	_type("h")
	await _frames(12)
	_expect("monitor 1 again, fullscreen", w.current_screen == 0 and w.mode == Window.MODE_FULLSCREEN
		and w.position == DisplayServer.screen_get_position(0) and w.size == DisplayServer.screen_get_size(0),
		"screen %d, %d %s at %s" % [w.current_screen, w.mode, w.size, w.position])
	_type(char(27))
	await _frames(4)


func _finish() -> void:
	DirAccess.remove_absolute(_cfg)
	print("ui_video: OK" if _failed == 0 else "ui_video: FAILED")
	quit(0 if _failed == 0 else 1)


func _expect(what: String, ok: bool, detail: Variant = "") -> void:
	if not ok:
		_failed += 1
		print("FAIL %s %s" % [what, str(detail)])


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _text() -> String:
	return FileAccess.get_file_as_string(_cfg) if FileAccess.file_exists(_cfg) else "(no file)"


## Whether the settings file has the line key=value.
func _saved(key: String, value: String) -> bool:
	return _text().split("\n").has("%s=%s" % [key, value])


static func _row(c: Curses, y: int) -> String:
	var s := ""
	for x in 80:
		var ch: int = c.curscr.get_cell(y, x) & 0xFF
		s += char(ch) if ch >= 32 and ch < 127 else "?"
	return s


## Press and release a key (a character, or Escape).
func _type(c: String) -> void:
	var e := InputEventKey.new()
	if c == char(27):
		e.keycode = KEY_ESCAPE
	else:
		e.unicode = c.unicode_at(0)
		e.keycode = OS.find_keycode_from_string(c.to_upper())
	_send(e)


func _key(keycode: Key, alt := false) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.alt_pressed = alt
	_send(e)


func _send(e: InputEventKey) -> void:
	e.pressed = true
	Input.parse_input_event(e)
	var r: InputEventKey = e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)


func _shot() -> void:
	if _out == "":
		return
	_shots += 1
	var path := "%s%d.png" % [_out, _shots]
	root.get_texture().get_image().save_png(path)
	print("saved ", path)
