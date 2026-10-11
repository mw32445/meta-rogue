## mdport.c: machine dependent functions, the part the game uses.
##
## Copyright (C) 2005-2008 Nicholas J. Kisseberth. The environment-facing
## functions return the values pinned in RogueBase (env_*), which are the real
## user/home/time in normal play and fixed values in tests.
class_name Mdport
extends RogueBase

const M_NORMAL := 0
const M_ESC := 1
const M_KEYPAD := 2
const M_TRAIL := 3


static func md_init() -> void:
	pass


static func md_onsignal_default() -> void:
	pass


static func md_onsignal_exit() -> void:
	pass


static func md_onsignal_autosave() -> void:
	pass


static func md_ignoreallsignals() -> void:
	pass


static func md_tstphold() -> void:
	pass


static func md_tstpresume() -> void:
	pass


static func md_tstpsignal() -> void:
	pass


## md_hasclreol: the emulated terminal has clear-to-end-of-line.
static func md_hasclreol() -> bool:
	return true


## termcap SO/SE are undefined with ncurses: these do nothing.
static func md_raw_standout() -> void:
	pass


static func md_raw_standend() -> void:
	pass


static func md_unlink_open_file(file: String, _inf: Variant = null) -> int:
	return md_unlink(file)


static func md_unlink(file: String) -> int:
	var path := cpath(file)
	if file != "" and not outside_rundir(file) and FileAccess.file_exists(path):
		return 0 if DirAccess.remove_absolute(path) == OK else -1
	return -1


static func md_chmod(_filename: String, _mode: int) -> int:
	return 0


static func md_normaluser() -> void:
	pass


static func md_getuid() -> int:
	return env_uid


static func md_getpid() -> int:
	return env_pid


static func md_getusername() -> String:
	return env_name


static func md_gethomedir() -> String:
	return env_home


static func md_sleep(_s: int) -> void:
	pass


static func md_getshell() -> String:
	return "/bin/sh"


## The port never spawns a shell (FIDELITY.md); shell() still shows its prompts.
static func md_shellescape() -> int:
	return 0


static func md_getrealname(_uid: int) -> String:
	return env_name


## Wizard password: any password is accepted (the oracle does the same).
static func md_crypt(_key: String, _salt: String) -> String:
	return PASSWD


static func md_getpass(_prompt: String) -> String:
	return "oracle"


static func md_erasechar() -> int:
	return erasechar()


static func md_killchar() -> int:
	return killchar()


static func md_dsuspchar() -> int:
	return 0


static func md_setdsuspchar(_c: int) -> int:
	return 0


static func md_suspchar() -> int:
	return 0


static func md_setsuspchar(_c: int) -> int:
	return 0


