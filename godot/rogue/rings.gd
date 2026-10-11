## rings.c: Routines dealing specifically with rings
##
## @(#)rings.c	4.19 (Berkeley) 05/29/83
class_name Rings
extends RogueBase

## ring_eat()'s static int uses[]: food used per ring type
const uses: Array[int] = [
	1,	# R_PROTECT
	1,	# R_ADDSTR
	1,	# R_SUSTSTR
	-3,	# R_SEARCH
	-5,	# R_SEEINVIS
	0,	# R_NOP
	0,	# R_AGGR
	-3,	# R_ADDHIT
	-3,	# R_ADDDAM
	2,	# R_REGEN
	-2,	# R_DIGEST
	0,	# R_TELEPORT
	1,	# R_STEALTH
	1,	# R_SUSTARM
]


## ring_on:
##	Put a ring on a hand
static func ring_on() -> void:
	var obj: Thing
	var ring: int

	obj = await Pack.get_item("put on", RING)
	# Make certain that it is somethings that we want to wear
	if obj == null:
		return
	if obj.o_type != RING:
		if not terse:
			await Io.msg("it would be difficult to wrap that around a finger")
		else:
			await Io.msg("not a ring")
		return

	# find out which hand to put it on
	if await Misc.is_current(obj):
		return

	if cur_ring[LEFT] == null and cur_ring[RIGHT] == null:
		ring = await gethand()
		if ring < 0:
			return
	elif cur_ring[LEFT] == null:
		ring = LEFT
	elif cur_ring[RIGHT] == null:
		ring = RIGHT
	else:
		if not terse:
			await Io.msg("you already have a ring on each hand")
		else:
			await Io.msg("wearing two")
		return
	cur_ring[ring] = obj

	# Calculate the effect it has on the poor guy.
	match obj.o_which:
		R_ADDSTR:
			Misc.chg_str(obj.o_arm)
		R_SEEINVIS:
			Potions.invis_on()
		R_AGGR:
			Misc.aggravate()

	if not terse:
		await Io.addmsg("you are now wearing ")
	var nm: String = await Things.inv_name(obj, true)
	await Io.msg("%s (%c)", [nm, obj.o_packch])


## ring_off:
##	take off a ring
static func ring_off() -> void:
	var ring: int
	var obj: Thing

	if cur_ring[LEFT] == null and cur_ring[RIGHT] == null:
		if terse:
			await Io.msg("no rings")
		else:
			await Io.msg("you aren't wearing any rings")
		return
	elif cur_ring[LEFT] == null:
		ring = RIGHT
	elif cur_ring[RIGHT] == null:
		ring = LEFT
	else:
		ring = await gethand()
		if ring < 0:
			return
	mpos = 0
	obj = cur_ring[ring]
	if obj == null:
		await Io.msg("not wearing such a ring")
		return
	if await Things.dropcheck(obj):
		var nm: String = await Things.inv_name(obj, true)
		if fixes:	# FIX 10: a space before the pack letter
			await Io.msg("was wearing %s (%c)", [nm, obj.o_packch])
		else:
			await Io.msg("was wearing %s(%c)", [nm, obj.o_packch])


## gethand:
##	Which hand is the hero interested in?
static func gethand() -> int:
	var c: int

	while true:
		if terse:
			await Io.msg("left or right ring? ")
		else:
			await Io.msg("left hand or right hand? ")
		c = await Io.readchar()
		if c == ESCAPE:
			return -1
		mpos = 0
		if c == ord("l") or c == ord("L"):
			return LEFT
		elif c == ord("r") or c == ord("R"):
			return RIGHT
		if terse:
			await Io.msg("L or R")
		else:
			await Io.msg("please type L or R")
	return -1	# not reached (for (;;))


## ring_eat:
##	How much food does this ring use up?
static func ring_eat(hand: int) -> int:
	var ring: Thing
	var eat: int

	ring = cur_ring[hand]
	if ring == null:
		return 0
	eat = uses[ring.o_which]
	if eat < 0:
		eat = int(rnd(-eat) == 0)
	if ring.o_which == R_DIGEST:
		eat = -eat
	return eat


## ring_num:
##	Print ring bonuses
static func ring_num(obj: Thing) -> String:
	var buf: String	# static char buf[10]: rewritten on every call

	if (obj.o_flags & ISKNOW) == 0:
		return ""
	match obj.o_which:
		R_PROTECT, R_ADDSTR, R_ADDDAM, R_ADDHIT:
			buf = sprintf(" [%s]", [Weapons.num(obj.o_arm, 0, RING)])
		_:
			return ""
	return buf
