## OPTIONS - VIDEO: the video settings screen (F10), drawn like the Guild's
## (godot/guild/guild_screen.gd): 80x24, with its own Curses, shown on the game's
## TerminalView. ui/main.gd gives it the keys (key()) while it is open. A change is
## made at once: it emits `changed`, and main.gd applies and saves the settings.
## Escape emits `closed` (F10 closes it in main.gd).
class_name SettingsScreen
extends RefCounted

signal changed
signal closed

const WIDTH := 79
## The first row line, and the width of a row's bar.
const TOP := 4
const BAR := 46

## The rows.
const ROW_MODE := 0
const ROW_SIZE := 1
const ROW_MONITOR := 2
const ROW_VSYNC := 3
const LABELS: Array[String] = ["Display mode", "Window size", "Monitor", "VSync"]
const MODE_NAMES := {VideoSettings.WINDOWED: "Windowed", VideoSettings.FULLSCREEN: "Fullscreen",
	VideoSettings.EXCLUSIVE: "Exclusive fullscreen"}

var cs: Curses
var video: VideoSettings
## The screens, one {size, usable, hz} each (VideoSettings.screens(true)).
var screens: Array[Dictionary] = []
## The row under the cursor.
var row := ROW_MODE
## The message line.
var _say := ""


func _init(settings: VideoSettings, all: Array[Dictionary]) -> void:
	video = settings
	screens = all
	cs = Curses.new()
	cs.leaveok(cs.stdscr, true)
	draw()


# ---- keys ---------------------------------------------------------------------

## A key, as TerminalView.key_code() gives it.
func key(code: int) -> void:
	_say = ""
	match code:
		ord("j"), Curses.KEY_DOWN, 14:	# ^N
			_move(1)
		ord("k"), Curses.KEY_UP, 16:	# ^P
			_move(-1)
		ord("l"), Curses.KEY_RIGHT, 13, 10:	# Enter: the next value
			_change(1)
		ord("h"), Curses.KEY_LEFT:
			_change(-1)
		27:
			closed.emit()
			return
	draw()


## The rows shown: the monitor only with several screens.
func rows() -> Array[int]:
	var r: Array[int] = [ROW_MODE, ROW_SIZE]
	if screens.size() > 1:
		r.append(ROW_MONITOR)
	r.append(ROW_VSYNC)
	return r


## Whether a row can change: the window size only in windowed mode.
func _selectable(r: int) -> bool:
	return r != ROW_SIZE or video.mode == VideoSettings.WINDOWED


func _move(d: int) -> void:
	var r := rows()
	var i := r.find(row) + d
	while i >= 0 and i < r.size():
		if _selectable(r[i]):
			row = r[i]
			return
		i += d


## The next (d = 1) or previous (d = -1) value of the row, applied and saved.
func _change(d: int) -> void:
	match row:
		ROW_MODE:
			var i := VideoSettings.MODES.find(video.mode)
			video.mode = VideoSettings.MODES[posmod(i + d, VideoSettings.MODES.size())]
		ROW_SIZE:
			var sizes := _sizes()
			video.size = sizes[posmod(sizes.find(video.size) + d, sizes.size())]
		ROW_MONITOR:
			video.screen = posmod(video.screen + d, screens.size())
			video.fit(screens)
		ROW_VSYNC:
			video.vsync = not video.vsync
	if Engine.is_embedded_in_editor():
		_say = "saved (not applied in the editor's game view)"
	changed.emit()


## The window sizes to choose from: those offered on the monitor, and the current
## size if it is another.
func _sizes() -> Array[Vector2i]:
	var s := _screen()
	var out := VideoSettings.presets_for(s.get("size", Vector2i.ZERO), s.get("usable", Rect2i()))
	if not out.has(video.size):
		out.append(video.size)
		out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return out


## The chosen monitor's {size, usable, hz}, or {} if it is not known.
func _screen() -> Dictionary:
	if video.screen >= 0 and video.screen < screens.size():
		return screens[video.screen]
	return {}


# ---- drawing --------------------------------------------------------------------

func draw() -> void:
	if not rows().has(row) or not _selectable(row):
		row = ROW_MODE
	var w := cs.stdscr
	cs.werase(w)
	_title("OPTIONS - VIDEO")
	_put(1, 1, _detected())
	_put(2, 1, "-".repeat(WIDTH - 2))
	var y := TOP
	for r in rows():
		var s := "%s %-18s%s" % [">" if r == row else " ", LABELS[r], _value(r)]
		_put(y, 1, s + " ".repeat(maxi(0, BAR - s.length())), r == row)
		y += 1
	_put(21, 1, "-".repeat(WIDTH - 2))
	_put(22, 1, "j/k choose  h/l change  Alt+Enter fullscreen  Esc close")
	_put(23, 1, _say)
	cs.wrefresh(w)


## What was detected of the chosen monitor: "Screen 1 of 2: 1920 x 1080, 60 Hz".
func _detected() -> String:
	var s := _screen()
	if s.is_empty():
		return "No screen detected"
	var sz: Vector2i = s["size"]
	var t := "Screen %d of %d: %d x %d" % [video.screen + 1, screens.size(), sz.x, sz.y]
	var hz: float = s.get("hz", -1.0)
	if is_finite(hz) and hz > 0:
		t += ", %d Hz" % roundi(hz)
	return t


func _value(r: int) -> String:
	match r:
		ROW_MODE:
			return MODE_NAMES[video.mode]
		ROW_SIZE:
			if video.mode == VideoSettings.WINDOWED:
				return "%d x %d" % [video.size.x, video.size.y]
			var s := _screen()
			if s.is_empty():
				return "native"
			return "%d x %d (native)" % [s["size"].x, s["size"].y]
		ROW_MONITOR:
			return "%d of %d" % [video.screen + 1, screens.size()]
		ROW_VSYNC:
			return "On" if video.vsync else "Off"
	return ""


## Title bar: centered, in standout across the screen.
func _title(t: String) -> void:
	var pad := (WIDTH - t.length()) / 2
	_put(0, 0, " ".repeat(pad) + t + " ".repeat(WIDTH - pad - t.length()), true)


## Write s at (y, x), clipped to the screen (never the last cell: it would scroll).
func _put(y: int, x: int, s: String, standout := false) -> void:
	var w := cs.stdscr
	s = s.substr(0, maxi(0, WIDTH - x))
	if standout:
		cs.wstandout(w)
	cs.mvwaddstr(w, y, x, s)
	if standout:
		cs.wstandend(w)
