## rip.c: File for the fun ends
## Death or a total win
##
## @(#)rip.c	4.57 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
class_name Rip
extends RogueBase


## struct sc_ent (score.h), typedef'd SCORE: one entry of the score file.
## C's SCORE *top_ten is an Array of Score here (Save.rd_score/wr_score take
## it); SCORE * pointers into it are indices.
class Score:
	extends RefCounted
	var sc_uid := 0		## unsigned int
	var sc_score := 0	## int
	var sc_flags := 0	## unsigned int
	var sc_monster := 0	## unsigned short
	var sc_name := ""	## char sc_name[MAXSTR]: the C string (up to the first NUL)
	var sc_level := 0	## int
	var sc_time := 0	## unsigned int (malloc garbage in C until rd_score fills it)

	## *this = *o (struct assignment)
	func copy_from(o: Score) -> void:
		sc_uid = o.sc_uid
		sc_score = o.sc_score
		sc_flags = o.sc_flags
		sc_monster = o.sc_monster
		sc_name = o.sc_name
		sc_level = o.sc_level
		sc_time = o.sc_time


const rip: Array[String] = [
"                       __________\n",
"                      /          \\\n",
"                     /    REST    \\\n",
"                    /      IN      \\\n",
"                   /     PEACE      \\\n",
"                  /                  \\\n",
"                  |                  |\n",
"                  |                  |\n",
"                  |   killed by a    |\n",
"                  |                  |\n",
"                  |       1980       |\n",
"                 *|     *  *  *      | *\n",
"         ________)/\\\\_//(\\/(/\\)/\\//\\/|_)_______\n",
]

## score(): static char *reason[]
const reason: Array[String] = [
	"killed",
	"quit",
	"A total winner",
	"killed with Amulet",
]

## killname(): static struct h_list nlist[] as {h_ch, h_desc, h_print}
## (the C table ends with a {'\0'} entry)
const nlist: Array = [
	[ord("a"), "arrow", true],
	[ord("b"), "bolt", true],
	[ord("d"), "dart", true],
	[ord("h"), "hypothermia", false],
	[ord("s"), "starvation", false],
]

## death_monst(): static char poss[]
const poss: Array[int] = [
	ord("A"), ord("B"), ord("C"), ord("D"), ord("E"), ord("F"), ord("G"), ord("H"), ord("I"), ord("J"), ord("K"), ord("L"),
	ord("M"), ord("N"), ord("O"), ord("P"), ord("Q"), ord("R"), ord("S"), ord("T"), ord("U"), ord("V"), ord("W"), ord("X"),
	ord("Y"), ord("Z"), ord("a"), ord("b"), ord("h"), ord("d"), ord("s"),
	ord(" "),	# This is provided to generate the "Wally the Wonder Badger"
				# message for killer
]


