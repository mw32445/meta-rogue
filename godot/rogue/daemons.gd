## daemons.c: All the daemon and fuse functions are in here
##
## @(#)daemons.c	4.24 (Berkeley) 02/05/99
##
## Every function here is a daemon/fuse target: it takes the one int argument
## that Daemon._call() passes (d_arg), which the C functions ignore.
class_name Daemons
extends RogueBase


## doctor:
##	A healing daemon that restors hit points after rest
static func doctor(_arg: int = 0) -> void:
	var lv: int
	var ohp: int

	lv = pstats.s_lvl
	ohp = pstats.s_hpt
	quiet += 1
	if lv < 8:
		if quiet + (lv << 1) > 20:
			pstats.s_hpt += 1
	else:
		if quiet >= 3:
			pstats.s_hpt += rnd(lv - 7) + 1
	if ISRING(LEFT, R_REGEN):
		pstats.s_hpt += 1
	if ISRING(RIGHT, R_REGEN):
		pstats.s_hpt += 1
	if ohp != pstats.s_hpt:
		if pstats.s_hpt > max_hp:
			pstats.s_hpt = max_hp
		quiet = 0


## Swander:
##	Called when it is time to start rolling for wandering monsters
static func swander(_arg: int = 0) -> void:
	Daemon.start_daemon(D_ROLLWAND, 0, BEFORE())


## rollwand:
##	Called to roll to see if a wandering monster starts up
##	(int between = 0 is RogueBase.between)
static func rollwand(_arg: int = 0) -> void:
	between += 1
	if between >= 4:
		if roll(1, 6) == 4:
			await Monsters.wanderer()
			Daemon.kill_daemon(D_ROLLWAND)
			Daemon.fuse(D_SWANDER, 0, WANDERTIME(), BEFORE())
		between = 0


## unconfuse:
##	Release the poor player from his confusion
static func unconfuse(_arg: int = 0) -> void:
	player.t_flags &= ~ISHUH
	await Io.msg("you feel less %s now", [Misc.choose_str("trippy", "confused")])


## unsee:
##	Turn off the ability to see invisible
static func unsee(_arg: int = 0) -> void:
	var th: Thing

	th = mlist
	while th != null:
		if on(th, ISINVIS) and Chase.see_monst(th):
			mvaddch(th.t_pos.y, th.t_pos.x, th.t_oldch)
		th = th.l_next
	player.t_flags &= ~CANSEE


## sight:
##	He gets his sight back
static func sight(_arg: int = 0) -> void:
	if on(player, ISBLIND):
		Daemon.extinguish(D_SIGHT)
		player.t_flags &= ~ISBLIND
		if not (proom.r_flags & ISGONE):
			await Rooms.enter_room(hero)
		await Io.msg(Misc.choose_str("far out!  Everything is all cosmic again",
			"the veil of darkness lifts"))


## nohaste:
##	End the hasting
static func nohaste(_arg: int = 0) -> void:
	player.t_flags &= ~ISHASTE
	await Io.msg("you feel yourself slowing down")


## stomach:
##	Digest the hero's food
static func stomach(_arg: int = 0) -> void:
	var oldfood: int
	var orig_hungry := hungry_state
	var starved: bool
	var ring_l: int
	var ring_r: int

	if food_left <= 0:
		# C: if (food_left-- < -STARVETIME): compare, decrement, then death()
		starved = food_left < -STARVETIME
		food_left -= 1
		if starved:
			await Rip.death(ord("s"))
		# the hero is fainting
		if no_command != 0 or rnd(5) != 0:
			return
		no_command += rnd(8) + 4
		hungry_state = 3
		if not terse:
			await Io.addmsg(Misc.choose_str("the munchies overpower your motor capabilities.  ",
				"you feel too weak from lack of food.  "))
		await Io.msg(Misc.choose_str("You freak out", "You faint"))
	else:
		oldfood = food_left
		# C: ring_eat(LEFT) + ring_eat(RIGHT) is unsequenced; LEFT first, then
		# RIGHT, as stock gcc does (docs/AUDIT.md; the oracle pins the same)
		ring_l = Rings.ring_eat(LEFT)
		ring_r = Rings.ring_eat(RIGHT)
		food_left -= ring_l + ring_r + 1 - int(amulet)

		if food_left < MORETIME and oldfood >= MORETIME:
			hungry_state = 2
			await Io.msg(Misc.choose_str("the munchies are interfering with your motor capabilites",
				"you are starting to feel weak"))
		elif food_left < 2 * MORETIME and oldfood >= 2 * MORETIME:
			hungry_state = 1
			if terse:
				await Io.msg(Misc.choose_str("getting the munchies", "getting hungry"))
			else:
				await Io.msg(Misc.choose_str("you are getting the munchies",
					"you are starting to get hungry"))
	if hungry_state != orig_hungry:
		player.t_flags &= ~ISRUN
		running = false
		to_death = false
		count = 0


## come_down:
##	Take the hero down off her acid trip.
static func come_down(_arg: int = 0) -> void:
	var tp: Thing
	var seemonst: bool

	if not on(player, ISHALU):
		return

	Daemon.kill_daemon(D_VISUALS)
	player.t_flags &= ~ISHALU

	if on(player, ISBLIND):
		return

	# undo the things
	tp = lvl_obj
	while tp != null:
		if Chase.cansee(tp.o_pos.y, tp.o_pos.x):
			mvaddch(tp.o_pos.y, tp.o_pos.x, tp.o_type)
		tp = tp.l_next

	# undo the monsters
	seemonst = on(player, SEEMONST)
	tp = mlist
	while tp != null:
		move(tp.t_pos.y, tp.t_pos.x)
		if Chase.cansee(tp.t_pos.y, tp.t_pos.x):
			if not on(tp, ISINVIS) or on(player, CANSEE):
				addch(tp.t_disguise)
			else:
				addch(chat(tp.t_pos.y, tp.t_pos.x))
		elif seemonst:
			standout()
			addch(tp.t_type)
			standend()
		tp = tp.l_next
	await Io.msg("Everything looks SO boring now.")


## visuals:
##	change the characters for the player
static func visuals(_arg: int = 0) -> void:
	var tp: Thing
	var seemonst: bool

	if not after or (running and jump):
		return
	# change the things
	tp = lvl_obj
	while tp != null:
		if Chase.cansee(tp.o_pos.y, tp.o_pos.x):
			mvaddch(tp.o_pos.y, tp.o_pos.x, Misc.rnd_thing())
		tp = tp.l_next

	# change the stairs
	if not seenstairs and Chase.cansee(stairs.y, stairs.x):
		mvaddch(stairs.y, stairs.x, Misc.rnd_thing())

	# change the monsters
	seemonst = on(player, SEEMONST)
	tp = mlist
	while tp != null:
		move(tp.t_pos.y, tp.t_pos.x)
		if Chase.see_monst(tp):
			if tp.t_type == ord("X") and tp.t_disguise != ord("X"):
				addch(Misc.rnd_thing())
			else:
				addch(rnd(26) + ord("A"))
		elif seemonst:
			standout()
			addch(rnd(26) + ord("A"))
			standend()
		tp = tp.l_next


## land:
##	Land from a levitation potion
static func land(_arg: int = 0) -> void:
	player.t_flags &= ~ISLEVIT
	await Io.msg(Misc.choose_str("bummer!  You've hit the ground",
		"you float gently to the ground"))
