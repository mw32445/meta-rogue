## weapons.c: Functions for dealing with problems brought about by weapons
##
## @(#)weapons.c	4.34 (Berkeley) 02/05/99
##
## The global "group" lives in RogueBase. fall()'s static fpos and
## hit_monster()'s static mp are RogueBase._fall_fpos and _hit_monster_mp.
class_name Weapons
extends RogueBase

const NO_WEAPON := -1

## static struct init_weaps {
##	char *iw_dam;	/* Damage when wielded */
##	char *iw_hrl;	/* Damage when thrown */
##	char iw_launch;	/* Launching weapon */
##	int iw_flags;	/* Miscellaneous flags */
## } init_dam[MAXWEAPONS]
const init_dam: Array[Dictionary] = [
	{"iw_dam": "2x4", "iw_hrl": "1x3", "iw_launch": NO_WEAPON, "iw_flags": 0},	# Mace
	{"iw_dam": "3x4", "iw_hrl": "1x2", "iw_launch": NO_WEAPON, "iw_flags": 0},	# Long sword
	{"iw_dam": "1x1", "iw_hrl": "1x1", "iw_launch": NO_WEAPON, "iw_flags": 0},	# Bow
	{"iw_dam": "1x1", "iw_hrl": "2x3", "iw_launch": BOW, "iw_flags": ISMANY | ISMISL},	# Arrow
	{"iw_dam": "1x6", "iw_hrl": "1x4", "iw_launch": NO_WEAPON, "iw_flags": ISMISL | ISMISL},	# Dagger
	{"iw_dam": "4x4", "iw_hrl": "1x2", "iw_launch": NO_WEAPON, "iw_flags": 0},	# 2h sword
	{"iw_dam": "1x1", "iw_hrl": "1x3", "iw_launch": NO_WEAPON, "iw_flags": ISMANY | ISMISL},	# Dart
	{"iw_dam": "1x2", "iw_hrl": "2x4", "iw_launch": NO_WEAPON, "iw_flags": ISMANY | ISMISL},	# Shuriken
	{"iw_dam": "2x3", "iw_hrl": "1x6", "iw_launch": NO_WEAPON, "iw_flags": ISMISL},	# Spear
]


## missile:
##	Fire a missile in a given direction
static func missile(ydelta: int, xdelta: int) -> void:
	var obj: Thing

	# Get which thing we are hurling
	obj = await Pack.get_item("throw", WEAPON)
	if obj == null:
		return
	if not await Things.dropcheck(obj) or await Misc.is_current(obj):
		return
	obj = Pack.leave_pack(obj, true, false)
	do_motion(obj, ydelta, xdelta)
	# AHA! Here it has hit something.  If it is a wall or a door,
	# or if it misses (combat) the monster, put it on the floor
	if moat(obj.o_pos.y, obj.o_pos.x) == null or \
			not await hit_monster(obj.o_pos.y, obj.o_pos.x, obj):
		await fall(obj, true)


## do_motion:
##	Do the actual motion on the screen done by an object traveling
##	across the room
static func do_motion(obj: Thing, ydelta: int, xdelta: int) -> void:
	var ch: int

	# Come fly with us ...
	obj.o_pos.copy_from(hero)
	while true:
		# Erase the old one
		if not ce(obj.o_pos, hero) and Chase.cansee(obj.o_pos.y, obj.o_pos.x) and not terse:
			ch = chat(obj.o_pos.y, obj.o_pos.x)
			if ch == FLOOR and not Misc.show_floor():
				ch = ord(" ")
			mvaddch(obj.o_pos.y, obj.o_pos.x, ch)
		# Get the new position
		obj.o_pos.y += ydelta
		obj.o_pos.x += xdelta
		ch = winat(obj.o_pos.y, obj.o_pos.x)
		if Io.step_ok(ch) and ch != DOOR:
			# It hasn't hit anything yet, so display it
			# If it alright.
			if Chase.cansee(obj.o_pos.y, obj.o_pos.x) and not terse:
				mvaddch(obj.o_pos.y, obj.o_pos.x, obj.o_type)
				refresh()
			continue
		break


