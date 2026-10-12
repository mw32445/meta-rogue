## options.c: This file has all the code for the option command.  I would rather
## this command were not necessary, but it is the only way to keep the
## wolves off of my back.
##
## @(#)options.c	4.24 (Berkeley) 05/10/83
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## The C option table holds pointers: o_opt points at the global to set and
## o_putfunc/o_getfunc are function pointers. Here o_opt is the name of the
## RogueBase global (read and written through _opt_get/_opt_set, i.e.
## *(type *) o_opt), and the two functions are ids dispatched by
## _putfunc/_getfunc. put_bool/put_inv_t/get_bool/get_sf/get_inv_t take that
## "pointer" (the global's name) like C takes void *.
##
## C char * out-parameters are values here:
##   get_str(opt, win) returns [retval, new contents of opt]
##   strucpy(s1, s2, len) returns the new contents of s1
##   get_num(vp, win) takes the int vp points at and returns [retval, new int]
class_name Options
extends RogueBase

## #define NUM_OPTS (sizeof optlist / sizeof (OPTION))
const NUM_OPTS := 10

## #define MAXINP 50: max string to read from terminal or environment
const MAXINP := 50

## struct optstruct (OPTION): description of an option and what to do with it
class Option:
	extends RefCounted
	var o_name: String		## option name
	var o_prompt: String		## prompt for interactive entry
	var o_opt: StringName		## pointer to thing to set (the global's name)
	var o_putfunc: StringName	## function to print value
	var o_getfunc: StringName	## function to get value interactively

	func _init(name: String, prompt: String, opt: StringName, putfunc: StringName,
			getfunc: StringName) -> void:
		o_name = name
		o_prompt = prompt
		o_opt = opt
		o_putfunc = putfunc
		o_getfunc = getfunc


## OPTION optlist[] (constant: built afresh on each use)
static func _optlist() -> Array[Option]:
	return [
		Option.new("terse", "Terse output",
			&"terse", &"put_bool", &"get_bool"),
		Option.new("flush", "Flush typeahead during battle",
			&"fight_flush", &"put_bool", &"get_bool"),
		Option.new("jump", "Show position only at end of run",
			&"jump", &"put_bool", &"get_bool"),
		Option.new("seefloor", "Show the lamp-illuminated floor",
			&"see_floor", &"put_bool", &"get_sf"),
		Option.new("passgo", "Follow turnings in passageways",
			&"passgo", &"put_bool", &"get_bool"),
		Option.new("tombstone", "Print out tombstone when killed",
			&"tombstone", &"put_bool", &"get_bool"),
		Option.new("inven", "Inventory style",
			&"inv_type", &"put_inv_t", &"get_inv_t"),
		Option.new("name", "Name",
			&"whoami", &"put_str", &"get_str"),
		Option.new("fruit", "Fruit",
			&"fruit", &"put_str", &"get_str"),
		Option.new("file", "Save file",
			&"file_name", &"put_str", &"get_str"),
	]


## *(type *) o_opt: the value of the global an option points at
static func _opt_get(o_opt: StringName) -> Variant:
	match o_opt:
		&"terse": return terse
		&"fight_flush": return fight_flush
		&"jump": return jump
		&"see_floor": return see_floor
		&"passgo": return passgo
		&"tombstone": return tombstone
		&"inv_type": return inv_type
		&"whoami": return whoami
		&"fruit": return fruit
		&"file_name": return file_name
	push_error("options: no global " + o_opt)
	return null


## *(type *) o_opt = v: set the global an option points at
static func _opt_set(o_opt: StringName, v: Variant) -> void:
	match o_opt:
		&"terse": terse = v
		&"fight_flush": fight_flush = v
		&"jump": jump = v
		&"see_floor": see_floor = v
		&"passgo": passgo = v
		&"tombstone": tombstone = v
		&"inv_type": inv_type = v
		&"whoami": whoami = v
		&"fruit": fruit = v
		&"file_name": file_name = v
		_: push_error("options: no global " + o_opt)


## (*op->o_putfunc)(op->o_opt)
static func _putfunc(op: Option) -> void:
	match op.o_putfunc:
		&"put_bool": put_bool(op.o_opt)
		&"put_str": put_str(op.o_opt)
		&"put_inv_t": put_inv_t(op.o_opt)


