## Curses emulation: the subset of ncurses 6.4 that Rogue uses, with ncurses'
## exact semantics. Rogue reads its own screen back into game state and the RNG
## (t_oldch, set_mname, seen_stairs), so wrapping, ERR paths, attributes and
## change-tracked refresh must all match. Verified against real ncurses by the
## differential fuzzer (harness/curses_fuzz, godot/tests/curses_fuzz.gd).
##
## Model: every window holds chtype cells (char | attribute bits, ncurses
## layout) and per-line dirty ranges. Rogue only refreshes with wrefresh
## (wnoutrefresh + doupdate), so newscr and curscr are one virtual screen.
##
## Input: wgetch()/wgetnstr()/read_line() are coroutines that await keys fed
## by push_key() (interactive) or by a replay driver. A per-key step hook lets
## the test runner log the state at every keyboard read.
class_name Curses
extends RefCounted

const OK := 0
const ERR := -1

const A_NORMAL := 0
const A_CHARTEXT := 0xFF
const A_ATTRIBUTES := 0xFFFFFF00
const A_COLOR := 0xFF00
const A_STANDOUT := 0x10000
const A_ALTCHARSET := 0x400000
## (chtype) ERR, what mvinch() returns for an illegal position
const CHTYPE_ERR := 0xFFFFFFFF

## ncurses KEY_* codes (Linux)
const KEY_MIN := 257
const KEY_DOWN := 258
const KEY_UP := 259
const KEY_LEFT := 260
const KEY_RIGHT := 261
const KEY_HOME := 262
const KEY_BACKSPACE := 263
const KEY_NPAGE := 338
const KEY_PPAGE := 339
const KEY_ENTER := 343
const KEY_A1 := 348
const KEY_A3 := 349
const KEY_B2 := 350
const KEY_C1 := 351
const KEY_C3 := 352
const KEY_END := 360
const KEY_LL := 347
const KEY_SEND := 386
const KEY_SHOME := 391
const KEY_SLEFT := 393
const KEY_SNEXT := 396
const KEY_SPREVIOUS := 398
const KEY_SRIGHT := 402
const KEY_EOL := 335
const KEY_SR := 337
const KEY_SF := 336

const _ISPAD := 0x10
const _HASMOVED := 0x20
const _WRAPPED := 0x40
const _NOCHANGE := -1
const TABSIZE := 8

## Erase/kill characters of the emulated tty (pinned the same in the oracle).
const ERASE_CHAR := 8	# ^H
const KILL_CHAR := 21	# ^U


class CWindow:
	extends RefCounted
	var _cury := 0
	var _curx := 0
	var _maxy := 0
	var _maxx := 0
	var _begy := 0
	var _begx := 0
	var _flags := 0
	var _attrs := 0
	var _bkgd := 32
	var _clear := false
	var _leaveok := false
	var _scroll := false
	var _regtop := 0
	var _regbottom := 0
	var _parent: CWindow = null
	var _pary := 0
	var _parx := 0
	var _children := 0
	var ncols := 0
	var cells := PackedInt64Array()
	var firstchar := PackedInt32Array()
	var lastchar := PackedInt32Array()

	func _init(nlines: int, ncolumns: int, begy: int, begx: int) -> void:
		ncols = ncolumns
		_maxy = nlines - 1
		_maxx = ncolumns - 1
		_begy = begy
		_begx = begx
		_regbottom = _maxy
		cells.resize(nlines * ncolumns)
		cells.fill(32)
		# SVr4/ncurses: a new window is entirely "changed"
		firstchar.resize(nlines)
		firstchar.fill(0)
		lastchar.resize(nlines)
		lastchar.fill(_maxx)

	func get_cell(y: int, x: int) -> int:
		if _parent != null:
			return _parent.get_cell(y + _pary, x + _parx)
		return cells[y * ncols + x]

	func set_cell(y: int, x: int, v: int) -> void:
		if _parent != null:
			_parent.set_cell(y + _pary, x + _parx, v)
		else:
			cells[y * ncols + x] = v

	## CHANGED_CELL
	func changed_cell(y: int, x: int) -> void:
		if firstchar[y] == _NOCHANGE:
			firstchar[y] = x
			lastchar[y] = x
		elif x < firstchar[y]:
			firstchar[y] = x
		elif x > lastchar[y]:
			lastchar[y] = x

	## CHANGED_RANGE
	func changed_range(y: int, start: int, end: int) -> void:
		if firstchar[y] == _NOCHANGE or firstchar[y] > start:
			firstchar[y] = start
		if lastchar[y] == _NOCHANGE or lastchar[y] < end:
			lastchar[y] = end

	## CHANGED_TO_EOL
	func changed_to_eol(y: int, start: int, end: int) -> void:
		if firstchar[y] == _NOCHANGE or firstchar[y] > start:
			firstchar[y] = start
		lastchar[y] = end

	func legal_yx(y: int, x: int) -> bool:
		return y >= 0 and y <= _maxy and x >= 0 and x <= _maxx


