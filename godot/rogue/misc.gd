## misc.c: All sorts of miscellaneous routines
##
## @(#)misc.c	4.66 (Berkeley) 08/06/83
##
## The persistent static of get_dir() (last_delt) is
## RogueBase._get_dir_last_delt.
class_name Misc
extends RogueBase


## look:
##	A quick glance all around the player
##	(C: #undef DEBUG, so the `static bool done` guard is compiled out.)
static func look(wakeup: bool) -> void:
	var ch: int
	var tp: Thing
	var pp: Place
	var rp: Room
	var ey: int
	var ex: int
	var passcount: int
	var pfl: int
	var fp: Place			# C: char *fp = &pp->p_flags
	var pch: int
	var sy: int
	var sx: int
	var sumhero := 0
	var diffhero := 0

	passcount = 0
	rp = proom
	if not ce(oldpos, hero):
		erase_lamp(oldpos, oldrp)
		oldpos.copy_from(hero)
		oldrp = rp
	ey = hero.y + 1
	ex = hero.x + 1
	sx = hero.x - 1
	sy = hero.y - 1
	if door_stop and not firstmove and running:
		sumhero = hero.y + hero.x
		diffhero = hero.y - hero.x
	pp = INDEX(hero.y, hero.x)
	pch = pp.p_ch
	pfl = pp.p_flags

	for y in range(sy, ey + 1):
		if y > 0 and y < NUMLINES - 1:
			for x in range(sx, ex + 1):
				if x < 0 or x >= NUMCOLS:
					continue
				if not on(player, ISBLIND):
					if y == hero.y and x == hero.x:
						continue

				pp = INDEX(y, x)
				ch = pp.p_ch
				if ch == 32:		# nothing need be done with a ' '
					continue
				fp = pp
				if pch != DOOR and ch != DOOR:
					if (pfl & F_PASS) != (fp.p_flags & F_PASS):
						continue
				if ((fp.p_flags & F_PASS) != 0 or ch == DOOR) and \
						((pfl & F_PASS) != 0 or pch == DOOR):
					if hero.x != x and hero.y != y and \
							not Io.step_ok(chat(y, hero.x)) and not Io.step_ok(chat(hero.y, x)):
						continue

				tp = pp.p_monst
				if tp == null:
					ch = trip_ch(y, x, ch)
				else:
					if on(player, SEEMONST) and on(tp, ISINVIS):
						if door_stop and not firstmove:
							running = false
						continue
					else:
						if wakeup:
							await Monsters.wake_monster(y, x)
						if Chase.see_monst(tp):
							if on(player, ISHALU):
								ch = rnd(26) + ord("A")
							else:
								ch = tp.t_disguise
				if on(player, ISBLIND) and (y != hero.y or x != hero.x):
					continue

				move(y, x)

				if (proom.r_flags & ISDARK) != 0 and not see_floor and ch == FLOOR:
					ch = 32

				if tp != null or ch != CCHAR(inch()):
					addch(ch)

				if door_stop and not firstmove and running:
					match runch:
						ord("h"):
							if x == ex:
								continue
						ord("j"):
							if y == sy:
								continue
						ord("k"):
							if y == ey:
								continue
						ord("l"):
							if x == sx:
								continue
						ord("y"):
							if (y + x) - sumhero >= 1:
								continue
						ord("u"):
							if (y - x) - diffhero >= 1:
								continue
						ord("n"):
							if (y + x) - sumhero <= -1:
								continue
						ord("b"):
							if (y - x) - diffhero <= -1:
								continue
					match ch:
						DOOR:
							if x == hero.x or y == hero.y:
								running = false
						PASSAGE:
							if x == hero.x or y == hero.y:
								passcount += 1
						FLOOR, 124, 45, 32:	# FLOOR '|' '-' ' '
							pass
						_:
							running = false
	if door_stop and not firstmove and passcount > 1:
		running = false
	if not running or not jump:
		mvaddch(hero.y, hero.x, PLAYER)


## trip_ch:
##	Return the character appropriate for this space, taking into
##	account whether or not the player is tripping.
static func trip_ch(y: int, x: int, ch: int) -> int:
	if on(player, ISHALU) and after:
		match ch:
			FLOOR, 32, PASSAGE, 45, 124, DOOR, TRAP:	# FLOOR ' ' PASSAGE '-' '|' DOOR TRAP
				pass
			_:
				if y != stairs.y or x != stairs.x or not seenstairs:
					ch = rnd_thing()
	return ch


