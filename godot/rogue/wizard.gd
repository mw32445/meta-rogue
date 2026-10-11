## wizard.c: Special wizard commands (some of which are also non-wizard commands
## under strange circumstances)
##
## @(#)wizard.c	4.30 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
class_name Wizard
extends RogueBase

## type_name(): static struct h_list tlist[] as {h_ch, h_desc, h_print}
## (the C table has no terminating {'\0'} entry)
const tlist: Array = [
	[POTION, "potion", false],
	[SCROLL, "scroll", false],
	[FOOD, "food", false],
	[R_OR_S, "ring, wand or staff", false],
	[RING, "ring", false],
	[STICK, "wand or staff", false],
	[WEAPON, "weapon", false],
	[ARMOR, "suit of armor", false],
]


## whatis:
##	What a certin object is
static func whatis(insist: bool, type_: int) -> void:
	var obj: Thing

	if pack == null:
		await Io.msg("you don't have anything in your pack to identify")
		return

	while true:
		obj = await Pack.get_item("identify", type_)
		if insist:
			if n_objs == 0:
				return
			elif obj == null:
				await Io.msg("you must identify something")
			elif type_ != 0 and obj.o_type != type_ \
					and not (type_ == R_OR_S and (obj.o_type == RING or obj.o_type == STICK)):
				await Io.msg("you must identify a %s", [type_name(type_)])
			else:
				break
		else:
			break

	if obj == null:
		return

	match obj.o_type:
		SCROLL:
			set_know(obj, scr_info)
		POTION:
			set_know(obj, pot_info)
		STICK:
			set_know(obj, ws_info)
		WEAPON, ARMOR:
			obj.o_flags |= ISKNOW
		RING:
			set_know(obj, ring_info)
	await Io.msg(Things.inv_name(obj, false))


## set_know:
##	Set things up when we really know what a thing is
static func set_know(obj: Thing, info: Array[ObjInfo]) -> void:
	info[obj.o_which].oi_know = true
	obj.o_flags |= ISKNOW
	# guess = &info[obj->o_which].oi_guess
	if info[obj.o_which].oi_guess != null:
		# free(*guess)
		info[obj.o_which].oi_guess = null


## type_name:
##	Return a pointer to the name of the type
##	(callers only pass types that are in the table)
static func type_name(type_: int) -> Variant:
	for hp: Array in tlist:
		if type_ == hp[0]:
			return hp[1]
	# NOTREACHED (C would read past the end of tlist)
	return null


## create_obj:
##	wizard command for getting anything he wants (MASTER only)
static func create_obj() -> void:
	var obj: Thing
	var ch: int
	var bless: int
	var r: Array

	obj = List.new_item()
	await Io.msg("type of item: ")
	obj.o_type = await Io.readchar()
	mpos = 0
	await Io.msg("which %c do you want? (0-f)", [obj.o_type])
	ch = await Io.readchar()
	# UB: a key outside 0-9a-f gives an o_which past the end of the tables
	obj.o_which = (ch - ord("0") if isdigit(ch) else ch - ord("a") + 10)
	obj.o_group = 0
	obj.o_count = 1
	mpos = 0
	if obj.o_type == WEAPON or obj.o_type == ARMOR:
		await Io.msg("blessing? (+,-,n)")
		bless = await Io.readchar()
		mpos = 0
		if bless == ord("-"):
			obj.o_flags |= ISCURSED
		if obj.o_type == WEAPON:
			Weapons.init_weapon(obj, obj.o_which)
			if bless == ord("-"):
				obj.o_hplus -= rnd(3) + 1
			if bless == ord("+"):
				obj.o_hplus += rnd(3) + 1
		else:
			obj.o_arm = a_class[obj.o_which]
			if bless == ord("-"):
				obj.o_arm += rnd(3) + 1
			if bless == ord("+"):
				obj.o_arm -= rnd(3) + 1
	elif obj.o_type == RING:
		match obj.o_which:
			R_PROTECT, R_ADDSTR, R_ADDHIT, R_ADDDAM:
				await Io.msg("blessing? (+,-,n)")
				bless = await Io.readchar()
				mpos = 0
				if bless == ord("-"):
					obj.o_flags |= ISCURSED
				obj.o_arm = (-1 if bless == ord("-") else rnd(2) + 1)
			R_AGGR, R_TELEPORT:
				obj.o_flags |= ISCURSED
	elif obj.o_type == STICK:
		Sticks.fix_stick(obj)
	elif obj.o_type == GOLD:
		await Io.msg("how much?")
		r = await Options.get_num(obj.o_goldval, stdscr)	# get_num(&obj->o_goldval, stdscr)
		obj.o_goldval = r[1]
	await Pack.add_pack(obj, false)


## teleport:
##	Bamf the hero someplace else
static func teleport() -> void:
	var c := Coord.new()	# static coord c: find_floor() sets it before every use

	mvaddch(hero.y, hero.x, Pack.floor_at())
	Rooms.find_floor(null, c, 0, true)	# limit FALSE
	if Chase.roomin(c) != proom:
		await Rooms.leave_room(hero)
		hero.copy_from(c)
		await Rooms.enter_room(hero)
	else:
		hero.copy_from(c)
		await Misc.look(true)
	mvaddch(hero.y, hero.x, PLAYER)
	# turn off ISHELD in case teleportation was done while fighting
	# a Flytrap
	if on(player, ISHELD):
		player.t_flags &= ~ISHELD
		vf_hit = 0
		monsters[ord("F") - ord("A")].m_stats.s_dmg = "000x0"
	no_move = 0
	count = 0
	running = false
	MachDep.flush_type()


## passwd:
##	See if user knows password (MASTER only)
##	Any password is accepted: md_crypt() returns PASSWD (FIDELITY.md).
static func passwd() -> int:
	var sp: int		# char *sp: index into buf
	var c: int
	var buf := PackedByteArray()	# static char buf[MAXSTR]: [buf, sp) is written before it is read
	var key := ""

	await Io.msg("wizard's Password:")
	mpos = 0
	sp = 0
	while true:
		c = await Io.readchar()
		if c == ord("\n") or c == ord("\r") or c == ESCAPE:
			break
		if c == Mdport.md_killchar():
			sp = 0
		elif c == Mdport.md_erasechar() and sp > 0:
			sp -= 1
		else:
			buf.resize(sp + 1)	# *sp++ = c
			buf[sp] = c & 0xFF
			sp += 1
	if sp == 0:
		return 0	# FALSE
	# *sp = '\0': the C string in buf
	buf.resize(sp)
	for b in buf:
		if b == 0:
			break
		key += chr(b)
	return int(PASSWD == Mdport.md_crypt(key, "mT"))


## show_map:
##	Print out the map for the wizard (MASTER only)
static func show_map() -> void:
	var real: int

	wclear(hw)
	for y in range(1, NUMLINES - 1):
		for x in range(NUMCOLS):
			real = flat(y, x)
			if (real & F_REAL) == 0:
				wstandout(hw)
			wmove(hw, y, x)
			waddch(hw, chat(y, x))
			if real == 0:
				wstandend(hw)
	await Io.show_win("---More (level map)---")