var LINES := 24
var COLS := 80
var stdscr: CWindow
## The physical screen (merged newscr/curscr).
var curscr: CWindow
## False when the last refresh used leaveok: the cursor is wherever ncurses'
## update optimizer left it, which the emulation does not model.
var cursor_known := true
var _endwin := false
var _halfdelay := false
## score() deleted curscr: only the stdout stream remains (step log writes Z).
var curses_gone := false
## CWindow ids for test tooling; the game uses CWindow references.
var windows: Dictionary = {}

## ---- input ---------------------------------------------------------------
signal _key_ready
var _queue: Array[int] = []
var _waiters := 0
## Replay mode: keys come from this script; -1 ends the run.
var script_keys: PackedInt32Array = PackedInt32Array()
var script_pos := 0
var replay := false
## Called as step_hook.call(key) at every keyboard read (test step log).
var step_hook: Callable = Callable()
## Emitted when the key script is exhausted (replay) - the run is over.
signal script_finished
## Emitted when the program calls exit(); the coroutine stack is then abandoned.
signal program_exited(status: int)
signal _halt	## never emitted
var exit_status := -1
## Called as exit_hook.call(status) when the program exits (test step log).
var exit_hook: Callable = Callable()
## Output stream for bytes written to stdout (printf/putchar after endwin, BEL).
var stdout_bytes := PackedByteArray()


func _init(lines := 24, cols := 80) -> void:
	LINES = lines
	COLS = cols
	curscr = CWindow.new(lines, cols, 0, 0)
	stdscr = CWindow.new(lines, cols, 0, 0)
	windows[0] = stdscr
	windows[1] = curscr


## ---- windows -------------------------------------------------------------

func newwin(nlines: int, ncols: int, begy: int, begx: int) -> CWindow:
	if begy < 0 or begx < 0 or nlines < 0 or ncols < 0:
		return null
	if nlines == 0:
		nlines = LINES - begy
	if ncols == 0:
		ncols = COLS - begx
	if nlines <= 0 or ncols <= 0:
		return null
	return CWindow.new(nlines, ncols, begy, begx)


## subwin: shares storage with orig; begy/begx are screen-relative.
func subwin(orig: CWindow, nlines: int, ncols: int, begy: int, begx: int) -> CWindow:
	if orig == null:
		return null
	return derwin(orig, nlines, ncols, begy - orig._begy, begx - orig._begx)


## derwin: begy/begx are relative to orig.
func derwin(orig: CWindow, nlines: int, ncols: int, pary: int, parx: int) -> CWindow:
	if pary < 0 or parx < 0 or orig == null or nlines < 0 or ncols < 0:
		return null
	if pary + nlines > orig._maxy + 1 or parx + ncols > orig._maxx + 1:
		return null
	if nlines == 0:
		nlines = orig._maxy + 1 - pary
	if ncols == 0:
		ncols = orig._maxx + 1 - parx
	if nlines <= 0 or ncols <= 0:
		return null
	var w := CWindow.new(nlines, ncols, orig._begy + pary, orig._begx + parx)
	orig._children += 1
	w._parent = orig
	w._pary = pary
	w._parx = parx
	w._attrs = orig._attrs
	w._bkgd = orig._bkgd
	w.cells = PackedInt64Array()
	return w


## Fails (and keeps the window) while it still has subwindows, as in ncurses.
func delwin(win: CWindow) -> int:
	if win == null or win._children > 0:
		return ERR
	if win._parent != null:
		win._parent._children -= 1
		touchwin(win._parent)
	if win == curscr:
		curses_gone = true
	return OK


func mvwin(win: CWindow, y: int, x: int) -> int:
	if win == null:
		return ERR
	if y < 0 or x < 0 or y + win._maxy > LINES - 1 or x + win._maxx > COLS - 1:
		return ERR
	win._begy = y
	win._begx = x
	touchwin(win)
	return OK