## fall:
##	Drop an item someplace around here.
static func fall(obj: Thing, pr: bool) -> void:
	var pp: Place

	if fallpos(obj.o_pos, _fall_fpos):
		pp = INDEX(_fall_fpos.y, _fall_fpos.x)
		pp.p_ch = obj.o_type
		obj.o_pos.copy_from(_fall_fpos)
		if Chase.cansee(_fall_fpos.y, _fall_fpos.x):
			if pp.p_monst != null:
				pp.p_monst.t_oldch = obj.o_type
			else:
				mvaddch(_fall_fpos.y, _fall_fpos.x, obj.o_type)
		lvl_obj = List._attach(lvl_obj, obj)
		return
	if pr:
		if has_hit:
			await Io.endmsg()
			has_hit = false
		await Io.msg("the %s vanishes as it hits the ground",
			[_weap_info_name(obj.o_which)])
	List.discard(obj)


## weap_info[which].oi_name for fall()'s message.
## UB: missile() throws any pack object, so a potion, scroll, ring or stick
## whose o_which is past the end of weap_info[] (MAXWEAPONS + 1 entries) can
## get here. C then reads the next array in memory; in the std/master oracle
## builds (gcc -O2)
## scr_info[] follows weap_info[], so weap_info[MAXWEAPONS + 1 + k] is
## scr_info[k] (o_which <= 17 stays inside scr_info). docs/requests/C.md
static func _weap_info_name(which: int) -> Variant:
	if which >= 0 and which < weap_info.size():
		return weap_info[which].oi_name
	if which >= weap_info.size() and which - weap_info.size() < scr_info.size():
		return scr_info[which - weap_info.size()].oi_name
	push_error("fall: weap_info[%d] is out of range" % which)
	return null


## init_weapon:
##	Set up the initial goodies for a weapon
static func init_weapon(weap: Thing, which: int) -> void:
	var iwp: Dictionary

	weap.o_type = WEAPON
	weap.o_which = which
	# UB: the wizard's create_obj() can pass a which past the table; C then
	# reads past init_dam[] (the port reports an index error).
	iwp = init_dam[which]
	weap.o_damage = iwp.iw_dam
	weap.o_hurldmg = iwp.iw_hrl
	weap.o_launch = iwp.iw_launch
	weap.o_flags = iwp.iw_flags
	weap.o_hplus = 0
	weap.o_dplus = 0
	if which == DAGGER:
		weap.o_count = rnd(4) + 2
		weap.o_group = group
		group += 1
	elif (weap.o_flags & ISMANY) != 0:
		weap.o_count = rnd(8) + 8
		weap.o_group = group
		group += 1
	else:
		weap.o_count = 1
		weap.o_group = 0


## hit_monster:
##	Does the missile hit the monster?
static func hit_monster(y: int, x: int, obj: Thing) -> int:
	_hit_monster_mp.y = y
	_hit_monster_mp.x = x
	return await Fight.fight(_hit_monster_mp, obj, true)


## num:
##	Figure out the plus number for armor/weapons
static func num(n1: int, n2: int, type_: int) -> String:
	var numbuf: String	# static char numbuf[10]: rewritten on every call

	numbuf = sprintf("%d" if n1 < 0 else "+%d", [n1])
	if type_ == WEAPON:
		numbuf += sprintf(",%d" if n2 < 0 else ",+%d", [n2])
	return numbuf


## wield:
##	Pull out a certain weapon
static func wield() -> void:
	var obj: Thing
	var oweapon: Thing
	var sp: String

	oweapon = cur_weapon
	if not await Things.dropcheck(cur_weapon):
		cur_weapon = oweapon
		return
	cur_weapon = oweapon
	obj = await Pack.get_item("wield", WEAPON)
	if obj == null:
		# bad:
		after = false
		return

	if obj.o_type == ARMOR:
		await Io.msg("you can't wield armor")
		# C: goto bad
		after = false
		return
	if await Misc.is_current(obj):
		# C: goto bad
		after = false
		return

	sp = Things.inv_name(obj, true)
	cur_weapon = obj
	if not terse:
		await Io.addmsg("you are now ")
	await Io.msg("wielding %s (%c)", [sp, obj.o_packch])


## fallpos:
##	Pick a random position around the give (y, x) coordinates
static func fallpos(pos: Coord, newpos: Coord) -> bool:
	var y: int
	var x: int
	var cnt: int
	var ch: int

	cnt = 0
	y = pos.y - 1
	while y <= pos.y + 1:
		x = pos.x - 1
		while x <= pos.x + 1:
			# check to make certain the spot is empty, if it is,
			# put the object there, set it in the level list
			# and re-draw the room if he can see it
			if y == hero.y and x == hero.x:
				x += 1
				continue
			ch = chat(y, x)
			if ch == FLOOR or ch == PASSAGE:
				cnt += 1
				if rnd(cnt) == 0:
					newpos.y = y
					newpos.x = x
			x += 1
		y += 1
	return cnt != 0
