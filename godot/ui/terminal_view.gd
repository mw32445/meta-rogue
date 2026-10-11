## The game's terminal: draws the emulated physical screen (curscr) as an
## 80x24 grid of character cells, with standout as inverse video and the
## cursor where curses left it. After endwin() it shows what the program wrote
## to stdout, as a terminal shows the shell's screen again.
##
## Key presses become the codes a curses program reads with keypad() on:
## characters, control characters and KEY_* codes for the arrow, Home/End and
## Page keys. The ported md_readchar() turns those into Rogue commands.
class_name TerminalView
extends Control

## A key, as the code a curses program reads (see key_code()).
signal key_pressed(code: int)

const COLS := 80
const ROWS := 24
const FG := Color(0.82, 0.82, 0.82)
const BG := Color(0.0, 0.0, 0.0)
const BLINK := 0.53

var cs: Curses = null
var font: Font = preload("res://fonts/DejaVuSansMono.ttf")
var font_size := 16
var cell := Vector2(10, 20)
var ascent := 16.0
var _blink := 0.0
var _cursor_on := true
var _seen_version := -1
var _console_cache := []
var _console_bytes := -1


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	resized.connect(_fit)
	_fit()
	grab_focus()


## The largest font size whose 80x24 grid fits the control.
func _fit() -> void:
	var ref := 64
	var adv := font.get_char_size(ord("M"), ref).x
	var hgt := font.get_height(ref)
	var by_w := int(floor(size.x / (COLS * adv) * ref))
	var by_h := int(floor(size.y / (ROWS * hgt) * ref))
	font_size = maxi(6, mini(by_w, by_h))
	cell = Vector2(font.get_char_size(ord("M"), font_size).x, font.get_height(font_size))
	ascent = font.get_ascent(font_size)
	queue_redraw()


func _process(delta: float) -> void:
	_blink += delta
	if _blink >= BLINK:
		_blink = 0.0
		_cursor_on = not _cursor_on
		queue_redraw()
	if cs != null and cs.version != _seen_version:
		_seen_version = cs.version
		_cursor_on = true
		_blink = 0.0
		queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if cs == null:
		return
	var origin := ((size - cell * Vector2(COLS, ROWS)) / 2).floor()
	if cs.curses_gone or cs.isendwin():
		_draw_console(origin)
		return
	var w := cs.curscr
	for y in ROWS:
		for x in COLS:
			var v := w.get_cell(y, x)
			var c := v & Curses.A_CHARTEXT
			var pos := origin + Vector2(x, y) * cell
			var fg := FG
			if (v & Curses.A_STANDOUT) != 0:
				draw_rect(Rect2(pos, cell), FG)
				fg = BG
			if c > 32 and c < 127:
				draw_char(font, pos + Vector2(0, ascent), char(c), font_size, fg)
	if cs.cursor_known and _cursor_on and has_focus():
		_draw_cursor(origin + Vector2(w._curx, w._cury) * cell)


func _draw_cursor(pos: Vector2) -> void:
	var h := maxf(2.0, floorf(cell.y / 8))
	draw_rect(Rect2(pos + Vector2(0, cell.y - h), Vector2(cell.x, h)), FG)


## The stdout stream as a terminal shows it: the last 24 lines.
func _draw_console(origin: Vector2) -> void:
	var lines := _console_lines()
	var first := maxi(0, lines.size() - ROWS)
	for i in range(first, lines.size()):
		var s: String = lines[i]
		for x in mini(s.length(), COLS):
			var c := s.unicode_at(x)
			if c > 32 and c < 127:
				draw_char(font, origin + Vector2(x * cell.x, (i - first) * cell.y + ascent), s[x],
					font_size, FG)
	if _cursor_on and has_focus() and not lines.is_empty():
		var last: String = lines[lines.size() - 1]
		_draw_cursor(origin + Vector2(mini(last.length(), COLS - 1), lines.size() - 1 - first) * cell)


## Interpret the stdout bytes: newline (with the tty's CR), carriage return,
## backspace; escape sequences (the mvcur() before saving) are skipped.
func _console_lines() -> Array:
	var b := cs.stdout_bytes
	if b.size() == _console_bytes:
		return _console_cache
	var lines := [""]
	var col := 0
	var i := 0
	while i < b.size():
		var c := b[i]
		i += 1
		if c == 10:
			lines.append("")
			col = 0
		elif c == 13:
			col = 0
		elif c == 8:
			col = maxi(0, col - 1)
		elif c == 27:
			if i < b.size() and b[i] == ord("["):
				i += 1
				while i < b.size() and (b[i] < 0x40 or b[i] > 0x7E):
					i += 1
			i += 1
		elif c == 9:
			col = mini(COLS - 1, (col / 8 + 1) * 8)
		elif c >= 32:
			if col >= COLS:
				lines.append("")
				col = 0
			var s: String = lines[lines.size() - 1]
			while s.length() < col:
				s += " "
			s = s.substr(0, col) + char(c) + s.substr(col + 1)
			lines[lines.size() - 1] = s
			col += 1
	_console_cache = lines
	_console_bytes = b.size()
	return lines


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var code := key_code(event)
		if code >= 0:
			key_pressed.emit(code)
		accept_event()


## The code a curses program would read for this key, or -1 to ignore it.
## Shifted/control arrows give the codes md_readchar() maps to the "run"
## commands (^H ^J ^K ^L ^Y ^U ^B ^N).
static func key_code(e: InputEventKey) -> int:
	var k := e.keycode
	var mod := e.shift_pressed or e.ctrl_pressed
	match k:
		KEY_UP, KEY_KP_8:
			return 0x146 if mod else Curses.KEY_UP
		KEY_DOWN, KEY_KP_2:
			return 0x145 if mod else Curses.KEY_DOWN
		KEY_LEFT, KEY_KP_4:
			return Curses.KEY_SLEFT if mod else Curses.KEY_LEFT
		KEY_RIGHT, KEY_KP_6:
			return Curses.KEY_SRIGHT if mod else Curses.KEY_RIGHT
		KEY_HOME, KEY_KP_7:
			return Curses.KEY_SHOME if mod else Curses.KEY_HOME
		KEY_END, KEY_KP_1:
			return Curses.KEY_SEND if mod else Curses.KEY_END
		KEY_PAGEUP, KEY_KP_9:
			return Curses.KEY_SPREVIOUS if mod else Curses.KEY_PPAGE
		KEY_PAGEDOWN, KEY_KP_3:
			return Curses.KEY_SNEXT if mod else Curses.KEY_NPAGE
		KEY_KP_5:
			if RogueBase.fixes:	# FIX 1: rest; md_readchar() would make KEY_B2 'u'
				return ord(".")
			return Curses.KEY_B2
		KEY_ENTER, KEY_KP_ENTER:
			return 13
		KEY_ESCAPE:
			return 27
		KEY_BACKSPACE:
			return 8
		KEY_TAB:
			return 9
	if e.ctrl_pressed and not e.alt_pressed:
		if k >= KEY_A and k <= KEY_Z:
			return k - KEY_A + 1
		match k:
			KEY_BRACKETLEFT:
				return 27
			KEY_BACKSLASH:
				return 28
			KEY_BRACKETRIGHT:
				return 29
		return -1
	var u := e.unicode
	if u >= 32 and u < 127:
		return u
	return -1
