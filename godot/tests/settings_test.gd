## Tests of the video settings (ui/video_settings.gd, ui/settings_screen.gd) and their
## wiring in ui/main.gd: the window sizes offered and the first-launch defaults on
## made-up screens, the settings file, the keys of the OPTIONS - VIDEO screen, and F10
## and Alt+Enter over the Guild screen. The real window is tested by ui_video.gd.
##   godot --headless --path godot --script res://tests/settings_test.gd
## Prints one line per failed check and a summary; exit status 1 on any failure. Works
## in (and removes) the folder "settings_test" of the user data folder. The main-scene
## checks are skipped when a saved game is there (the game would restore it).
extends SceneTree

const FHD := {"size": Vector2i(1920, 1080), "usable": Rect2i(0, 0, 1920, 1040), "hz": 60.0}
const QHD := {"size": Vector2i(2560, 1440), "usable": Rect2i(1920, 0, 2560, 1400), "hz": 143.98}

var _passed := 0
var _failed := 0
var _dir := ""
var _changes := 0
var _closes := 0


func _initialize() -> void:
	_dir = OS.get_user_data_dir().path_join("settings_test")
	_clean()
	DirAccess.make_dir_recursive_absolute(_dir)
	_test_presets()
	_test_defaults()
	_test_fit()
	_test_file()
	_test_toggle()
	_test_screen()
	_test_screen_one_monitor()
	await _test_main()
	_clean()
	print("settings_test: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(what: String, ok: bool, detail: Variant = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL %s %s" % [what, str(detail)])


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(_dir):
		return
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


## "1280x720 1366x768" for a list of sizes.
static func _sizes(a: Array) -> String:
	var out := PackedStringArray()
	for s in a:
		out.append("%dx%d" % [s.x, s.y])
	return " ".join(out)


## Row y of a curses screen as text (standout and all).
static func _row(c: Curses, y: int) -> String:
	var s := ""
	for x in 80:
		var ch: int = c.curscr.get_cell(y, x) & 0xFF
		s += char(ch) if ch >= 32 and ch < 127 else "?"
	return s


static func _standout(c: Curses, y: int, x: int) -> bool:
	return (c.curscr.get_cell(y, x) & Curses.A_STANDOUT) != 0


# ---- screens --------------------------------------------------------------------

func _test_presets() -> void:
	var cases := [
		# screen, usable area, sizes offered
		[Vector2i(1366, 768), Rect2i(0, 0, 1366, 768), "1280x720 1366x768"],
		[Vector2i(1366, 768), Rect2i(0, 0, 1366, 728), "1280x720"],
		[Vector2i(1920, 1080), Rect2i(0, 0, 1920, 1040), "1280x720 1366x768 1600x900"],
		[Vector2i(1920, 1080), Rect2i(0, 0, 1920, 1080), "1280x720 1366x768 1600x900 1920x1080"],
		[Vector2i(2560, 1440), Rect2i(0, 0, 2560, 1400), "1280x720 1366x768 1600x900 1920x1080"],
		[Vector2i(3840, 2160), Rect2i(0, 0, 3840, 2160),
			"1280x720 1366x768 1600x900 1920x1080 2560x1440 3840x2160"],
		[Vector2i(3840, 2160), Rect2i(0, 0, 3840, 2100),
			"1280x720 1366x768 1600x900 1920x1080 2560x1440"],
		# too small for any preset: the smallest if the screen holds it, else the usable area
		[Vector2i(1280, 720), Rect2i(0, 0, 1280, 680), "1280x720"],
		[Vector2i(1024, 768), Rect2i(0, 0, 1024, 738), "1024x738"],
		# usable area unknown: the whole screen
		[Vector2i(1600, 900), Rect2i(), "1280x720 1366x768 1600x900"],
		# no screen (headless): all of them
		[Vector2i.ZERO, Rect2i(), "1280x720 1366x768 1600x900 1920x1080 2560x1440 3840x2160"],
	]
	for c in cases:
		var got := _sizes(VideoSettings.presets_for(c[0], c[1]))
		_check("presets: %s, usable %s" % [c[0], c[1].size], got == c[2], "got " + got)


