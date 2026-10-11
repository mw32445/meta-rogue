## monsters.c: File with various monster functions in it
##
## @(#)monsters.c	4.46 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## wanderer()'s static coord cp is RogueBase._wanderer_cp.
class_name Monsters
extends RogueBase

## List of monsters in rough order of vorpalness
const lvl_mons: Array[int] = [
	ord("K"), ord("E"), ord("B"), ord("S"), ord("H"), ord("I"), ord("R"), ord("O"), ord("Z"),
	ord("L"), ord("C"), ord("Q"), ord("A"),
	ord("N"), ord("Y"), ord("F"), ord("T"), ord("W"), ord("P"), ord("X"), ord("U"), ord("M"),
	ord("V"), ord("G"), ord("J"), ord("D"),
]

const wand_mons: Array[int] = [
	ord("K"), ord("E"), ord("B"), ord("S"), ord("H"), 0, ord("R"), ord("O"), ord("Z"),
	0, ord("C"), ord("Q"), ord("A"),
	0, ord("Y"), 0, ord("T"), ord("W"), ord("P"), 0, ord("U"), ord("M"),
	ord("V"), ord("G"), ord("J"), 0,
]


## randmonster:
##	Pick a monster to show up.  The lower the level,
##	the meaner the monster.
static func randmonster(wander: bool) -> int:
	var d: int
	var mons: Array[int]

	mons = wand_mons if wander else lvl_mons
	while true:
		d = level + (rnd(10) - 6)
		if d < 0:
			d = rnd(5)
		if d > 25:
			d = rnd(5) + 21
		if not (mons[d] == 0):
			break
	return mons[d]


## new_monster:
##	Pick a new monster and add it to the list
static func new_monster(tp: Thing, type_: int, cp: Coord) -> void:
	var mp: Monster
	var lev_add: int

	lev_add = level - AMULETLEVEL
	if lev_add < 0:
		lev_add = 0
	mlist = List._attach(mlist, tp)
	tp.t_type = type_
	tp.t_disguise = type_
	tp.t_pos.copy_from(cp)
	move(cp.y, cp.x)
	tp.t_oldch = CCHAR(inch())
	tp.t_room = Chase.roomin(cp)
	INDEX(cp.y, cp.x).p_monst = tp
	mp = monsters[tp.t_type - ord("A")]
	tp.t_stats.s_lvl = mp.m_stats.s_lvl + lev_add
	tp.t_stats.s_hpt = roll(tp.t_stats.s_lvl, 8)
	tp.t_stats.s_maxhp = tp.t_stats.s_hpt
	tp.t_stats.s_arm = mp.m_stats.s_arm - lev_add
	tp.t_stats.s_dmg = mp.m_stats.s_dmg
	tp.t_stats.s_str = mp.m_stats.s_str
	tp.t_stats.s_exp = mp.m_stats.s_exp + lev_add * 10 + exp_add(tp)
	tp.t_flags = mp.m_flags
	if level > 29:
		tp.t_flags |= ISHASTE
	tp.t_turn = true
	tp.t_pack = null
	if ISWEARING(R_AGGR):
		Chase.runto(cp)
	if type_ == ord("X"):
		tp.t_disguise = Misc.rnd_thing()


## expadd:
##	Experience to add for this monster's level/hit points
static func exp_add(tp: Thing) -> int:
	var mod: int

	if tp.t_stats.s_lvl == 1:
		mod = tp.t_stats.s_maxhp / 8
	else:
		mod = tp.t_stats.s_maxhp / 6
	if tp.t_stats.s_lvl > 9:
		mod *= 20
	elif tp.t_stats.s_lvl > 6:
		mod *= 4
	return mod


## wanderer:
##	Create a new wandering monster and aim it at the player
static func wanderer() -> void:
	var tp: Thing

	tp = List.new_item()
	while true:
		Rooms.find_floor(null, _wanderer_cp, false, true)
		if not (Chase.roomin(_wanderer_cp) == proom):
			break
	new_monster(tp, randmonster(true), _wanderer_cp)
	if on(player, SEEMONST):
		standout()
		if not on(player, ISHALU):
			addch(tp.t_type)
		else:
			addch(rnd(26) + ord("A"))
		standend()
	Chase.runto(tp.t_pos)
	if MASTER:
		if wizard:
			await Io.msg("started a wandering %s", [monsters[tp.t_type - ord("A")].m_name])


## wake_monster:
##	What to do when the hero steps next to a monster
static func wake_monster(y: int, x: int) -> Thing:
	var tp: Thing
	var rp: Room
	var ch: int
	var mname: String

	if MASTER:
		tp = moat(y, x)
		if tp == null:
			await Io.msg("can't find monster in wake_monster")
			if fixes:	# FIX N14: nothing to wake (a monster letter is an object)
				return null
			# C dereferences the NULL monster and crashes (docs/FIDELITY.md:
			# exit status 139, as the oracle reports it)
			await exit(139)
			return null
	else:
		tp = moat(y, x)
		if tp == null:
			endwin()	# C: endwin(), abort();
			await abort()
	ch = tp.t_type
	# Every time he sees mean monster, it might start chasing him
	if not on(tp, ISRUN) and rnd(3) != 0 and on(tp, ISMEAN) and not on(tp, ISHELD) \
			and not ISWEARING(R_STEALTH) and not on(player, ISLEVIT):
		tp.t_dest = hero
		tp.t_flags |= ISRUN
	if ch == ord("M") and not on(player, ISBLIND) and not on(player, ISHALU) \
			and not on(tp, ISFOUND) and not on(tp, ISCANC) and on(tp, ISRUN):
		rp = proom
		if (rp != null and not (rp.r_flags & ISDARK)) \
				or Chase.dist(y, x, hero.y, hero.x) < LAMPDIST:
			tp.t_flags |= ISFOUND
			if not save(VS_MAGIC):
				if on(player, ISHUH):
					Daemon.lengthen(D_UNCONFUSE, Misc.spread(HUHDURATION))
				else:
					Daemon.fuse(D_UNCONFUSE, 0, Misc.spread(HUHDURATION), AFTER())
				player.t_flags |= ISHUH
				mname = Fight.set_mname(tp)
				await Io.addmsg("%s", [mname])
				if mname != "it":
					await Io.addmsg("'")
				await Io.msg("s gaze has confused you")
	# Let greedy ones guard gold
	if on(tp, ISGREED) and not on(tp, ISRUN):
		tp.t_flags |= ISRUN
		if proom.r_goldval != 0:
			tp.t_dest = proom.r_gold
		else:
			tp.t_dest = hero
	return tp


## give_pack:
##	Give a pack to a monster if it deserves one
static func give_pack(tp: Thing) -> void:
	if level >= max_level and rnd(100) < monsters[tp.t_type - ord("A")].m_carry:
		tp.t_pack = List._attach(tp.t_pack, Things.new_thing())


## save_throw:
##	See if a creature save against something
static func save_throw(which: int, tp: Thing) -> int:
	var need: int

	need = 14 + which - tp.t_stats.s_lvl / 2
	return int(roll(1, 20) >= need)


## save:
##	See if he saves against various nasty things
static func save(which: int) -> int:
	if which == VS_MAGIC:
		if ISRING(LEFT, R_PROTECT):
			which -= cur_ring[LEFT].o_arm
		if ISRING(RIGHT, R_PROTECT):
			which -= cur_ring[RIGHT].o_arm
	return save_throw(which, player)