## score:
##	Figure score and post it.
static func score(amount: int, flags: int, monst: int) -> void:
	var scp: int		# SCORE *scp: index into top_ten
	var sc2: int		# SCORE *sc2: index into top_ten, -1 for NULL
	var top_ten: Array[Score]	# SCORE *top_ten
	var endp: int		# SCORE *endp = &top_ten[numscores]
	var prflags := 0	# MASTER
	var uid: int		# unsigned int

	MachDep.start_score()

	if flags >= 0 or (MASTER and wizard):
		mvaddstr(LINES - 1, 0, "[Press return to continue]")
		refresh()
		prbuf = await wgetnstr(stdscr, 80)
		endwin()
		printf("\n")
		MachDep.resetltchars()
		# free up space to "guarantee" there is space for the top_ten
		delwin(stdscr)
		delwin(curscr)
		if hw != null:
			delwin(hw)

	# top_ten = (SCORE *) malloc(numscores * sizeof (SCORE))
	top_ten = []
	for k in numscores:
		top_ten.append(Score.new())
	endp = numscores
	scp = 0
	while scp < endp:
		top_ten[scp].sc_score = 0
		top_ten[scp].sc_name = _rnd_name()	# (unsigned char) rnd(255) x MAXSTR
		top_ten[scp].sc_flags = RN()
		top_ten[scp].sc_level = RN()
		top_ten[scp].sc_monster = RN() & 0xFFFF	# (unsigned short) RN
		top_ten[scp].sc_uid = RN()
		scp += 1

	# signal(SIGINT, SIG_DFL): no signals in the port

	if MASTER:
		if wizard:
			if prbuf == "names":
				prflags = 1
			elif prbuf == "edit":
				prflags = 2
	Save.rd_score(top_ten)
	# Insert her in list if need be
	sc2 = -1
	if noscore == 0:
		uid = Mdport.md_getuid() & 0xFFFFFFFF
		scp = 0
		while scp < endp:
			if amount > top_ten[scp].sc_score:
				break
			elif not allscore and flags != 2 \
					and top_ten[scp].sc_uid == uid and top_ten[scp].sc_flags != 2:	# only one score per nowin uid
				scp = endp
			scp += 1
		if scp < endp:
			if flags != 2 and not allscore:
				sc2 = scp
				while sc2 < endp:
					if top_ten[sc2].sc_uid == uid and top_ten[sc2].sc_flags != 2:
						break
					sc2 += 1
				if sc2 >= endp:
					sc2 = endp - 1
			else:
				sc2 = endp - 1
			while sc2 > scp:
				top_ten[sc2].copy_from(top_ten[sc2 - 1])	# *sc2 = sc2[-1]
				sc2 -= 1
			top_ten[scp].sc_score = amount
			top_ten[scp].sc_name = whoami.substr(0, MAXSTR)	# strncpy(scp->sc_name, whoami, MAXSTR)
			top_ten[scp].sc_flags = flags & 0xFFFFFFFF
			if flags == 2:
				top_ten[scp].sc_level = max_level
			else:
				top_ten[scp].sc_level = level
			top_ten[scp].sc_monster = monst & 0xFFFF
			top_ten[scp].sc_uid = uid
			sc2 = scp
	# Print the list
	if flags != -1:
		putchar(ord("\n"))
	printf("Top %s %s:\n", [Numname, "Scores" if allscore else "Rogueists"])
	printf("   Score Name\n")
	scp = 0
	while scp < endp:
		if top_ten[scp].sc_score != 0:
			if sc2 == scp:
				Mdport.md_raw_standout()
			printf("%2d %5d %s: %s on level %d", [scp + 1,
				top_ten[scp].sc_score, top_ten[scp].sc_name, reason[top_ten[scp].sc_flags],
				top_ten[scp].sc_level])
			if top_ten[scp].sc_flags == 0 or top_ten[scp].sc_flags == 3:
				printf(" by %s", [killname(to_schar(top_ten[scp].sc_monster), true)])
			if MASTER:
				if prflags == 1:
					printf(" (%s)", [Mdport.md_getrealname(top_ten[scp].sc_uid)])
				elif prflags == 2:
					# fflush(stdout)
					prbuf = await fgets_stdin(10)
					if cat(prbuf, 0) == ord("d"):
						sc2 = scp
						while sc2 < endp - 1:
							top_ten[sc2].copy_from(top_ten[sc2 + 1])	# *sc2 = *(sc2 + 1)
							sc2 += 1
						sc2 = endp - 1
						top_ten[sc2].sc_score = 0
						top_ten[sc2].sc_name = _rnd_name()	# (char) rnd(255) x MAXSTR
						top_ten[sc2].sc_flags = RN()
						top_ten[sc2].sc_level = RN()
						top_ten[sc2].sc_monster = RN() & 0xFFFF	# (unsigned short) RN
						scp -= 1
				else:
					printf(".")
			else:
				printf(".")
			if sc2 == scp:
				Mdport.md_raw_standend()
			putchar(ord("\n"))
		else:
			break
		scp += 1
	# Update the list file
	if sc2 != -1:
		if await MachDep.lock_sc():
			# fp = signal(SIGINT, SIG_IGN)
			Save.wr_score(top_ten)
			MachDep.unlock_sc()
			# signal(SIGINT, fp)


## for (i = 0; i < MAXSTR; i++) sc_name[i] = (char) rnd(255);
##	The MAXSTR random draws of score(). Returns the C string they spell:
##	the characters before the first NUL (char(0) is not representable).
static func _rnd_name() -> String:
	var name := ""
	var nul := false
	var c: int
	for i in MAXSTR:
		c = rnd(255)
		if c == 0:
			nul = true
		elif not nul:
			name += chr(c)
	return name


## death:
##	Do something really fun when he dies
static func death(monst: int) -> void:
	var dp: int		# char **dp: index into rip
	var killer: String
	var year: int		# 1900 + lt->tm_year

	# signal(SIGINT, SIG_IGN)
	purse -= purse / 10
	# signal(SIGINT, leave)
	clear()
	killer = killname(monst, false)
	if not tombstone:
		mvprintw(LINES - 2, 0, "Killed by ")
		killer = killname(monst, false)
		if monst != ord("s") and monst != ord("h"):
			printw("a%s ", [Misc.vowelstr(killer)])
		printw("%s with %d gold", [killer, purse])
	else:
		# time(&date); lt = localtime(&date): tests pin time() and TZ=UTC
		year = Time.get_datetime_dict_from_unix_time(env_time)["year"]
		move(8, 0)
		dp = 0
		while dp < rip.size():
			addstr(rip[dp])
			dp += 1
		mvaddstr(17, center(killer), killer)
		if monst == ord("s") or monst == ord("h"):
			mvaddch(16, 32, ord(" "))
		else:
			mvaddstr(16, 33, Misc.vowelstr(killer))
		mvaddstr(14, center(whoami), whoami)
		prbuf = sprintf("%d Au", [purse])
		move(15, center(prbuf))
		addstr(prbuf)
		prbuf = sprintf("%4d", [year])
		mvaddstr(18, 26, prbuf)
	move(LINES - 1, 0)
	refresh()
	await score(purse, 3 if amulet else 0, monst)
	printf("[Press return to continue]")
	# fflush(stdout)
	prbuf = await fgets_stdin(10)
	await Main.my_exit(0)
	return