func _test_defaults() -> void:
	var cases := [
		[Vector2i(1366, 768), Rect2i(0, 0, 1366, 768), Vector2i(1280, 720)],
		[Vector2i(1366, 768), Rect2i(0, 0, 1366, 728), Vector2i(1280, 720)],
		[Vector2i(1920, 1080), Rect2i(0, 0, 1920, 1040), Vector2i(1600, 900)],
		[Vector2i(1920, 1080), Rect2i(0, 0, 1920, 1080), Vector2i(1600, 900)],
		[Vector2i(2560, 1440), Rect2i(0, 0, 2560, 1400), Vector2i(1920, 1080)],
		[Vector2i(3840, 2160), Rect2i(0, 0, 3840, 2160), Vector2i(2560, 1440)],
		[Vector2i(3840, 2160), Rect2i(0, 0, 3840, 2100), Vector2i(2560, 1440)],
		[Vector2i(1024, 768), Rect2i(0, 0, 1024, 738), Vector2i(1024, 738)],
		[Vector2i.ZERO, Rect2i(), Vector2i(1280, 720)],
	]
	for c in cases:
		var v := VideoSettings.defaults_for(c[0], c[1])
		_check("first launch on %s (usable %s): fullscreen, VSync on, windowed %s" % [c[0], c[1].size,
			c[2]], v.mode == VideoSettings.FULLSCREEN and v.vsync and v.size == c[2] and v.screen == 0,
			"got %s %s vsync %s" % [v.mode, v.size, v.vsync])


func _test_fit() -> void:
	var fhd: Dictionary = FHD
	_check("suits: a size offered", VideoSettings.suits(Vector2i(1600, 900), fhd.size, fhd.usable))
	_check("suits: not taller than the usable area",
		not VideoSettings.suits(Vector2i(1920, 1080), fhd.size, fhd.usable))
	_check("suits: another size that fits", VideoSettings.suits(Vector2i(1700, 1000), fhd.size, fhd.usable))
	_check("suits: not a tiny window", not VideoSettings.suits(Vector2i(600, 300), fhd.size, fhd.usable))
	var all: Array[Dictionary] = [FHD, QHD]
	var v := VideoSettings.new()
	v.screen = 5
	v.size = Vector2i(1920, 1080)
	v.fit(all, 1)
	_check("fit: a monitor that is gone gives way to the fallback", v.screen == 1, v.screen)
	_check("fit: a size the monitor holds stays", v.size == Vector2i(1920, 1080), v.size)
	v.size = Vector2i(2560, 1440)
	v.fit(all)
	_check("fit: a size taller than the usable area becomes the default", v.size == Vector2i(1920, 1080),
		v.size)
	v.screen = 0
	v.size = Vector2i(1920, 1080)
	v.fit(all)
	_check("fit: a size the monitor cannot hold becomes its default", v.size == Vector2i(1600, 900), v.size)
	var none: Array[Dictionary] = []
	v.screen = 7
	v.fit(none)
	_check("fit: no screens known changes nothing", v.screen == 7 and v.size == Vector2i(1600, 900))


# ---- the file ---------------------------------------------------------------------

