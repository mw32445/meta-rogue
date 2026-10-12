## potions.c: Function(s) for dealing with potions
##
## @(#)potions.c	4.46 (Berkeley) 06/07/83
class_name Potions
extends RogueBase

## typedef struct {
##	int pa_flags;
##	void (*pa_daemon)();
##	int pa_time;
##	char *pa_high, *pa_straight;
## } PACT;
##
## pa_daemon is a daemon function id (D_*; &"" for NULL). In C the
## P_SEEINVIS entry's pa_high and pa_straight point at the global prbuf,
## which quaff() writes just before do_pot() reads them: they hold the
## marker PA_PRBUF here and are dereferenced at use time (_pa_str).
const PA_PRBUF := &"&prbuf"

const p_actions: Array[Dictionary] = [
	{"pa_flags": ISHUH, "pa_daemon": D_UNCONFUSE, "pa_time": HUHDURATION,	# P_CONFUSE
		"pa_high": "what a tripy feeling!",
		"pa_straight": "wait, what's going on here. Huh? What? Who?"},
	{"pa_flags": ISHALU, "pa_daemon": D_COME_DOWN, "pa_time": SEEDURATION,	# P_LSD
		"pa_high": "Oh, wow!  Everything seems so cosmic!",
		"pa_straight": "Oh, wow!  Everything seems so cosmic!"},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_POISON
		"pa_high": null, "pa_straight": null},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_STRENGTH
		"pa_high": null, "pa_straight": null},
	{"pa_flags": CANSEE, "pa_daemon": D_UNSEE, "pa_time": SEEDURATION,	# P_SEEINVIS
		"pa_high": PA_PRBUF,
		"pa_straight": PA_PRBUF},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_HEALING
		"pa_high": null, "pa_straight": null},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_MFIND
		"pa_high": null, "pa_straight": null},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_TFIND
		"pa_high": null, "pa_straight": null},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_RAISE
		"pa_high": null, "pa_straight": null},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_XHEAL
		"pa_high": null, "pa_straight": null},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_HASTE
		"pa_high": null, "pa_straight": null},
	{"pa_flags": 0, "pa_daemon": &"", "pa_time": 0,	# P_RESTORE
		"pa_high": null, "pa_straight": null},
	{"pa_flags": ISBLIND, "pa_daemon": D_SIGHT, "pa_time": SEEDURATION,	# P_BLIND
		"pa_high": "oh, bummer!  Everything is dark!  Help!",
		"pa_straight": "a cloak of darkness falls around you"},
	{"pa_flags": ISLEVIT, "pa_daemon": D_LAND, "pa_time": HEALTIME,	# P_LEVIT
		"pa_high": "oh, wow!  You're floating in the air!",
		"pa_straight": "you start to float in the air"},
]


