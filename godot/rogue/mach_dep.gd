## mach_dep.c: Various installation dependent routines
##
## @(#)mach_dep.c	4.37 (Berkeley) 05/23/83
##
## The load-average and checkout code (MAXLOAD, MAXUSERS, CHECKTIME) is not
## compiled into the default build and is not ported. The score file itself is
## read and written by Save.rd_score/wr_score.
class_name MachDep
extends RogueBase


## init_check:
##	Check out too see if it is proper to play the game now
static func init_check() -> void:
	pass


## open_score:
##	Open up the score file for future use
static func open_score() -> void:
	pass


## setup:
##	Get starting setup for all games
static func setup() -> void:
	Mdport.md_onsignal_default()
	raw()			# Raw mode
	noecho()		# Echo off
	keypad(stdscr, true)
	getltchars()		# get the local tty chars


## getltchars:
##	Get the local tty chars for later use
static func getltchars() -> void:
	pass


## setltchars:
##	Set the local tty chars to the given values
static func setltchars(_c: int) -> void:
	pass


## resetltchars:
##	Reset the local tty chars to original values.
static func resetltchars() -> void:
	pass


## playltchars:
##	Set local tty chars to the values we use when playing.
static func playltchars() -> void:
	pass


## start_score:
##	Start the scoring sequence
static func start_score() -> void:
	pass


## is_symlink:
##	See if the file has a symbolic link
static func is_symlink(_sp: String) -> bool:
	return false


## lock_sc:
##	lock the score file.  If it takes too long, ask the user if
##	they care to wait.  Return TRUE if the lock is successful.
##	C: fopen(lockfile, "w+") always succeeds in a writable directory,
##	so the "very busy" prompt is never reached (it is kept for the record).
static func lock_sc() -> bool:
	var busy := false
	if busy:
		printf("The score file is very busy.  Do you want to wait longer\n")
		printf("for it to become free so your score can get posted?\n")
		printf("If so, type \"y\"\n")
		prbuf = await fgets_stdin(MAXSTR)
		return cat(prbuf, 0) == ord("y")
	return true


## unlock_sc:
##	Unlock the score file
static func unlock_sc() -> void:
	pass


## flush_type:
##	Flush typeahead for traps, etc.
static func flush_type() -> void:
	flushinp()