## (*op->o_getfunc)(op->o_opt, win)
static func _getfunc(op: Option, win: Curses.CWindow) -> int:
	var r: Array
	match op.o_getfunc:
		&"get_bool":
			return await get_bool(op.o_opt, win)
		&"get_sf":
			return await get_sf(op.o_opt, win)
		&"get_inv_t":
			return await get_inv_t(op.o_opt, win)
		&"get_str":
			# get_str writes the string through its pointer: store it back
			r = await get_str(_opt_get(op.o_opt), win)
			_opt_set(op.o_opt, r[1])
			return r[0]
	push_error("options: no getfunc " + op.o_getfunc)
	return NORM


## option:
##	Print and then set options from the terminal
static func option() -> void:
	var optlist := _optlist()
	var op: int		# OPTION *op: index into optlist
	var retval: int

	wclear(hw)
	# Display current values of options
	op = 0
	while op <= NUM_OPTS - 1:
		pr_optname(optlist[op])
		_putfunc(optlist[op])
		waddch(hw, ord("\n"))
		op += 1
	# Set values
	wmove(hw, 0, 0)
	op = 0
	while op <= NUM_OPTS - 1:
		pr_optname(optlist[op])
		retval = await _getfunc(optlist[op], hw)
		if retval != 0:
			if retval == QUIT:
				break
			elif op > 0:	# MINUS
				wmove(hw, op - 1, 0)
				op -= 2
			else:	# trying to back up beyond the top
				putchar(7)	# '\007'
				wmove(hw, 0, 0)
				op -= 1
		op += 1
	# Switch back to original screen
	wmove(hw, LINES - 1, 0)
	waddstr(hw, "--Press space to continue--")
	wrefresh(hw)
	await Io.wait_for(ord(" "))
	clearok(curscr, true)
	touchwin(stdscr)
	after = false


## pr_optname:
##	Print out the option name prompt
static func pr_optname(op: Option) -> void:
	wprintw(hw, "%s (\"%s\"): ", [op.o_prompt, op.o_name])


## put_bool
##	Put out a boolean
static func put_bool(b: StringName) -> void:
	waddstr(hw, "True" if _opt_get(b) else "False")


## put_str:
##	Put out a string
static func put_str(str_: StringName) -> void:
	waddstr(hw, _opt_get(str_))


## put_inv_t:
##	Put out an inventory type
static func put_inv_t(ip: StringName) -> void:
	waddstr(hw, inv_t_name[_opt_get(ip)])


## get_bool:
##	Allow changing a boolean option and print it out
static func get_bool(vp: StringName, win: Curses.CWindow) -> int:
	var bp := vp	# bool *bp = (bool *) vp
	var oy: int
	var ox: int
	var op_bad: bool
	var ch: int

	op_bad = true
	oy = getcury(win)
	ox = getcurx(win)
	waddstr(win, "True" if _opt_get(bp) else "False")
	while op_bad:
		wmove(win, oy, ox)
		wrefresh(win)
		ch = await Io.readchar()
		match ch:
			ord("t"), ord("T"):
				_opt_set(bp, true)
				op_bad = false
			ord("f"), ord("F"):
				_opt_set(bp, false)
				op_bad = false
			ord("\n"), ord("\r"):
				op_bad = false
			ESCAPE:
				return QUIT
			ord("-"):
				return MINUS
			_:
				wmove(win, oy, ox + 10)
				waddstr(win, "(T or F)")
	wmove(win, oy, ox)
	waddstr(win, "True" if _opt_get(bp) else "False")
	waddch(win, ord("\n"))
	return NORM


## get_sf:
##	Change value and handle transition problems from see_floor to
##	!see_floor.
static func get_sf(vp: StringName, win: Curses.CWindow) -> int:
	var bp := vp	# bool *bp = (bool *) vp
	var was_sf: bool
	var retval: int

	was_sf = see_floor
	retval = await get_bool(bp, win)
	if retval == QUIT:
		return QUIT
	if was_sf != see_floor:
		if not see_floor:
			see_floor = true
			Misc.erase_lamp(hero, proom)
			see_floor = false
		else:
			await Misc.look(false)
	return NORM


