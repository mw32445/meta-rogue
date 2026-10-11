## io.c: Various input/output functions
##
## @(#)io.c	4.32 (Berkeley) 02/05/99
class_name Io
extends RogueBase

## #define MAXMSG (NUMCOLS - sizeof "--More--")
const MAXMSG := NUMCOLS - 9

const STATE_NAME: Array[String] = ["", "Hungry", "Weak", "Faint"]


## msg:
##	Display a message at the top of the screen.
static func msg(fmt: String, args: Array = []) -> int:
	# if the string is "", just clear the line
	if fmt == "":
		move(0, 0)
		clrtoeol()
		mpos = 0
		return ~ESCAPE
	# otherwise add to the message and flush it out
	await doadd(fmt, args)
	return await endmsg()


## addmsg:
##	Add things to the current message
static func addmsg(fmt: String, args: Array = []) -> void:
	await doadd(fmt, args)


## endmsg:
##	Display a new msg (giving him a chance to see the previous one
##	if it is up there with the --More--)
static func endmsg() -> int:
	var ch: int
	if save_msg:
		huh = _io_msgbuf
	if mpos != 0:
		await Misc.look(false)
		mvaddstr(0, mpos, "--More--")
		refresh()
		if not msg_esc:
			await wait_for(ord(" "))
		else:
			while true:
				ch = await readchar()
				if ch == ord(" "):
					break
				if ch == ESCAPE:
					_io_msgbuf = ""
					mpos = 0
					_io_newpos = 0
					_io_msgbuf = ""
					return ESCAPE
	# All messages should start with uppercase, except ones that
	# start with a pack addressing character
	if islower(cat(_io_msgbuf, 0)) and not lower_msg and cat(_io_msgbuf, 1) != ord(")"):
		_io_msgbuf = chr(toupper(cat(_io_msgbuf, 0))) + _io_msgbuf.substr(1)
	mvaddstr(0, 0, _io_msgbuf)
	clrtoeol()
	mpos = _io_newpos
	_io_newpos = 0
	_io_msgbuf = ""
	refresh()
	return ~ESCAPE


## doadd:
##	Perform an add onto the message buffer
static func doadd(fmt: String, args: Array) -> void:
	# Do the printf into buf
	var buf := sprintf(fmt, args)
	if buf.length() + _io_newpos >= MAXMSG:
		await endmsg()
	_io_msgbuf += buf
	_io_newpos = _io_msgbuf.length()


## step_ok:
##	Returns true if it is ok to step on ch
static func step_ok(ch: int) -> bool:
	match ch:
		32, 124, 45:	# ' ' '|' '-'
			return false
		_:
			return not isalpha(ch)


## readchar:
##	Reads and returns a character, checking for gross input errors
static func readchar() -> int:
	var ch: int = to_schar(await Mdport.md_readchar())
	if ch == 3:
		await Main.quit(0)
		return 27
	return ch


## status:
##	Display the important stats line.  Keep the cursor where it was.
static func status() -> void:
	var oy: int
	var ox: int
	var temp: int

	# If nothing has changed since the last status, don't
	# bother.
	temp = cur_armor.o_arm if cur_armor != null else pstats.s_arm
	if _status_s_hp == pstats.s_hpt and _status_s_exp == pstats.s_exp \
			and _status_s_pur == purse and _status_s_arm == temp \
			and _status_s_str == pstats.s_str and _status_s_lvl == level \
			and _status_s_hungry == hungry_state and not stat_msg:
		return

	_status_s_arm = temp

	oy = getcury(stdscr)
	ox = getcurx(stdscr)
	if _status_s_hp != max_hp:
		temp = max_hp
		_status_s_hp = max_hp
		_status_hpwidth = 0
		while temp != 0:
			_status_hpwidth += 1
			temp /= 10

	# Save current status
	_status_s_lvl = level
	_status_s_pur = purse
	_status_s_hp = pstats.s_hpt
	_status_s_str = pstats.s_str
	_status_s_exp = pstats.s_exp
	_status_s_hungry = hungry_state

	if stat_msg:
		move(0, 0)
		await msg("Level: %d  Gold: %-5d  Hp: %*d(%*d)  Str: %2d(%d)  Arm: %-2d  Exp: %d/%d  %s",
			[level, purse, _status_hpwidth, pstats.s_hpt, _status_hpwidth, max_hp,
			pstats.s_str, max_stats.s_str, 10 - _status_s_arm, pstats.s_lvl,
			pstats.s_exp, STATE_NAME[hungry_state]])
	else:
		move(STATLINE, 0)
		printw("Level: %d  Gold: %-5d  Hp: %*d(%*d)  Str: %2d(%d)  Arm: %-2d  Exp: %d/%d  %s",
			[level, purse, _status_hpwidth, pstats.s_hpt, _status_hpwidth, max_hp,
			pstats.s_str, max_stats.s_str, 10 - _status_s_arm, pstats.s_lvl,
			pstats.s_exp, STATE_NAME[hungry_state]])

	clrtoeol()
	move(oy, ox)


## wait_for
##	Sit around until the guy types the right key
static func wait_for(ch: int) -> void:
	var c: int
	if ch == ord("\n"):
		while true:
			c = await readchar()
			if c == ord("\n") or c == ord("\r"):
				break
	else:
		while true:
			c = await readchar()
			if c == ch:
				break


## show_win:
##	Function used to display a window and wait before returning
static func show_win(message: String) -> void:
	var win := hw
	wmove(win, 0, 0)
	waddstr(win, message)
	touchwin(win)
	wmove(win, hero.y, hero.x)
	wrefresh(win)
	await wait_for(ord(" "))
	clearok(curscr, true)
	touchwin(stdscr)
