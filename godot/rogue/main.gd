## main.c: Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## @(#)main.c	4.22 (Berkeley) 02/05/99
##
## rnd() and roll() live in RogueBase so every module can call them unqualified.
class_name Main
extends RogueBase


## main:
##	The main program, of course. argv/env come from RogueBase (argv, env_*).
static func main() -> void:
	var env: Variant
	var lowtime: int

	Mdport.md_init()

	if MASTER:
		# Check to see if he is a wizard
		if argv.size() >= 2 and argv[1] == "":
			if PASSWD == Mdport.md_crypt(Mdport.md_getpass("wizard's password: "), "mT"):
				wizard = true
				player.t_flags |= SEEMONST
				argv = argv.slice(1)

	# get home and options from environment
	home = Mdport.md_gethomedir().substr(0, MAXSTR)

	file_name = home
	file_name += "rogue.save"

	env = env_rogueopts
	if env != null:
		Options.parse_opts(env)
	if env == null or whoami == "":
		whoami = Options.strucpy(whoami, Mdport.md_getusername(), Mdport.md_getusername().length())
	lowtime = env_time
	if MASTER and wizard and env_seedvar != null:
		dnum = atoi(env_seedvar)
	else:
		dnum = lowtime + Mdport.md_getpid()
	seed_ = dnum & 0xFFFFFFFF

	if guild:	# the Fighters' Guild (docs/GUILD.md): a 20-entry Hall of Fame, and
				# pack letters a-z then A-Z for the bigger packs it sells
		numscores = 20
		Numname = "Twenty"
		pack_used.resize(52)
		pack_used.fill(false)
	MachDep.open_score()

	# Drop setuid/setgid after opening the scoreboard file.
	Mdport.md_normaluser()

	# check for print-score option
	Mdport.md_normaluser()	# we drop any setgid/setuid priveldges here

	if argv.size() == 2:
		if argv[1] == "-s":
			noscore = 1
			await Rip.score(0, -1, 0)
			await exit(0)
			return
		elif argv[1] == "-d":
			var seed0 := seed_
			dnum = rnd(100)	# throw away some rnd()s to break patterns
			if dnum == 0:
				# while (--dnum) wraps C's 32-bit int: 2^32 - 1 more draws, a full
				# period of the RNG minus one, which leaves seed where it started.
				seed_ = seed0
			else:
				while true:
					dnum -= 1
					if dnum == 0:
						break
					rnd(100)
			purse = rnd(100) + 1
			level = rnd(100) + 1
			initscr()
			MachDep.getltchars()
			await Rip.death(Rip.death_monst())
			await exit(0)
			return

	MachDep.init_check()	# check for legal startup
	if argv.size() == 2:
		if not await Save.restore(argv[1]):	# Note: restore will never return
			await my_exit(1)
			return
	if MASTER and wizard:
		printf("Hello %s, welcome to dungeon #%d", [whoami, dnum])
	else:
		printf("Hello %s, just a moment while I dig the dungeon...", [whoami])

	initscr()			# Start up cursor package
	Init.init_probs()		# Set up prob tables for objects
	await Init.init_player()	# Set up initial player stats
	Init.init_names()		# Set up names of scrolls
	Init.init_colors()		# Set up colors of potions
	Init.init_stones()		# Set up stone settings of rings
	Init.init_materials()		# Set up materials of wands
	if guild and loadout != null:	# the Guild's purchases (docs/GUILD.md), used once
		await Loadout.apply(loadout)
		loadout = null
	MachDep.setup()

	# The screen must be at least NUMLINES x NUMCOLS
	if LINES < NUMLINES or COLS < NUMCOLS:
		printf("\nSorry, the screen must be at least %dx%d\n", [NUMLINES, NUMCOLS])
		endwin()
		await my_exit(1)
		return

	# Set up windows
	hw = newwin(LINES, COLS, 0, 0)
	idlok(stdscr, true)
	idlok(hw, true)
	if MASTER:
		noscore = int(wizard)
	await NewLevel.new_level()	# Draw current level
	# Start up daemons and fuses
	Daemon.start_daemon(D_RUNNERS, 0, AFTER())
	Daemon.start_daemon(D_DOCTOR, 0, AFTER())
	Daemon.fuse(D_SWANDER, 0, WANDERTIME(), AFTER())
	Daemon.start_daemon(D_STOMACH, 0, AFTER())
	await playit()


## endit:
##	Exit the program abnormally.
static func endit(_sig: int) -> void:
	await fatal("Okay, bye bye!\n")


## fatal:
##	Exit the program, printing a message.
static func fatal(s: String) -> void:
	mvaddstr(LINES - 2, 0, s)
	refresh()
	endwin()
	await my_exit(0)


## tstp:
##	Handle stop and start signals (never installed: SIGTSTP is #undef'd)
static func tstp(_ignored: int) -> void:
	var oy := getcury(curscr)
	var ox := getcurx(curscr)

	# leave nicely
	mvcur(0, COLS - 1, LINES - 1, 0)
	endwin()
	MachDep.resetltchars()
	Mdport.md_tstpsignal()

	# start back up again
	Mdport.md_tstpresume()
	raw()
	noecho()
	keypad(stdscr, true)
	MachDep.playltchars()
	clearok(curscr, true)
	wrefresh(curscr)
	mvcur(getcury(curscr), getcurx(curscr), oy, ox)


## playit:
##	The main loop of the program.  Loop until the game is over,
##	refreshing things and looking at the proper times.
static func playit() -> void:
	var opts: Variant

	# set up defaults for slow terminals
	if baudrate() <= 1200:
		terse = true
		jump = true
		see_floor = false

	if Mdport.md_hasclreol():
		inv_type = INV_CLEAR

	# parse environment declaration of options
	opts = env_rogueopts
	if opts != null:
		Options.parse_opts(opts)

	oldpos.copy_from(hero)
	oldrp = Chase.roomin(hero)
	while playing:
		await Command.command()	# Command execution
	await endit(0)


## quit:
##	Have player make certain, then exit.
static func quit(_sig: int) -> void:
	var oy: int
	var ox: int

	# Reset the signal in case we got here via an interrupt
	if not q_comm:
		mpos = 0
	oy = getcury(curscr)
	ox = getcurx(curscr)
	await Io.msg("really quit?")
	if await Io.readchar() == ord("y"):
		clear()
		mvprintw(LINES - 2, 0, "You quit with %d gold pieces", [purse])
		move(LINES - 1, 0)
		refresh()
		await Rip.score(purse, 1, 0)
		await my_exit(0)
	else:
		move(0, 0)
		clrtoeol()
		await Io.status()
		move(oy, ox)
		refresh()
		mpos = 0
		count = 0
		to_death = false


## leave:
##	Leave quickly, but curteously
static func leave(_sig: int) -> void:
	if not isendwin():
		mvcur(0, COLS - 1, LINES - 1, 0)
		endwin()
	putchar(ord("\n"))
	await my_exit(0)


## shell:
##	Let them escape for a while
static func shell() -> void:
	# Set the terminal back to original mode
	move(LINES - 1, 0)
	refresh()
	endwin()
	MachDep.resetltchars()
	putchar(ord("\n"))
	in_shell = true
	after = false

	# Fork and do a shell (the port never spawns one)
	Mdport.md_shellescape()

	printf("\n[Press return to continue]")
	noecho()
	raw()
	keypad(stdscr, true)
	MachDep.playltchars()
	in_shell = false
	await Io.wait_for(ord("\n"))
	clearok(stdscr, true)


## my_exit:
##	Leave the process properly
static func my_exit(st: int) -> void:
	MachDep.resetltchars()
	await exit(st)