func _test_file() -> void:
	var path := _dir.path_join("video.cfg")
	var v := VideoSettings.new()
	v.path = path
	_check("file: none to load", not v.load_() and v.mode == VideoSettings.FULLSCREEN)
	v.mode = VideoSettings.EXCLUSIVE
	v.size = Vector2i(1366, 768)
	v.screen = 1
	v.vsync = false
	_check("file: saved", v.save() == OK and FileAccess.file_exists(path))
	var text := FileAccess.get_file_as_string(path)
	_check("file: readable", text.contains("[video]") and text.contains("mode=\"exclusive\"")
		and text.contains("size=Vector2i(1366, 768)") and text.contains("vsync=false"), text)
	var w := VideoSettings.new()
	w.path = path
	_check("file: loaded back", w.load_() and w.mode == VideoSettings.EXCLUSIVE
		and w.size == Vector2i(1366, 768) and w.screen == 1 and not w.vsync,
		"%s %s %d %s" % [w.mode, w.size, w.screen, w.vsync])
	w.toggle_fullscreen()
	w.toggle_fullscreen()
	_check("file: a loaded exclusive mode is the one Alt+Enter returns to", w.mode == VideoSettings.EXCLUSIVE)

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[video]\nmode=\"sideways\"\nsize=\"big\"\nscreen=\"two\"\nvsync=3\n")
	f.close()
	w = VideoSettings.new()
	w.path = path
	_check("file: wrong values are ignored", w.load_() and w.mode == VideoSettings.FULLSCREEN
		and w.size == VideoSettings.PRESETS[0] and w.screen == 0 and w.vsync)
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[video]\nmode=@@@\n")	# Godot prints the parse error
	f.close()
	_check("file: an unreadable file does not load", not w.load_())
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("no settings here\n")
	f.close()
	_check("file: a file without [video] does not load", not w.load_())

	# headless: open() reads a file, and on first launch detects without saving
	w = VideoSettings.open(path, root)
	_check("open: a file without settings gives the defaults", w.mode == VideoSettings.FULLSCREEN
		and w.size == Vector2i(1280, 720) and w.path == path)
	v.save()
	w = VideoSettings.open(path, root)
	_check("open: the saved settings", w.mode == VideoSettings.EXCLUSIVE and w.size == Vector2i(1366, 768)
		and not w.vsync)
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_string("[video]\nmode=\"windowed\"\n")
	f.close()
	w = VideoSettings.open(path, root)
	_check("open: what the file lacks is the default", w.mode == VideoSettings.WINDOWED
		and w.size == Vector2i(1280, 720) and w.vsync and w.screen == 0)
	var fresh := _dir.path_join("fresh.cfg")
	w = VideoSettings.open(fresh, root)
	_check("open: first launch on a headless display: defaults, no file", w.mode == VideoSettings.FULLSCREEN
		and w.size == Vector2i(1280, 720) and not FileAccess.file_exists(fresh))
	w.path = ""
	_check("file: no path, nothing saved", w.save() == OK and not FileAccess.file_exists(fresh))
	_check("apply: headless, the window is left alone", not VideoSettings.can_apply()
		and VideoSettings.screens().is_empty())


func _test_toggle() -> void:
	var v := VideoSettings.new()
	v.toggle_fullscreen()
	_check("Alt+Enter: fullscreen -> windowed", v.mode == VideoSettings.WINDOWED)
	v.toggle_fullscreen()
	_check("Alt+Enter: windowed -> fullscreen", v.mode == VideoSettings.FULLSCREEN)
	v.mode = VideoSettings.EXCLUSIVE
	v.mode = VideoSettings.WINDOWED
	v.toggle_fullscreen()
	_check("Alt+Enter: back to exclusive fullscreen if that was the last", v.mode == VideoSettings.EXCLUSIVE)


# ---- the screen ---------------------------------------------------------------------

func _on_changed() -> void:
	_changes += 1


func _on_closed() -> void:
	_closes += 1