func wmove(win: CWindow, y: int, x: int) -> int:
	if win == null or not win.legal_yx(y, x):
		return ERR
	win._cury = y
	win._curx = x
	win._flags &= ~_WRAPPED
	win._flags |= _HASMOVED
	return OK


func getcury(win: CWindow) -> int:
	return win._cury


func getcurx(win: CWindow) -> int:
	return win._curx


func getmaxy(win: CWindow) -> int:
	return win._maxy + 1


func getmaxx(win: CWindow) -> int:
	return win._maxx + 1


func leaveok(win: CWindow, bf: bool) -> int:
	win._leaveok = bf
	return OK


func clearok(win: CWindow, bf: bool) -> int:
	win._clear = bf
	return OK


func idlok(_win: CWindow, _bf: bool) -> int:
	return OK


func keypad(_win: CWindow, _bf: bool) -> int:
	return OK


func wattrset(win: CWindow, attrs: int) -> int:
	win._attrs = attrs
	return OK


func wstandout(win: CWindow) -> int:
	return wattrset(win, A_STANDOUT)


func wstandend(win: CWindow) -> int:
	return wattrset(win, A_NORMAL)


func touchwin(win: CWindow) -> int:
	for y in win._maxy + 1:
		win.firstchar[y] = 0
		win.lastchar[y] = win._maxx
	return OK


func is_wintouched(win: CWindow) -> bool:
	for y in win._maxy + 1:
		if win.firstchar[y] != _NOCHANGE:
			return true
	return false


## ---- output --------------------------------------------------------------

static func unctrl(c: int) -> String:
	c &= 0xFF
	if c < 32:
		return "^" + char(c + 64)
	if c == 127:
		return "^?"
	if c < 127:
		return char(c)
	# 128-255 do not occur in Rogue's text
	return "~" + char(c & 0x7F)


func _render_char(win: CWindow, ch: int) -> int:
	var a := win._attrs
	if (ch & A_CHARTEXT) == 32 and (ch & A_ATTRIBUTES) == 0:
		return (win._bkgd & A_CHARTEXT) | a | (win._bkgd & A_ATTRIBUTES)
	return ch | a


## newline_forces_scroll: advances *ypos unless at the bottom of the scroll region
func _newline_forces_scroll(win: CWindow) -> bool:
	var y := win._cury
	if y >= win._regtop and y <= win._regbottom:
		if y == win._regbottom:
			return true
		elif y < win._maxy:
			win._cury = y + 1
	elif y < win._maxy:
		win._cury = y + 1
	return false


func _wrap_to_next_line(win: CWindow) -> int:
	win._flags |= _WRAPPED
	if _newline_forces_scroll(win):
		win._curx = win._maxx
		if not win._scroll:
			return ERR
	win._curx = 0
	return OK


func _waddch_literal(win: CWindow, ch: int) -> int:
	var x := win._curx
	var y := win._cury
	if not win.legal_yx(y, x):
		return ERR
	ch = _render_char(win, ch)
	win.changed_cell(y, x)
	win.set_cell(y, x, ch)
	x += 1
	if x > win._maxx:
		return _wrap_to_next_line(win)
	win._curx = x
	return OK


func waddch(win: CWindow, ch: int) -> int:
	if win == null:
		return ERR
	ch &= 0xFFFFFFFF
	var t := ch & A_CHARTEXT
	var s := unctrl(t)
	if (ch & A_ALTCHARSET) != 0 or s.length() == 1 or (t >= 32 and t < 127):
		return _waddch_literal(win, ch)
	var x := win._curx
	var y := win._cury
	if not win.legal_yx(y, x):
		return ERR
	match t:
		9:	# '\t'
			x = x + (TABSIZE - (x % TABSIZE))
			if (not win._scroll and y == win._regbottom) or x <= win._maxx:
				var blank := 32 | (ch & A_ATTRIBUTES)
				while win._curx < x:
					if _waddch_literal(win, blank) == ERR:
						return ERR
				return OK
			else:
				wclrtoeol(win)
				win._flags |= _WRAPPED
				if _newline_forces_scroll(win):
					x = win._maxx
				else:
					x = 0
				y = win._cury
		10:	# '\n'
			wclrtoeol(win)
			if _newline_forces_scroll(win):
				return ERR
			y = win._cury
			x = 0
			win._flags &= ~_WRAPPED
		13:	# '\r'
			x = 0
			win._flags &= ~_WRAPPED
		8:	# '\b'
			if x == 0:
				return OK
			x -= 1
			win._flags &= ~_WRAPPED
		_:
			for i in s.length():
				if _waddch_literal(win, s.unicode_at(i) | (ch & A_ATTRIBUTES)) == ERR:
					return ERR
			return OK
	win._curx = x
	win._cury = y
	return OK


