## The video settings: display mode, window size (windowed), monitor and VSync, kept
## in user://video.cfg and changed on the OPTIONS - VIDEO screen (settings_screen.gd).
##
## On first launch (no file) they come from the screen the window is on: borderless
## fullscreen at the screen's own resolution and, for windowed mode, the largest
## standard size that fits in 90% of the screen's usable area (1600 x 900 on a
## 1920 x 1080 screen). That choice is a pure function of the screen's size and
## usable area (defaults_for(), presets_for()), so tests can use made-up screens.
## apply() leaves the window alone on a headless display (the tests) and when the
## game runs embedded in the editor (the editor sizes it).
class_name VideoSettings
extends RefCounted

const PATH := "user://video.cfg"
const SECTION := "video"

## Display modes, as the file has them.
const WINDOWED := "windowed"
## Borderless, at the screen's own resolution.
const FULLSCREEN := "fullscreen"
const EXCLUSIVE := "exclusive"
const MODES: Array[String] = [WINDOWED, FULLSCREEN, EXCLUSIVE]

## The window sizes offered (largest last).
const PRESETS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
## A first-launch window takes at most this part of the usable area.
const ROOM := 0.9
## A saved window size smaller than this is ignored.
const MIN_SIZE := Vector2i(640, 360)

var mode := FULLSCREEN:
	set(m):
		mode = m
		if m != WINDOWED:
			_full = m
## The window size in windowed mode.
var size := PRESETS[0]
## The monitor: a DisplayServer screen index.
var screen := 0
var vsync := true
## The settings file ("": none, save() does nothing).
var path := ""
## The fullscreen mode last used (Alt+Enter goes back to it).
var _full := FULLSCREEN


# ---- screens (pure) --------------------------------------------------------------

## The room for a window on a screen: its usable area (without panels and taskbars),
## or the whole screen when that is unknown.
static func _room(screen_size: Vector2i, usable: Rect2i) -> Vector2i:
	if usable.size.x > 0 and usable.size.y > 0:
		return usable.size
	return screen_size


static func _fits(s: Vector2i, room: Vector2i) -> bool:
	return s.x <= room.x and s.y <= room.y


## The window sizes offered on a screen: the presets its usable area holds. On a
## screen too small for any: the smallest preset if the screen itself holds it, else
## the usable area. An unknown screen (size 0) gets them all.
static func presets_for(screen_size: Vector2i, usable: Rect2i) -> Array[Vector2i]:
	if screen_size.x <= 0 or screen_size.y <= 0:
		return PRESETS.duplicate()
	var room := _room(screen_size, usable)
	var out: Array[Vector2i] = []
	for p in PRESETS:
		if _fits(p, room):
			out.append(p)
	if out.is_empty():
		out.append(PRESETS[0] if _fits(PRESETS[0], screen_size) else room)
	return out


## The first-launch window size on a screen: the largest size offered that fits in
## 90% of the usable area, else the smallest size offered.
static func default_size(screen_size: Vector2i, usable: Rect2i) -> Vector2i:
	var offered := presets_for(screen_size, usable)
	var room := Vector2(_room(screen_size, usable)) * ROOM
	var best := offered[0]
	for p in offered:
		if p.x <= room.x and p.y <= room.y:
			best = p
	return best


## Whether a window of size s suits a screen: one of the sizes offered, or a size
## between MIN_SIZE and the usable area.
static func suits(s: Vector2i, screen_size: Vector2i, usable: Rect2i) -> bool:
	if presets_for(screen_size, usable).has(s):
		return true
	return _fits(MIN_SIZE, s) and screen_size.x > 0 and _fits(s, _room(screen_size, usable))


## The first-launch settings for a screen: borderless fullscreen, VSync on, and the
## windowed size default_size().
static func defaults_for(screen_size: Vector2i, usable: Rect2i) -> VideoSettings:
	var v := VideoSettings.new()
	v.mode = FULLSCREEN
	v.size = default_size(screen_size, usable)
	v.vsync = true
	return v


## Keep the settings to the screens there are (one {size, usable} each): a monitor
## that is gone gives way to `fallback`, a window size that does not suit the
## monitor to its default size.
func fit(all: Array[Dictionary], fallback := 0) -> void:
	if all.is_empty():
		return
	if screen < 0 or screen >= all.size():
		screen = clampi(fallback, 0, all.size() - 1)
	var s: Dictionary = all[screen]
	if not suits(size, s["size"], s["usable"]):
		size = default_size(s["size"], s["usable"])


## Alt+Enter: windowed <-> fullscreen (the fullscreen mode last used).
func toggle_fullscreen() -> void:
	mode = _full if mode == WINDOWED else WINDOWED


# ---- the file ---------------------------------------------------------------------