## quaff:
##	Quaff a potion from the pack
static func quaff() -> void:
	var obj: Thing
	var tp: Thing
	var mp: Thing
	var discardit := false
	var show: bool
	var trip: bool

	obj = await Pack.get_item("quaff", POTION)
	# Make certain that it is somethings that we want to drink
	if obj == null:
		return
	if obj.o_type != POTION:
		if not terse:
			await Io.msg("yuk! Why would you want to drink that?")
		else:
			await Io.msg("that's undrinkable")
		return
	if obj == cur_weapon:
		cur_weapon = null

	# Calculate the effect it has on the poor guy.
	trip = on(player, ISHALU)
	discardit = obj.o_count == 1
	Pack.leave_pack(obj, false, false)
	match obj.o_which:
		P_CONFUSE:
			await do_pot(P_CONFUSE, not trip)
		P_POISON:
			pot_info[P_POISON].oi_know = true
			if ISWEARING(R_SUSTSTR):
				await Io.msg("you feel momentarily sick")
			else:
				Misc.chg_str(-(rnd(3) + 1))
				await Io.msg("you feel very sick now")
				await Daemons.come_down()
		P_HEALING:
			pot_info[P_HEALING].oi_know = true
			pstats.s_hpt += roll(pstats.s_lvl, 4)
			if pstats.s_hpt > max_hp:
				max_hp += 1
				pstats.s_hpt = max_hp
			await Daemons.sight()
			await Io.msg("you begin to feel better")
		P_STRENGTH:
			pot_info[P_STRENGTH].oi_know = true
			Misc.chg_str(1)
			await Io.msg("you feel stronger, now.  What bulging muscles!")
		P_MFIND:
			player.t_flags |= SEEMONST
			if fixes and Daemon.find_slot(D_TURN_SEE) != null:
				# FIX 30: lengthen the fuse already burning, as other potions
				# do, instead of filling the 20 daemon slots
				Daemon.lengthen(D_TURN_SEE, HUHDURATION)
			else:
				Daemon.fuse(D_TURN_SEE, 1, HUHDURATION, AFTER())	# C: fuse((void(*)())turn_see, TRUE, ...)
			if not turn_see(false):
				await Io.msg("you have a %s feeling for a moment, then it passes",
					[Misc.choose_str("normal", "strange")])
		P_TFIND:
			# Potion of magic detection.  Show the potions and scrolls
			show = false
			if lvl_obj != null:
				wclear(hw)
				tp = lvl_obj
				while tp != null:
					if is_magic(tp):
						show = true
						wmove(hw, tp.o_pos.y, tp.o_pos.x)
						waddch(hw, MAGIC)
						pot_info[P_TFIND].oi_know = true
					tp = tp.l_next
				mp = mlist
				while mp != null:
					tp = mp.t_pack
					while tp != null:
						if is_magic(tp):
							show = true
							wmove(hw, mp.t_pos.y, mp.t_pos.x)
							waddch(hw, MAGIC)
						tp = tp.l_next
					mp = mp.l_next
			if show:
				pot_info[P_TFIND].oi_know = true
				await Io.show_win("You sense the presence of magic on this level.--More--")
			else:
				await Io.msg("you have a %s feeling for a moment, then it passes",
					[Misc.choose_str("normal", "strange")])
		P_LSD:
			if not trip:
				if on(player, SEEMONST):
					turn_see(false)
				Daemon.start_daemon(D_VISUALS, 0, BEFORE())
				seenstairs = seen_stairs()
			await do_pot(P_LSD, true)
		P_SEEINVIS:
			prbuf = sprintf("this potion tastes like %s juice", [fruit])
			show = on(player, CANSEE)
			await do_pot(P_SEEINVIS, false)
			if not show:
				invis_on()
			await Daemons.sight()
		P_RAISE:
			pot_info[P_RAISE].oi_know = true
			await Io.msg("you suddenly feel much more skillful")
			await raise_level()
		P_XHEAL:
			pot_info[P_XHEAL].oi_know = true
			pstats.s_hpt += roll(pstats.s_lvl, 8)
			if pstats.s_hpt > max_hp:
				if pstats.s_hpt > max_hp + pstats.s_lvl + 1:
					max_hp += 1
				max_hp += 1
				pstats.s_hpt = max_hp
			await Daemons.sight()
			await Daemons.come_down()
			await Io.msg("you begin to feel much better")
		P_HASTE:
			pot_info[P_HASTE].oi_know = true
			after = false
			if await Misc.add_haste(true):
				await Io.msg("you feel yourself moving much faster")
		P_RESTORE:
			if ISRING(LEFT, R_ADDSTR):
				pstats.s_str = Misc.add_str(pstats.s_str, -cur_ring[LEFT].o_arm)
			if ISRING(RIGHT, R_ADDSTR):
				pstats.s_str = Misc.add_str(pstats.s_str, -cur_ring[RIGHT].o_arm)
			if pstats.s_str < max_stats.s_str:
				pstats.s_str = max_stats.s_str
			if ISRING(LEFT, R_ADDSTR):
				pstats.s_str = Misc.add_str(pstats.s_str, cur_ring[LEFT].o_arm)
			if ISRING(RIGHT, R_ADDSTR):
				pstats.s_str = Misc.add_str(pstats.s_str, cur_ring[RIGHT].o_arm)
			if fixes:	# FIX typo
				await Io.msg("hey, this tastes great.  It makes you feel warm all over")
			else:
				await Io.msg("hey, this tastes great.  It make you feel warm all over")
		P_BLIND:
			await do_pot(P_BLIND, true)
		P_LEVIT:
			await do_pot(P_LEVIT, true)
		_:
			if MASTER:
				await Io.msg("what an odd tasting potion!")
				return
	await Io.status()
	# Throw the item away

	await Misc.call_it(pot_info[obj.o_which])

	if discardit:
		List.discard(obj)
	return