func waddstr(win: CWindow, s: String) -> int:
	if win == null:
		return ERR
	for i in s.length():
		var c := s.unicode_at(i)
		if c == 0:
			break
		if waddch(win, c & 0xFF) == ERR:
			return ERR
	return OK


func mvwaddch(win: CWindow, y: int, x: int, ch: int) -> int:
	if wmove(win, y, x) == ERR:
		return ERR
	return waddch(win, ch)


func mvwaddstr(win: CWindow, y: int, x: int, s: String) -> int:
	if wmove(win, y, x) == ERR:
		return ERR
	return waddstr(win, s)


func wclrtoeol(win: CWindow) -> int:
	if win == null:
		return ERR
	var y := win._cury
	var x := win._curx
	# just wrapped: the clear applies to the new line, unless at the bottom right
	if (win._flags & _WRAPPED) != 0 and y < win._maxy:
		win._flags &= ~_WRAPPED
	if (win._flags & _WRAPPED) != 0 or y > win._maxy or x > win._maxx:
		return ERR
	win.changed_to_eol(y, x, win._maxx)
	for i in range(x, win._maxx + 1):
		win.set_cell(y, i, win._bkgd)
	return OK


func werase(win: CWindow) -> int:
	if win == null:
		return ERR
	for y in win._maxy + 1:
		for x in win._maxx + 1:
			win.set_cell(y, x, win._bkgd)
		win.firstchar[y] = 0
		win.lastchar[y] = win._maxx
	win._curx = 0
	win._cury = 0
	win._flags &= ~_WRAPPED
	return OK


func wclear(win: CWindow) -> int:
	if werase(win) == ERR:
		return ERR
	win._clear = true
	return OK


func winch(win: CWindow) -> int:
	return win.get_cell(win._cury, win._curx)


func mvwinch(win: CWindow, y: int, x: int) -> int:
	if wmove(win, y, x) == ERR:
		return CHTYPE_ERR
	return winch(win)


## ---- refresh -------------------------------------------------------------

## Mark changed every cell of win that is changed in any of its ancestors.
func wsyncdown(win: CWindow) -> void:
	if win == null or win._parent == null:
		return
	var pp := win._parent
	wsyncdown(pp)
	for y in win._maxy + 1:
		if pp.firstchar[win._pary + y] >= 0:
			var left := pp.firstchar[win._pary + y] - win._parx
			var right := pp.lastchar[win._pary + y] - win._parx
			if left < 0:
				left = 0
			if right > win._maxx:
				right = win._maxx
			win.changed_range(y, left, right)


func wnoutrefresh(win: CWindow) -> int:
	if win == null or (win._flags & _ISPAD) != 0:
		return ERR
	wsyncdown(win)
	var begx := win._begx
	var begy := win._begy
	var limit_x := win._maxx
	if limit_x > curscr._maxx - begx:
		limit_x = curscr._maxx - begx
	var src_row := 0
	var dst_row := begy
	while src_row <= win._maxy and dst_row <= curscr._maxy:
		if win.firstchar[src_row] != _NOCHANGE:
			var last_src := win.lastchar[src_row]
			if last_src > limit_x:
				last_src = limit_x
			var src_col := win.firstchar[src_row]
			var dst_col := src_col + begx
			while src_col <= last_src:
				var v := win.get_cell(src_row, src_col)
				if curscr.get_cell(dst_row, dst_col) != v:
					curscr.set_cell(dst_row, dst_col, v)
				src_col += 1
				dst_col += 1
		win.firstchar[src_row] = _NOCHANGE
		win.lastchar[src_row] = _NOCHANGE
		src_row += 1
		dst_row += 1
	win._clear = false
	if not win._leaveok:
		curscr._cury = win._cury + win._begy
		curscr._curx = win._curx + win._begx
		cursor_known = true
	else:
		cursor_known = false
	win._flags &= ~_HASMOVED
	return OK