## get_str:
##	Set a string option
##	C writes the string through vopt; here the new contents of vopt are
##	returned: [NORM/QUIT/MINUS, opt] (opt is vopt unchanged when nothing
##	was typed).
static func get_str(vopt: String, win: Curses.CWindow) -> Array:
	var opt := vopt	# char *opt = (char *) vopt
	var sp: int		# char *sp: index into buf
	var oy: int
	var ox: int
	var i: int
	var c: int		# signed char
	var buf := ""	# static char buf[MAXSTR]: [buf, sp) is written before it is read

	oy = getcury(win)
	ox = getcurx(win)
	wrefresh(win)
	# loop reading in the string, and put it in a temporary buffer
	sp = 0
	while true:
		c = await Io.readchar()
		if c == ord("\n") or c == ord("\r") or c == ESCAPE:
			break
		if c == -1:
			pass	# C: continue
		elif c == erasechar():	# process erase character
			if sp > 0:
				sp -= 1
				i = unctrl(cat(buf, sp)).length()
				buf = buf.substr(0, sp)
				while i != 0:
					waddch(win, ord("\b"))
					i -= 1
			# C: continue
		elif c == killchar():	# process kill character
			sp = 0
			buf = ""
			wmove(win, oy, ox)
			# C: continue
		elif sp == 0 and c == ord("-") and win != stdscr:
			break
		elif sp == 0 and c == ord("~"):
			buf = home	# strcpy(buf, home)
			waddstr(win, home)
			sp += home.length()
			# C: continue
		elif sp >= MAXINP or not (isprint(c) or c == ord(" ")):
			putchar(CTRL_G)
		else:
			buf += chr(c)	# *sp++ = c
			sp += 1
			waddstr(win, unctrl(c))
		# the for loop's increment: wclrtoeol(win), wrefresh(win)
		wclrtoeol(win)
		wrefresh(win)
	# *sp = '\0'
	if sp > 0:	# only change option if something has been typed
		opt = strucpy(opt, buf, buf.length())
	mvwprintw(win, oy, ox, "%s\n", [opt])
	wrefresh(win)
	if win == stdscr:
		mpos += sp
	if c == ord("-"):
		return [MINUS, opt]
	elif c == ESCAPE:
		return [QUIT, opt]
	else:
		return [NORM, opt]


## get_inv_t
##	Get an inventory type name
static func get_inv_t(vp: StringName, win: Curses.CWindow) -> int:
	var ip := vp	# int *ip = (int *) vp
	var oy: int
	var ox: int
	var op_bad: bool
	var ch: int

	op_bad = true
	oy = getcury(win)
	ox = getcurx(win)
	waddstr(win, inv_t_name[_opt_get(ip)])
	while op_bad:
		wmove(win, oy, ox)
		wrefresh(win)
		ch = await Io.readchar()
		match ch:
			ord("o"), ord("O"):
				_opt_set(ip, INV_OVER)
				op_bad = false
			ord("s"), ord("S"):
				_opt_set(ip, INV_SLOW)
				op_bad = false
			ord("c"), ord("C"):
				_opt_set(ip, INV_CLEAR)
				op_bad = false
			ord("\n"), ord("\r"):
				op_bad = false
			ESCAPE:
				return QUIT
			ord("-"):
				return MINUS
			_:
				wmove(win, oy, ox + 15)
				waddstr(win, "(O, S, or C)")
	mvwprintw(win, oy, ox, "%s\n", [inv_t_name[_opt_get(ip)]])
	return NORM


## get_num:
##	Get a numeric option (MASTER only)
##	C writes a short through vp. Its only caller passes &obj->o_goldval (an
##	int): vp is that int's value, and [retval, the int's new value] is
##	returned.
static func get_num(vp: int, win: Curses.CWindow) -> Array:
	var opt := vp	# short *opt = (short *) vp
	var i: int
	var r: Array

	r = await get_str(_get_num_buf, win)
	_get_num_buf = r[1]
	i = r[0]
	if i == NORM:
		if fixes:	# FIX 22: store the whole int (C: int *opt = (int *) vp)
			opt = _to_int32(atoi(_get_num_buf))
		else:
			# UB: *opt = (short) atoi(buf) stores 16 bits into the low half of
			# the int it points at (little-endian x86); the high half is kept.
			opt = (opt & ~0xFFFF) | (atoi(_get_num_buf) & 0xFFFF)
	return [i, opt]