func _test_screen() -> void:
	var all: Array[Dictionary] = [FHD, QHD]
	var v := VideoSettings.defaults_for(FHD.size, FHD.usable)
	var s := SettingsScreen.new(v, all)
	s.changed.connect(_on_changed)
	s.closed.connect(_on_closed)
	_changes = 0
	_closes = 0
	var c := s.cs
	_check("screen: the title bar", _row(c, 0).contains("OPTIONS - VIDEO") and _standout(c, 0, 0)
		and _standout(c, 0, 78) and not _standout(c, 0, 79))
	_check("screen: what was detected", _row(c, 1).begins_with(" Screen 1 of 2: 1920 x 1080, 60 Hz"), _row(c, 1))
	_check("screen: the rows", _row(c, 4).contains("Display mode      Fullscreen")
		and _row(c, 5).contains("Window size       1920 x 1080 (native)")
		and _row(c, 6).contains("Monitor           1 of 2") and _row(c, 7).contains("VSync             On"),
		[_row(c, 4), _row(c, 5), _row(c, 6), _row(c, 7)])
	_check("screen: the cursor bar on the display mode", _row(c, 4).begins_with(" > Display mode")
		and _standout(c, 4, 1) and not _standout(c, 5, 1))
	_check("screen: the key line", _row(c, 22).contains("j/k choose  h/l change  Alt+Enter fullscreen  Esc close"))
	s.key(ord("j"))
	_check("screen: in fullscreen j skips the window size", s.row == SettingsScreen.ROW_MONITOR
		and _standout(c, 6, 1) and _row(c, 6).begins_with(" > Monitor"))
	s.key(ord("k"))
	s.key(ord("k"))
	_check("screen: k stops at the top", s.row == SettingsScreen.ROW_MODE)
	s.key(ord("l"))
	_check("screen: l: exclusive fullscreen", v.mode == VideoSettings.EXCLUSIVE and _changes == 1
		and _row(c, 4).contains("Exclusive fullscreen"))
	s.key(13)
	_check("screen: Enter: the next value (round to windowed)", v.mode == VideoSettings.WINDOWED
		and _changes == 2 and _row(c, 4).contains("Windowed") and _row(c, 5).contains("1600 x 900")
		and not _row(c, 5).contains("native"))
	s.key(ord("h"))
	s.key(Curses.KEY_RIGHT)
	_check("screen: h and right arrow change it too", v.mode == VideoSettings.WINDOWED and _changes == 4)
	s.key(Curses.KEY_DOWN)
	_check("screen: windowed, the size can be chosen", s.row == SettingsScreen.ROW_SIZE)
	s.key(ord("l"))
	_check("screen: the next size wraps round to the smallest", v.size == Vector2i(1280, 720)
		and _row(c, 5).contains("1280 x 720"), v.size)
	s.key(ord("h"))
	s.key(ord("h"))
	_check("screen: h: the smaller size", v.size == Vector2i(1366, 768), v.size)
	s.key(ord("j"))
	s.key(ord("l"))
	_check("screen: the second monitor", v.screen == 1 and v.size == Vector2i(1366, 768)
		and _row(c, 1).contains("Screen 2 of 2: 2560 x 1440, 144 Hz") and _row(c, 6).contains("2 of 2"),
		_row(c, 1))
	s.key(ord("j"))
	s.key(13)
	_check("screen: VSync off", not v.vsync and _row(c, 7).contains("Off") and s.row == SettingsScreen.ROW_VSYNC)
	s.key(ord("j"))
	_check("screen: j stops at the bottom", s.row == SettingsScreen.ROW_VSYNC)
	s.key(ord("x"))
	s.key(ord("q"))
	_check("screen: other keys do nothing", _changes == 9 and _closes == 0, _changes)
	# a size the first monitor cannot hold: back there, it becomes its default
	s.key(ord("k"))
	s.key(ord("k"))
	s.key(ord("l"))
	s.key(ord("l"))
	_check("screen: 1920 x 1080 on the second monitor", v.size == Vector2i(1920, 1080), v.size)
	s.key(ord("j"))
	s.key(ord("h"))
	_check("screen: back on the first monitor, its default size", v.screen == 0
		and v.size == Vector2i(1600, 900), "%d %s" % [v.screen, v.size])
	# Alt+Enter while the screen is open (main.gd redraws it): the fullscreen mode
	# last used, exclusive
	s.key(ord("k"))
	v.toggle_fullscreen()
	s.draw()
	_check("screen: fullscreen again: the cursor leaves the size row", v.mode == VideoSettings.EXCLUSIVE
		and s.row == SettingsScreen.ROW_MODE and _row(c, 5).contains("1920 x 1080 (native)")
		and _standout(c, 4, 1), s.row)
	s.key(27)
	_check("screen: Escape closes", _closes == 1 and _changes == 12, _changes)