## Read the settings file: false if there is none, or it cannot be parsed, or it has
## no [video] section. Values that are missing or of the wrong kind keep what they were.
func load_() -> bool:
	var f := ConfigFile.new()
	if path == "" or f.load(path) != OK or not f.has_section(SECTION):
		return false
	var m: Variant = f.get_value(SECTION, "mode", mode)
	if m is String and MODES.has(m):
		mode = m
	var s: Variant = f.get_value(SECTION, "size", size)
	if s is Vector2i and s.x > 0 and s.y > 0:
		size = s
	var n: Variant = f.get_value(SECTION, "screen", screen)
	if n is int:
		screen = n
	var vs: Variant = f.get_value(SECTION, "vsync", vsync)
	if vs is bool:
		vsync = vs
	return true


func save() -> Error:
	if path == "":
		return OK
	var f := ConfigFile.new()
	f.set_value(SECTION, "mode", mode)
	f.set_value(SECTION, "size", size)
	f.set_value(SECTION, "screen", screen)
	f.set_value(SECTION, "vsync", vsync)
	return f.save(path)


## The settings saved in `file` (over the defaults for the window's screen), fitted to
## the screens there are now. On first launch (no file, or one that cannot be read)
## the defaults, which are saved (unless the display is headless: it has no screen
## to detect).
static func open(file: String, window: Window) -> VideoSettings:
	var v := detect(window)
	var here := v.screen
	v.path = file
	if v.load_():
		v.fit(screens(), here)
	elif has_screens():
		v.save()
	return v


# ---- the display ------------------------------------------------------------------

## Whether there are real screens (not a headless display).
static func has_screens() -> bool:
	return DisplayServer.get_name() != "headless" and DisplayServer.get_screen_count() > 0


## Whether apply() changes the window: there are screens, and the game is not
## embedded in the editor.
static func can_apply() -> bool:
	return has_screens() and not Engine.is_embedded_in_editor()


## The screens: one {size, usable} each (none on a headless display), with hz, the
## refresh rate, if asked (negative or NaN when the system does not tell; some
## systems print an error then).
static func screens(with_hz := false) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not has_screens():
		return out
	for i in DisplayServer.get_screen_count():
		var s := {"size": DisplayServer.screen_get_size(i), "usable": DisplayServer.screen_get_usable_rect(i)}
		if with_hz:
			s["hz"] = DisplayServer.screen_get_refresh_rate(i)
		out.append(s)
	return out


## The first-launch settings for the screen the window is on (defaults_for()).
static func detect(window: Window) -> VideoSettings:
	var all := screens()
	if all.is_empty():
		return defaults_for(Vector2i.ZERO, Rect2i())
	var i := clampi(window.current_screen, 0, all.size() - 1)
	var v := defaults_for(all[i]["size"], all[i]["usable"])
	v.screen = i
	return v


## The settings the window has now (for a run without a settings file).
static func from_window(window: Window) -> VideoSettings:
	var v := detect(window)
	match window.mode:
		Window.MODE_FULLSCREEN:
			v.mode = FULLSCREEN
		Window.MODE_EXCLUSIVE_FULLSCREEN:
			v.mode = EXCLUSIVE
		_:
			v.mode = WINDOWED
			v.size = window.size
	v.vsync = DisplayServer.window_get_vsync_mode(window.get_window_id()) != DisplayServer.VSYNC_DISABLED
	return v


## Whether the window is windowed as far as the settings go: maximized counts too.
static func _windowed(window: Window) -> bool:
	return window.mode == Window.MODE_WINDOWED or window.mode == Window.MODE_MAXIMIZED


## Take in what the player did to the window itself: in windowed mode, the size and
## monitor it was dragged (or maximized) to.
func sync(window: Window) -> void:
	if can_apply() and mode == WINDOWED and _windowed(window):
		size = window.size
		screen = window.current_screen


## Set the window up: VSync, mode and monitor, and in windowed mode the size. The
## window is placed (centred in the monitor's usable area) only when it changes
## mode, monitor or size, so a maximized window stays so. A move to another monitor
## goes through windowed mode (an X11 window in exclusive fullscreen cannot change
## screens).
func apply(window: Window) -> void:
	if not can_apply():
		return
	var all := screens()
	fit(all, window.current_screen)
	var id := window.get_window_id()
	var sync_mode := DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	if DisplayServer.window_get_vsync_mode(id) != sync_mode:
		DisplayServer.window_set_vsync_mode(sync_mode, id)
	var moving := window.current_screen != screen
	if mode == WINDOWED:
		if moving or not _windowed(window) or window.size != size:
			_place(window, all[screen])
		return
	if moving:
		_place(window, all[screen])
	window.mode = Window.MODE_FULLSCREEN if mode == FULLSCREEN else Window.MODE_EXCLUSIVE_FULLSCREEN


## Windowed, of the windowed size, centred in the usable area of screen s.
func _place(window: Window, s: Dictionary) -> void:
	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
	var area: Rect2i = s["usable"]
	if area.size.x <= 0 or area.size.y <= 0:
		area = Rect2i(DisplayServer.screen_get_position(screen), s["size"])
	window.size = size
	window.position = area.position + Vector2i(maxi(0, (area.size.x - size.x) / 2),
		maxi(0, (area.size.y - size.y) / 2))