## md_readchar: read a key, translating escape sequences and curses KEY_*
## codes (arrows, keypad, Home/End/PgUp/PgDn, shifted keys) to Rogue commands.
## The emulated getch() returns ERR immediately in halfdelay mode, so an ESC is
## never merged with the next key (FIDELITY.md).
static func md_readchar() -> int:
	var ch := 0
	var lastch := 0
	var mode := M_NORMAL
	var mode2 := M_NORMAL

	while true:
		ch = await getch()

		if ch == ERR:	# timed out waiting for valid sequence
			# flush input so far and start over
			mode = M_NORMAL
			nocbreak()
			raw()
			ch = 27
			break

		if mode == M_TRAIL:
			if ch == ord("^"):	# msys console  : 7,5,6,8: modified
				ch = CTRL(toupper(lastch))
			if ch == ord("~"):	# cygwin console: 1,5,6,4: normal
				ch = tolower(lastch)	# windows telnet: 1,5,6,4: normal
										# msys console  : 7,5,6,8: normal
			if mode2 == M_ESC:	# cygwin console: 1,5,6,4: modified
				ch = CTRL(toupper(ch))
			break

		if mode == M_ESC:
			if ch == 27:
				mode2 = M_ESC
				continue
			if ch == ord("F") or ch == ord("O") or ch == ord("["):
				mode = M_KEYPAD
				continue
			match ch:
				# Cygwin Console, PuTTY
				Curses.KEY_LEFT: ch = CTRL_H
				Curses.KEY_RIGHT: ch = CTRL_L
				Curses.KEY_UP: ch = CTRL_K
				Curses.KEY_DOWN: ch = CTRL_J
				Curses.KEY_HOME: ch = CTRL_Y
				Curses.KEY_PPAGE: ch = CTRL_U
				Curses.KEY_NPAGE: ch = CTRL_N
				Curses.KEY_END: ch = CTRL_B
			break

		if mode == M_KEYPAD:
			match ch:
				# ESC F - Interix Console codes
				ord("^"): ch = CTRL_H	# Shift-Left
				ord("$"): ch = CTRL_L	# Shift-Right
				# ESC [ - Interix Console codes
				ord("H"): ch = ord("y")	# Home
				1: ch = CTRL_K		# Ctl-Keypad Up
				2: ch = CTRL_J		# Ctl-Keypad Down
				3: ch = CTRL_L		# Ctl-Keypad Right
				4: ch = CTRL_H		# Ctl-Keypad Left
				263: ch = CTRL_Y	# Ctl-Keypad Home
				19: ch = CTRL_U		# Ctl-Keypad PgUp
				20: ch = CTRL_N		# Ctl-Keypad PgDn
				21: ch = CTRL_B		# Ctl-Keypad End
				# ESC [ - Cygwin Console codes
				ord("G"): ch = ord(".")	# Keypad 5
				ord("7"):
					lastch = ord("Y")	# Ctl-Home
					mode = M_TRAIL
				ord("5"):
					lastch = ord("U")	# Ctl-PgUp
					mode = M_TRAIL
				ord("6"):
					lastch = ord("N")	# Ctl-PgDn
					mode = M_TRAIL
				# ESC [ - Win32 Telnet, PuTTY
				ord("1"):
					lastch = ord("y")	# Home
					mode = M_TRAIL
				ord("4"):
					lastch = ord("b")	# End
					mode = M_TRAIL
				# ESC O - PuTTY
				ord("D"): ch = CTRL_H
				ord("C"): ch = CTRL_L
				ord("A"): ch = CTRL_K
				ord("B"): ch = CTRL_J
				ord("t"): ch = ord("h")
				ord("v"): ch = ord("l")
				ord("x"): ch = ord("k")
				ord("r"): ch = ord("j")
				ord("w"): ch = ord("y")
				ord("y"): ch = ord("u")
				ord("s"): ch = ord("n")
				ord("q"): ch = ord("b")
				ord("u"): ch = ord(".")
			if mode != M_KEYPAD:
				continue

		if ch == 27:
			halfdelay(1)
			mode = M_ESC
			continue

		match ch:
			Curses.KEY_LEFT: ch = ord("h")
			Curses.KEY_DOWN: ch = ord("j")
			Curses.KEY_UP: ch = ord("k")
			Curses.KEY_RIGHT: ch = ord("l")
			Curses.KEY_HOME: ch = ord("y")
			Curses.KEY_PPAGE: ch = ord("u")
			Curses.KEY_END: ch = ord("b")
			Curses.KEY_LL: ch = ord("b")
			Curses.KEY_NPAGE: ch = ord("n")
			Curses.KEY_A1: ch = ord("y")
			Curses.KEY_A3: ch = ord("u")
			Curses.KEY_C1: ch = ord("b")
			Curses.KEY_C3: ch = ord("n")
			# next should be '.', but for problem with putty/linux
			Curses.KEY_B2: ch = ord("u")
			Curses.KEY_SRIGHT: ch = CTRL_L
			Curses.KEY_SLEFT: ch = CTRL_H
			Curses.KEY_SHOME: ch = CTRL_Y
			Curses.KEY_SPREVIOUS: ch = CTRL_U
			Curses.KEY_SEND: ch = CTRL_B
			Curses.KEY_SNEXT: ch = CTRL_N
			0x146: ch = CTRL_K	# Shift-Up
			0x145: ch = CTRL_J	# Shift-Down
			Curses.KEY_EOL: ch = CTRL_B
			# MSYS rxvt console
			511: ch = CTRL_J	# Shift Dn
			512: ch = CTRL_J	# Ctl Down
			514: ch = CTRL_H	# Ctl Left
			516: ch = CTRL_L	# Ctl Right
			518: ch = CTRL_K	# Shift Up
			519: ch = CTRL_K	# Ctl Up
			Curses.KEY_BACKSPACE: ch = CTRL_H
		break

	nocbreak()	# disable halfdelay mode if on
	raw()

	return ch & 0x7F