func _test_screen_one_monitor() -> void:
	var one: Array[Dictionary] = [{"size": Vector2i(1366, 768), "usable": Rect2i(0, 0, 1366, 768),
		"hz": NAN}]
	var v := VideoSettings.defaults_for(one[0].size, one[0].usable)
	var s := SettingsScreen.new(v, one)
	var c := s.cs
	_check("one monitor: no refresh rate known", _row(c, 1).strip_edges() == "Screen 1 of 1: 1366 x 768",
		_row(c, 1))
	_check("one monitor: no monitor row", _row(c, 6).contains("VSync") and not _row(c, 5).contains("Monitor")
		and _row(c, 5).contains("1366 x 768 (native)"))
	s.key(ord("j"))
	_check("one monitor: j goes to VSync", s.row == SettingsScreen.ROW_VSYNC)
	var none: Array[Dictionary] = []
	s = SettingsScreen.new(VideoSettings.new(), none)
	_check("no screens: still a screen", _row(s.cs, 1).contains("No screen detected")
		and _row(s.cs, 5).contains("native"))


# ---- main.gd ------------------------------------------------------------------------

## F10 and Alt+Enter in the main scene, over the Guild screen: the settings get the
## keys (the Guild none), Escape or F10 gives the Guild its screen and keys back.
func _test_main() -> void:
	if FileAccess.file_exists(OS.get_user_data_dir().path_join("rogue.save")):
		print("settings_test: main-scene checks skipped (a saved game is in the user data folder)")
		return
	var main_script: GDScript = load("res://ui/main.gd")
	var cfg := _dir.path_join("main_video.cfg")
	main_script.skip_guild = false
	main_script.video_path = cfg
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame	# _ready() runs once the tree is up
	var view: TerminalView = main.view
	var guild: GuildScreen = main._guild
	_check("main: the Guild opens", guild != null and view.cs == guild.cs)
	_check("main: headless, no settings file at startup", not FileAccess.file_exists(cfg)
		and main.video.mode == VideoSettings.FULLSCREEN)
	view.settings_requested.emit()
	var s: SettingsScreen = main._settings
	_check("main: F10 opens OPTIONS - VIDEO over the Guild", s != null and view.cs == s.cs
		and _row(s.cs, 0).contains("OPTIONS - VIDEO"))
	for k in [13, ord("j"), ord("2"), ord("e"), ord("y")]:
		view.key_pressed.emit(k)
	_check("main: the keys go to the settings, not the Guild", main._guild == guild and guild.section == 0
		and guild.shop.spent() == 0 and main.video.mode == VideoSettings.EXCLUSIVE, main.video.mode)
	_check("main: a change is saved", FileAccess.get_file_as_string(cfg).contains("mode=\"exclusive\""))
	view.key_pressed.emit(27)
	_check("main: Escape gives the Guild its screen back", main._settings == null and view.cs == guild.cs)
	view.settings_requested.emit()
	view.settings_requested.emit()
	_check("main: F10 closes it too", main._settings == null and view.cs == guild.cs)
	view.fullscreen_toggled.emit()
	_check("main: Alt+Enter: windowed, saved", main.video.mode == VideoSettings.WINDOWED
		and FileAccess.get_file_as_string(cfg).contains("mode=\"windowed\""))
	view.settings_requested.emit()
	view.fullscreen_toggled.emit()
	s = main._settings
	_check("main: Alt+Enter over the settings: back to exclusive fullscreen, shown",
		main.video.mode == VideoSettings.EXCLUSIVE and _row(s.cs, 4).contains("Exclusive fullscreen")
		and FileAccess.get_file_as_string(cfg).contains("mode=\"exclusive\""))
	view.key_pressed.emit(27)
	view.key_pressed.emit(ord("2"))
	_check("main: the Guild has its keys again", guild.section == 1 and view.cs == guild.cs)
	root.remove_child(main)
	main.free()
	main_script.skip_guild = false
	main_script.video_path = VideoSettings.PATH