## parse_opts:
##	Parse options from string, usually taken from the environment.
##	The string is a series of comma seperated values, with booleans
##	being stated as "name" (true) or "noname" (false), and strings
##	being "name=....", with the string being defined up to a comma
##	or the end of the entire option string.
##	C upper-cases the first letter of the inven value in place (in the
##	environment string, which playit() parses again); here the copy is
##	local: parsing the modified string gives the same result.
##	Reads past the end of the string (a string option at the very end with
##	no value) see NUL here; C reads whatever follows the string (UB).
static func parse_opts(str_: String) -> void:
	var buf := str_	# the C string (modified in place)
	var s := 0		# char *str: index into buf
	var sp: int		# char *sp: index into buf
	var len_: int
	var start: int	# char *start: offset into the string *op->o_opt
	var dst: String

	while cat(buf, s) != 0:
		# Get option name
		sp = s
		while isalpha(cat(buf, sp)):
			sp += 1
		len_ = sp - s
		# Look it up and deal with it
		for op: Option in _optlist():
			if EQSTR(buf.substr(s), op.o_name, len_):
				if op.o_putfunc == &"put_bool":	# if option is a boolean
					_opt_set(op.o_opt, true)	# NOSTRICT
				else:	# string option
					# Skip to start of string value
					s = sp + 1
					while cat(buf, s) == ord("="):
						s += 1
					if cat(buf, s) == ord("~"):
						if op.o_putfunc == &"put_inv_t":
							pass	# UB: C strcpy()s home over the int inv_type and the globals after it
						else:
							_opt_set(op.o_opt, home)	# strcpy((char *) op->o_opt, home)
						start = home.length()	# start = (char *) op->o_opt + strlen(home)
						while true:
							s += 1
							if cat(buf, s) != ord("/"):
								break
					else:
						start = 0	# start = (char *) op->o_opt
					# Skip to end of string value
					sp = s + 1
					while cat(buf, sp) != 0 and cat(buf, sp) != ord(","):
						sp += 1
					# check for type of inventory
					if op.o_putfunc == &"put_inv_t":
						if islower(cat(buf, s)):
							buf = buf.substr(0, s) + chr(toupper(cat(buf, s))) + buf.substr(s + 1)
						for i in range(INV_CLEAR + 1):	# i = inv_t_name; i <= &inv_t_name[INV_CLEAR]
							if _strncmp(buf.substr(s), inv_t_name[i], sp - s) == 0:
								inv_type = i
								break
					else:
						# strucpy(start, str, (int)(sp - str)): writes at start
						dst = _opt_get(op.o_opt)
						_opt_set(op.o_opt, dst.substr(0, start)
							+ strucpy(dst.substr(start), buf.substr(s), sp - s))
				break
			# check for "noname" for booleans
			elif op.o_putfunc == &"put_bool" \
					and EQSTR(buf.substr(s), "no", 2) and EQSTR(buf.substr(s + 2), op.o_name, len_ - 2):
				_opt_set(op.o_opt, false)	# NOSTRICT
				break

		# skip to start of next option name
		while cat(buf, sp) != 0 and not isalpha(cat(buf, sp)):
			sp += 1
		s = sp


## #define EQSTR(a, b, c) (strncmp(a, b, c) == 0)
static func EQSTR(a: String, b: String, c: int) -> bool:
	return _strncmp(a, b, c) == 0


## strncmp(s1, s2, n): n is a size_t (a negative int is huge)
static func _strncmp(s1: String, s2: String, n: int) -> int:
	var k := 0
	var c1: int
	var c2: int
	while n < 0 or k < n:
		c1 = cat(s1, k) & 0xFF
		c2 = cat(s2, k) & 0xFF
		if c1 != c2:
			return c1 - c2
		if c1 == 0:
			return 0
		k += 1
	return 0


## strucpy:
##	Copy string using unctrl for things
##	Returns what C writes at s1: the printable characters (and spaces) of
##	the first len (at most MAXINP) characters of s2.
static func strucpy(s1: String, s2: String, len_: int) -> String:
	var out := ""	# the characters written at s1
	var k := 0		# s2 index

	if len_ > MAXINP:
		len_ = MAXINP
	while len_ > 0:	# while (len--); len is never negative
		len_ -= 1
		if isprint(cat(s2, k)) or cat(s2, k) == ord(" "):
			out += chr(cat(s2, k))	# *s1++ = *s2
		k += 1
	# *s1 = '\0'
	return out