func doupdate() -> int:
	_endwin = false
	return OK


func wrefresh(win: CWindow) -> int:
	if win == null:
		return ERR
	if win == curscr:
		return doupdate()
	var code := wnoutrefresh(win)
	if code == OK:
		code = doupdate()
	return code


func endwin() -> int:
	_endwin = true
	return OK


func isendwin() -> bool:
	return _endwin


## ---- modes ---------------------------------------------------------------

func halfdelay(_tenths: int) -> int:
	_halfdelay = true
	return OK


func nocbreak() -> int:
	_halfdelay = false
	return OK


func raw() -> int:
	_halfdelay = false
	return OK


func noecho() -> int:
	return OK


func baudrate() -> int:
	return 38400


func erasechar() -> int:
	return ERASE_CHAR


func killchar() -> int:
	return KILL_CHAR


## Discard typeahead (interactive only; scripted keys are delivered on demand).
func flushinp() -> int:
	if not replay:
		_queue.clear()
	return OK


## Bytes the C program writes to stdout with printf/putchar.
func stdout_write(s: String) -> void:
	for i in s.length():
		stdout_bytes.append(s.unicode_at(i) & 0xFF)


## ---- input ---------------------------------------------------------------

## Interactive: queue a key and resume the waiting coroutine.
func push_key(key: int) -> void:
	_queue.push_back(key)
	if _waiters > 0:
		_key_ready.emit()


## Replay driver: resume the game with the next scripted key.
func feed() -> void:
	_key_ready.emit()


func _next_key() -> int:
	# The tripwire: exactly one coroutine may wait for input. A second waiter
	# means some coroutine call was not awaited.
	assert(_waiters == 0, "two coroutines waiting for input (missing await?)")
	_waiters += 1
	if replay:
		await _key_ready
		_waiters -= 1
		if script_pos < script_keys.size():
			script_pos += 1
			return script_keys[script_pos - 1]
		return -1
	while _queue.is_empty():
		await _key_ready
	_waiters -= 1
	return _queue.pop_front()


## Read one scripted/typed key and log the step.
func _read_key() -> int:
	var key: int = await _next_key()
	if step_hook.is_valid():
		step_hook.call(key)
	if key < 0:
		script_finished.emit()
		await _halt	# never resumed: the run is over
	return key


## wgetch: refresh first if the window was touched or its cursor moved
## (ncurses recur_wrefresh), then wait. In halfdelay mode the wait times out,
## so an ESC is never merged with the following key.
func wgetch(win: CWindow) -> int:
	if win != null and (win._flags & _ISPAD) == 0 \
			and (is_wintouched(win) or (win._flags & _HASMOVED) != 0):
		wrefresh(win)
	if _halfdelay:
		return ERR
	return await _read_key()


## wgetnstr with noecho (score's "[Press return to continue]").
func wgetnstr(win: CWindow, n: int) -> String:
	var s := PackedByteArray()
	while true:
		var ch: int = await wgetch(win)
		if ch == 10 or ch == 13 or ch == KEY_DOWN or ch == KEY_ENTER:
			break
		if ch == ERASE_CHAR or ch == KEY_LEFT or ch == KEY_BACKSPACE:
			if s.size() > 0:
				s.resize(s.size() - 1)
		elif ch == KILL_CHAR:
			s.clear()
		elif ch >= KEY_MIN or (n >= 0 and s.size() >= n):
			continue
		else:
			s.append(ch & 0xFF)
	return s.get_string_from_ascii()


## fgets(buf, size, stdin) after endwin: cooked line read.
func read_line(size: int) -> String:
	var s := PackedByteArray()
	while s.size() < size - 1:
		var ch: int = await _read_key()
		if ch == 13:
			ch = 10
		s.append(ch & 0xFF)
		if ch == 10:
			break
	return s.get_string_from_ascii()


## exit(status): record it, notify the host, and never return.
## Drop the suspended game: disconnecting the input signals frees the
## coroutine chain waiting on them (it holds this object, so it would leak).
func abandon() -> void:
	for sig in [_key_ready, _halt, script_finished, program_exited]:
		for c in sig.get_connections():
			sig.disconnect(c["callable"])


func exit_program(status: int) -> void:
	exit_status = status
	if exit_hook.is_valid():
		exit_hook.call(status)
	program_exited.emit(status)
	await _halt