## is_magic:
##	Returns true if an object radiates magic
static func is_magic(obj: Thing) -> bool:
	match obj.o_type:
		ARMOR:
			return (obj.o_flags & ISPROT) != 0 or obj.o_arm != a_class[obj.o_which]
		WEAPON:
			return obj.o_hplus != 0 or obj.o_dplus != 0
		POTION, SCROLL, STICK, RING, AMULET:
			return true
	return false


## invis_on:
##	Turn on the ability to see invisible
static func invis_on() -> void:
	var mp: Thing

	player.t_flags |= CANSEE
	mp = mlist
	while mp != null:
		if on(mp, ISINVIS) and Chase.see_monst(mp) and not on(player, ISHALU):
			mvaddch(mp.t_pos.y, mp.t_pos.x, mp.t_disguise)
		mp = mp.l_next


## turn_see:
##	Put on or off seeing monsters on this level
static func turn_see(turn_off: bool) -> bool:
	var mp: Thing
	var can_see: bool
	var add_new: bool

	add_new = false
	mp = mlist
	while mp != null:
		move(mp.t_pos.y, mp.t_pos.x)
		can_see = Chase.see_monst(mp)
		if turn_off:
			if not can_see:
				addch(mp.t_oldch)
		else:
			if not can_see:
				standout()
			if not on(player, ISHALU):
				addch(mp.t_type)
			else:
				addch(rnd(26) + ord("A"))
			if not can_see:
				standend()
				add_new = true	# C: add_new++
		mp = mp.l_next
	if turn_off:
		player.t_flags &= ~SEEMONST
	else:
		player.t_flags |= SEEMONST
	return add_new


## seen_stairs:
##	Return TRUE if the player has seen the stairs
static func seen_stairs() -> bool:
	var tp: Thing

	move(stairs.y, stairs.x)
	if inch() == STAIRS:	# it's on the map (full chtype, as in C)
		return true
	if ce(hero, stairs):	# It's under him
		return true

	# if a monster is on the stairs, this gets hairy
	tp = moat(stairs.y, stairs.x)
	if tp != null:
		if Chase.see_monst(tp) and on(tp, ISRUN):	# if it's visible and awake
			return true	# it must have moved there

		# if she can detect monster and there once were stairs
		if on(player, SEEMONST) and tp.t_oldch == STAIRS:
			return true	# it must have moved there
	return false


## raise_level:
##	The guy just magically went up a level.
static func raise_level() -> void:
	if fixes and e_levels[pstats.s_lvl - 1] == 0:
		return	# FIX 14: the top level (21): there is none above (C dropped to 1)
	pstats.s_exp = e_levels[pstats.s_lvl - 1] + 1
	await Misc.check_level()


## do_pot:
##	Do a potion with standard setup.  This means it uses a fuse and
##	turns on a flag
static func do_pot(type_: int, knowit: bool) -> void:
	var pp: Dictionary
	var t: int

	pp = p_actions[type_]
	if not pot_info[type_].oi_know:
		pot_info[type_].oi_know = knowit
	t = Misc.spread(pp["pa_time"])
	if not on(player, pp["pa_flags"]):
		player.t_flags |= pp["pa_flags"]
		Daemon.fuse(pp["pa_daemon"], 0, t, AFTER())
		await Misc.look(false)
	else:
		Daemon.lengthen(pp["pa_daemon"], t)
	if fixes:	# FIX 28: text (the fruit, for P_SEEINVIS), not a format
		await Io.msg("%s", [Misc.choose_str(_pa_str(pp["pa_high"]), _pa_str(pp["pa_straight"]))])
	else:
		await Io.msg(Misc.choose_str(_pa_str(pp["pa_high"]), _pa_str(pp["pa_straight"])))


## (port) Read a PACT pa_high / pa_straight char *: the PA_PRBUF entries
## point at the global prbuf, whose current contents C reads here.
static func _pa_str(s: Variant) -> Variant:
	if s is StringName:
		return prbuf
	if fixes and s == "what a tripy feeling!":	# FIX typo (p_actions[P_CONFUSE])
		return "what a trippy feeling!"
	return s