## erase_lamp:
##	Erase the area shown by a lamp in a dark room.
static func erase_lamp(pos: Coord, rp: Room) -> void:
	var ey: int
	var sy: int
	var ex: int

	if not (see_floor and (rp.r_flags & (ISGONE | ISDARK)) == ISDARK \
			and not on(player, ISBLIND)):
		return

	ey = pos.y + 1
	ex = pos.x + 1
	sy = pos.y - 1
	for x in range(pos.x - 1, ex + 1):
		for y in range(sy, ey + 1):
			if y == hero.y and x == hero.x:
				continue
			move(y, x)
			if inch() == FLOOR:
				addch(32)


## show_floor:
##	Should we show the floor in her room at this time?
static func show_floor() -> bool:
	if (proom.r_flags & (ISGONE | ISDARK)) == ISDARK and not on(player, ISBLIND):
		return see_floor
	else:
		return true


## find_obj:
##	Find the unclaimed object at y, x
##	(Not a coroutine: the MASTER "Non-object" message reports with
##	push_error, see docs/FIDELITY.md and blocking.json port_nonblocking.)
static func find_obj(y: int, x: int) -> Thing:
	var obj: Thing

	obj = lvl_obj
	while obj != null:
		if obj.o_pos.y == y and obj.o_pos.x == x:
			return obj
		obj = obj.l_next
	if MASTER:
		prbuf = sprintf("Non-object %d,%d", [y, x])
		await Io.msg(prbuf)
		return null
	else:
		# NOTREACHED
		return null


## eat:
##	She wants to eat something, so let her try
static func eat() -> void:
	var obj: Thing

	obj = await Pack.get_item("eat", FOOD)
	if obj == null:
		return
	if obj.o_type != FOOD:
		if not terse:
			await Io.msg("ugh, you would get ill if you ate that")
		else:
			await Io.msg("that's Inedible!")
		return
	if food_left < 0:
		food_left = 0
	food_left += HUNGERTIME - 200 + rnd(400)
	if food_left > STOMACHSIZE:
		food_left = STOMACHSIZE
	hungry_state = 0
	if obj == cur_weapon:
		cur_weapon = null
	if obj.o_which == 1:
		await Io.msg("my, that was a yummy %s", [fruit])
	else:
		if rnd(100) > 70:
			pstats.s_exp += 1
			await Io.msg("%s, this food tastes awful", [choose_str("bummer", "yuk")])
			await check_level()
		else:
			await Io.msg("%s, that tasted good", [choose_str("oh, wow", "yum")])
	Pack.leave_pack(obj, false, false)


## check_level:
##	Check to see if the guy has gone up a level.
static func check_level() -> void:
	var i: int
	var add: int
	var olevel: int

	i = 0
	while e_levels[i] != 0:
		if e_levels[i] > pstats.s_exp:
			break
		i += 1
	i += 1
	olevel = pstats.s_lvl
	pstats.s_lvl = i
	if i > olevel:
		add = roll(i - olevel, 10)
		max_hp += add
		pstats.s_hpt += add
		await Io.msg("welcome to level %d", [i])


## chg_str:
##	used to modify the playes strength.  It keeps track of the
##	highest it has been, just in case
static func chg_str(amt: int) -> void:
	var comp: int			# str_t

	if amt == 0:
		return
	pstats.s_str = add_str(pstats.s_str, amt)
	comp = pstats.s_str
	if ISRING(LEFT, R_ADDSTR):
		comp = add_str(comp, -cur_ring[LEFT].o_arm)
	if ISRING(RIGHT, R_ADDSTR):
		comp = add_str(comp, -cur_ring[RIGHT].o_arm)
	if comp > max_stats.s_str:
		max_stats.s_str = comp


## add_str:
##	Perform the actual add, checking upper and lower bound limits
##	(C: void add_str(str_t *sp, int amt). The port takes *sp and returns
##	its new value: add_str(&x, amt) is x = add_str(x, amt). str_t is
##	unsigned, so *sp + amt wraps modulo 2^32 before the clamp.)
static func add_str(sp: int, amt: int) -> int:
	sp = (sp + amt) & 0xFFFFFFFF	# *sp += amt
	if sp < 3:
		sp = 3
	elif sp > 31:
		sp = 31
	return sp


## add_haste:
##	Add a haste to the player
static func add_haste(potion: bool) -> bool:
	if on(player, ISHASTE):
		no_command += rnd(8)
		player.t_flags &= ~(ISRUN | ISHASTE)
		Daemon.extinguish(D_NOHASTE)
		await Io.msg("you faint from exhaustion")
		return false
	else:
		player.t_flags |= ISHASTE
		if potion:
			Daemon.fuse(D_NOHASTE, 0, rnd(4) + 4, AFTER())
		return true