## center:
##	Return the index to center the given string
static func center(str_: String) -> int:
	return 28 - ((str_.length() + 1) / 2)


## total_winner:
##	Code for a winner
static func total_winner() -> void:
	var obj: Thing
	var op: ObjInfo
	var worth := 0
	var oldpurse: int

	clear()
	standout()
	addstr("                                                               \n")
	addstr("  @   @               @   @           @          @@@  @     @  \n")
	addstr("  @   @               @@ @@           @           @   @     @  \n")
	addstr("  @   @  @@@  @   @   @ @ @  @@@   @@@@  @@@      @  @@@    @  \n")
	addstr("   @@@@ @   @ @   @   @   @     @ @   @ @   @     @   @     @  \n")
	addstr("      @ @   @ @   @   @   @  @@@@ @   @ @@@@@     @   @     @  \n")
	addstr("  @   @ @   @ @  @@   @   @ @   @ @   @ @         @   @  @     \n")
	addstr("   @@@   @@@   @@ @   @   @  @@@@  @@@@  @@@     @@@   @@   @  \n")
	addstr("                                                               \n")
	addstr("     Congratulations, you have made it to the light of day!    \n")
	standend()
	addstr("\nYou have joined the elite ranks of those who have escaped the\n")
	addstr("Dungeons of Doom alive.  You journey home and sell all your loot at\n")
	addstr("a great profit and are admitted to the Fighters' Guild.\n")
	mvaddstr(LINES - 1, 0, "--Press space to continue--")
	refresh()
	await Io.wait_for(ord(" "))
	clear()
	mvaddstr(0, 0, "   Worth  Item\n")
	oldpurse = purse
	obj = pack
	while obj != null:
		match obj.o_type:
			FOOD:
				worth = 2 * obj.o_count
			WEAPON:
				worth = weap_info[obj.o_which].oi_worth
				worth *= 3 * (obj.o_hplus + obj.o_dplus) + obj.o_count
				obj.o_flags |= ISKNOW
			ARMOR:
				worth = arm_info[obj.o_which].oi_worth
				worth += (9 - obj.o_arm) * 100
				worth += (10 * (a_class[obj.o_which] - obj.o_arm))
				obj.o_flags |= ISKNOW
			SCROLL:
				worth = scr_info[obj.o_which].oi_worth
				worth *= obj.o_count
				op = scr_info[obj.o_which]
				if not op.oi_know:
					worth /= 2
				op.oi_know = true
			POTION:
				worth = pot_info[obj.o_which].oi_worth
				worth *= obj.o_count
				op = pot_info[obj.o_which]
				if not op.oi_know:
					worth /= 2
				op.oi_know = true
			RING:
				op = ring_info[obj.o_which]
				worth = op.oi_worth
				if obj.o_which == R_ADDSTR or obj.o_which == R_ADDDAM \
						or obj.o_which == R_PROTECT or obj.o_which == R_ADDHIT:
					if obj.o_arm > 0:
						worth += obj.o_arm * 100
					else:
						worth = 10
				if (obj.o_flags & ISKNOW) == 0:
					worth /= 2
				obj.o_flags |= ISKNOW
				op.oi_know = true
			STICK:
				op = ws_info[obj.o_which]
				worth = op.oi_worth
				worth += 20 * obj.o_charges
				if (obj.o_flags & ISKNOW) == 0:
					worth /= 2
				obj.o_flags |= ISKNOW
				op.oi_know = true
			AMULET:
				worth = 1000
		if worth < 0:
			worth = 0
		printw("%c) %5d  %s\n", [obj.o_packch, worth, Things.inv_name(obj, false)])
		purse += worth
		obj = obj.l_next
	printw("   %5d  Gold Pieces          ", [oldpurse])
	refresh()
	await score(purse, 2, ord(" "))
	await Main.my_exit(0)
	return


## killname:
##	Convert a code to a monster name
##	(C returns the static buffer prbuf: the result is also left in prbuf)
static func killname(monst: int, doart: bool) -> String:
	var sp: String
	var article: bool

	if isupper(monst):
		sp = monsters[monst - ord("A")].m_name
		article = true
	else:
		sp = "Wally the Wonder Badger"
		article = false
		for hp: Array in nlist:
			if hp[0] == monst:
				sp = hp[1]
				article = hp[2]
				break
	if doart and article:
		prbuf = sprintf("a%s ", [Misc.vowelstr(sp)])
	else:
		prbuf = ""
	prbuf += sp
	return prbuf


## death_monst:
##	Return a monster appropriate for a random death.
static func death_monst() -> int:
	return poss[rnd(poss.size())]
