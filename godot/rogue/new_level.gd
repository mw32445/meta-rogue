## new_level.c: Dig and draw a new level
##
## @(#)new_level.c	4.38 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## treas_room()'s static coord mp is RogueBase._treas_room_mp.
class_name NewLevel
extends RogueBase

const TREAS_ROOM := 20	# one chance in TREAS_ROOM for a treasure room
const MAXTREAS := 10	# maximum number of treasures in a treasure room
const MINTREAS := 2	# minimum number of treasures in a treasure room
const MAXTRIES := 10	# max number of tries to put down a monster


## new_level:
##	Dig and draw a new level
static func new_level() -> void:
	var tp: Thing
	var sp: Place	# char *sp = &flat(y, x): sp.p_flags
	var i: int

	player.t_flags &= ~ISHELD	# unhold when you go down just in case
	if fixes:	# FIX 26: the hold ends, and with it the flytrap's count
		vf_hit = 0
	if level > max_level:
		max_level = level
	# Clean things off from last level
	for pp in places:
		pp.p_ch = ord(" ")
		pp.p_flags = F_REAL
		pp.p_monst = null
	clear()
	# Free up the monsters on the last level
	tp = mlist
	while tp != null:
		tp.t_pack = List._free_list(tp.t_pack)
		tp = tp.l_next
	mlist = List._free_list(mlist)
	# Throw away stuff left on the previous level (if anything)
	lvl_obj = List._free_list(lvl_obj)
	Rooms.do_rooms()			# Draw rooms
	await Passages.do_passages()		# Draw passages
	no_food += 1
	put_things()			# Place objects (if any)
	# Place the traps
	if rnd(10) < level:
		ntraps = rnd(level / 4) + 1
		if ntraps > MAXTRAPS:
			ntraps = MAXTRAPS
		i = ntraps
		while i != 0:	# while (i--)  (i >= 1 here; its final -1 is never read)
			i -= 1
			# not only wouldn't it be NICE to have traps in mazes
			# (not that we care about being nice), since the trap
			# number is stored where the passage number is, we
			# can't actually do it.
			while true:
				Rooms.find_floor(null, stairs, 0, false)
				if not (chat(stairs.y, stairs.x) != FLOOR):
					break
			sp = INDEX(stairs.y, stairs.x)
			sp.p_flags &= ~F_REAL
			sp.p_flags |= rnd(NTRAPS)
	# Place the staircase down.
	Rooms.find_floor(null, stairs, 0, false)
	INDEX(stairs.y, stairs.x).p_ch = STAIRS
	seenstairs = false

	tp = mlist
	while tp != null:
		tp.t_room = Chase.roomin(tp.t_pos)
		tp = tp.l_next

	Rooms.find_floor(null, hero, 0, true)
	await Rooms.enter_room(hero)
	mvaddch(hero.y, hero.x, PLAYER)
	if on(player, SEEMONST):
		Potions.turn_see(false)
	if on(player, ISHALU):
		Daemons.visuals()


## rnd_room:
##	Pick a room that is really there
static func rnd_room() -> int:
	var rm: int

	while true:
		rm = rnd(MAXROOMS)
		if not ((rooms[rm].r_flags & ISGONE) != 0):
			break
	return rm


## put_things:
##	Put potions and scrolls on this level
static func put_things() -> void:
	var obj: Thing

	# Once you have found the amulet, the only way to get new stuff is
	# go down into the dungeon.
	if amulet and level < max_level:
		return
	# check for treasure rooms, and if so, put it in.
	if rnd(TREAS_ROOM) == 0:
		treas_room()
	# Do MAXOBJ attempts to put things on a level
	for i in MAXOBJ:
		if rnd(100) < 36:
			# Pick a new object and link it in the list
			obj = Things.new_thing()
			lvl_obj = List._attach(lvl_obj, obj)
			# Put it somewhere
			Rooms.find_floor(null, obj.o_pos, 0, false)
			INDEX(obj.o_pos.y, obj.o_pos.x).p_ch = to_schar(obj.o_type)	# (char) obj->o_type
	# If he is really deep in the dungeon and he hasn't found the
	# amulet yet, put it somewhere on the ground
	if level >= AMULETLEVEL and not amulet:
		obj = List.new_item()
		lvl_obj = List._attach(lvl_obj, obj)
		obj.o_hplus = 0
		obj.o_dplus = 0
		obj.o_damage = "0x0"	# strncpy(obj->o_damage,"0x0",sizeof(obj->o_damage))
		obj.o_hurldmg = "0x0"	# strncpy(obj->o_hurldmg,"0x0",sizeof(obj->o_hurldmg))
		obj.o_arm = 11
		obj.o_type = AMULET
		# Put it somewhere
		Rooms.find_floor(null, obj.o_pos, 0, false)
		INDEX(obj.o_pos.y, obj.o_pos.x).p_ch = AMULET


## treas_room:
##	Add a treasure room
static func treas_room() -> void:
	var nm: int
	var tp: Thing
	var rp: Room
	var spots: int
	var num_monst: int
	var mp := _treas_room_mp	# static coord mp

	rp = rooms[rnd_room()]
	spots = (rp.r_max.y - 2) * (rp.r_max.x - 2) - MINTREAS
	if spots > (MAXTREAS - MINTREAS):
		spots = (MAXTREAS - MINTREAS)
	nm = rnd(spots) + MINTREAS
	num_monst = nm
	while nm != 0:	# while (nm--)  (nm >= 2 here; its final -1 is never read)
		nm -= 1
		if not Rooms.find_floor(rp, mp, 2 * MAXTRIES, false) and fixes:
			continue	# FIX N8: no free floor found: no object (C reused the last square)
		tp = Things.new_thing()
		tp.o_pos.copy_from(mp)
		lvl_obj = List._attach(lvl_obj, tp)
		INDEX(mp.y, mp.x).p_ch = to_schar(tp.o_type)	# (char) tp->o_type

	# fill up room with monsters from the next level down

	nm = rnd(spots) + MINTREAS
	if nm < num_monst + 2:
		nm = num_monst + 2
	spots = (rp.r_max.y - 2) * (rp.r_max.x - 2)
	if nm > spots:
		nm = spots
	level += 1
	while nm != 0:	# while (nm--)  (nm >= 4 here; its final -1 is never read)
		nm -= 1
		spots = 0
		if Rooms.find_floor(rp, mp, MAXTRIES, true):
			tp = List.new_item()
			Monsters.new_monster(tp, Monsters.randmonster(false), mp)
			tp.t_flags |= ISMEAN	# no sloughers in THIS room
			Monsters.give_pack(tp)
	level -= 1