## aggravate:
##	Aggravate all the monsters on this level
static func aggravate() -> void:
	var mp: Thing

	mp = mlist
	while mp != null:
		Chase.runto(mp.t_pos)
		mp = mp.l_next


## vowelstr:
##	For printfs: if string starts with a vowel, return "n" for an
##	"an".
static func vowelstr(str_: String) -> String:
	match cat(str_, 0):
		ord("a"), ord("A"), \
		ord("e"), ord("E"), \
		ord("i"), ord("I"), \
		ord("o"), ord("O"), \
		ord("u"), ord("U"):
			return "n"
		_:
			return ""


## is_current:
##	See if the object is one of the currently used items
static func is_current(obj: Thing) -> bool:
	if obj == null:
		return false
	if obj == cur_armor or obj == cur_weapon or obj == cur_ring[LEFT] \
			or obj == cur_ring[RIGHT]:
		if not terse:
			await Io.addmsg("That's already ")
		await Io.msg("in use")
		return true
	return false


## get_dir:
##	Set up the direction co_ordinate for use in varios "prefix"
##	commands
static func get_dir() -> bool:
	var prompt: String
	var gotit: bool

	if again and last_dir != 0:
		delta.y = _get_dir_last_delt.y
		delta.x = _get_dir_last_delt.x
		dir_ch = last_dir
	else:
		if not terse:
			prompt = "which direction? "
			await Io.msg(prompt)
		else:
			prompt = "direction: "
		while true:
			gotit = true
			dir_ch = await Io.readchar()
			match dir_ch:
				ord("h"), ord("H"):
					delta.y = 0
					delta.x = -1
				ord("j"), ord("J"):
					delta.y = 1
					delta.x = 0
				ord("k"), ord("K"):
					delta.y = -1
					delta.x = 0
				ord("l"), ord("L"):
					delta.y = 0
					delta.x = 1
				ord("y"), ord("Y"):
					delta.y = -1
					delta.x = -1
				ord("u"), ord("U"):
					delta.y = -1
					delta.x = 1
				ord("b"), ord("B"):
					delta.y = 1
					delta.x = -1
				ord("n"), ord("N"):
					delta.y = 1
					delta.x = 1
				ESCAPE:
					last_dir = 0
					Pack.reset_last()
					return false
				_:
					mpos = 0
					await Io.msg(prompt)
					gotit = false
			if gotit:	# C: until (gotit)
				break
		if isupper(dir_ch):
			dir_ch = to_schar(tolower(dir_ch))
		last_dir = dir_ch
		_get_dir_last_delt.y = delta.y
		_get_dir_last_delt.x = delta.x
	if on(player, ISHUH) and rnd(5) == 0:
		while true:
			delta.y = rnd(3) - 1
			delta.x = rnd(3) - 1
			if not (delta.y == 0 and delta.x == 0):
				break
	mpos = 0
	return true


## sign:
##	Return the sign of the number
##	(sign_ in the port: an unqualified sign() call would reach Godot's built-in.)
static func sign_(nm: int) -> int:
	if nm < 0:
		return -1
	else:
		return int(nm > 0)


## spread:
##	Give a spread around a given number (+/- 20%)
static func spread(nm: int) -> int:
	return nm - nm / 20 + rnd(nm / 10)


## call_it:
##	Call an object something after use.
##	(C passes &pot_info[i] etc.: the ObjInfo itself here.)
static func call_it(info: ObjInfo) -> void:
	if info.oi_know:
		if info.oi_guess != null:
			# free(info->oi_guess);
			info.oi_guess = null
	elif info.oi_guess == null:
		await Io.msg("call it: " if terse else "what do you want to call it? ")
		var r: Array = await Options.get_str(prbuf, stdscr)
		prbuf = r[1]
		if r[0] == NORM:
			# if (info->oi_guess != NULL) free(info->oi_guess);
			# info->oi_guess = malloc(strlen(prbuf) + 1); strcpy(...)
			info.oi_guess = prbuf


## static char thing_list[] (rnd_thing)
const THING_LIST: Array[int] = [
	POTION, SCROLL, RING, STICK, FOOD, WEAPON, ARMOR, STAIRS, GOLD, AMULET,
]


## rnd_thing:
##	Pick a random thing appropriate for this level
static func rnd_thing() -> int:
	var i: int

	if level >= AMULETLEVEL:
		i = rnd(THING_LIST.size())		# sizeof thing_list / sizeof (char)
	else:
		i = rnd(THING_LIST.size() - 1)
	return THING_LIST[i]


## choose_str:
##	Choose the first or second string depending on whether it the
##	player is tripping
static func choose_str(ts: String, ns: String) -> String:
	return (ts if on(player, ISHALU) else ns)
