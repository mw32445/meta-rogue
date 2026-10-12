## Emulation side of the curses differential fuzzer. Runs an op script (see
## harness/curses_fuzz/cfuzz.c) on the GDScript Curses emulation and writes the
## same output cfuzz prints for real ncurses.
##
## usage: godot --headless --path godot --script res://tests/curses_fuzz.gd -- OPS OUT [OPS OUT ...]
extends SceneTree


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or args.size() % 2 != 0:
		printerr("usage: curses_fuzz.gd -- OPS OUT [OPS OUT ...]")
		quit(2)
		return
	for i in range(0, args.size(), 2):
		_run(args[i], args[i + 1])
	quit(0)


func _run(ops_path: String, out_path: String) -> void:
	var ops := FileAccess.open(ops_path, FileAccess.READ)
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	var c := Curses.new()
	var wins := {0: c.stdscr, 1: c.curscr}
	while not ops.eof_reached():
		var line := ops.get_line()
		var f := line.split(" ", false)
		if f.is_empty() or f[0].begins_with("#"):
			continue
		out.store_string(line + "\n")
		var op := f[0]
		var r := 0
		if op == "newwin":
			var w = c.newwin(int(f[2]), int(f[3]), int(f[4]), int(f[5]))
			wins[int(f[1])] = w
			r = Curses.OK if w != null else Curses.ERR
		elif op == "subwin":
			var w = c.subwin(wins.get(int(f[2])), int(f[3]), int(f[4]), int(f[5]), int(f[6]))
			wins[int(f[1])] = w
			r = Curses.OK if w != null else Curses.ERR
		elif op == "dump":
			_dump(out, c.curscr, "=curscr", c.cursor_known)
			continue
		elif f.size() < 2 or wins.get(int(f[1])) == null:
			out.store_string("=bad\n")
			continue
		else:
			var w: Curses.CWindow = wins[int(f[1])]
			match op:
				"delwin":
					r = c.delwin(w)
					wins.erase(int(f[1]))
				"wmove": r = c.wmove(w, int(f[2]), int(f[3]))
				"waddch": r = c.waddch(w, int(f[2]))
				"waddstr": r = c.waddstr(w, _unhex(f[2]))
				"mvwaddch": r = c.mvwaddch(w, int(f[2]), int(f[3]), int(f[4]))
				"mvwaddstr": r = c.mvwaddstr(w, int(f[2]), int(f[3]), _unhex(f[4]))
				"wclrtoeol": r = c.wclrtoeol(w)
				"werase": r = c.werase(w)
				"wclear": r = c.wclear(w)
				"touchwin": r = c.touchwin(w)
				"wrefresh": r = c.wrefresh(w)
				"clearok": r = c.clearok(w, int(f[2]) != 0)
				"leaveok": r = c.leaveok(w, int(f[2]) != 0)
				"wstandout": r = c.wstandout(w)
				"wstandend": r = c.wstandend(w)
				"wattrset": r = c.wattrset(w, int(f[2]))
				"winch":
					out.store_string("=%x\n" % c.winch(w))
					continue
				"mvwinch":
					out.store_string("=%x\n" % c.mvwinch(w, int(f[2]), int(f[3])))
					continue
				"getyx":
					out.store_string("=%d,%d\n" % [c.getcury(w), c.getcurx(w)])
					continue
				"mvwin": r = c.mvwin(w, int(f[2]), int(f[3]))
				"getch":
					if (w._flags & Curses._ISPAD) == 0 \
							and (c.is_wintouched(w) or (w._flags & Curses._HASMOVED) != 0):
						r = c.wrefresh(w)
					else:
						r = 1
				"wdump":
					_dump(out, w, "=win", true)
					continue
				_:
					out.store_string("=bad\n")
					continue
		out.store_string("=%d\n" % r)
	out.close()


func _unhex(h: String) -> String:
	var s := ""
	var i := 0
	while i + 1 < h.length():
		s += char(h.substr(i, 2).hex_to_int())
		i += 2
	return s


func _dump(out: FileAccess, w: Curses.CWindow, tag: String, cursor_known: bool) -> void:
	var cur := "%d,%d" % [w._cury, w._curx] if cursor_known else "?"
	var s := "%s %s" % [tag, cur]
	for y in w._maxy + 1:
		s += "\n "
		for x in w._maxx + 1:
			s += "%x " % w.get_cell(y, x)
	out.store_string(s + "\n")
