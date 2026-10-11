## chase.c: Code for one creature to chase another
##
## @(#)chase.c	4.57 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## Statics (RogueBase): ch_ret -> _chase_ch_ret (where chasing takes you),
## runners' orig_pos -> _runners_orig_pos, do_chase's this -> _do_chase_this,
## chase's tryp -> _chase_tryp, cansee's tp -> _cansee_tp.
## t_dest is a coord pointer (&hero, &obj->o_pos, &rp->r_gold): it is a Coord
## reference here, compared by identity.
class_name Chase
extends RogueBase

const DRAGONSHOT := 5	# one chance in DRAGONSHOT that a dragon will flame


## runners:
##	Make all the running monsters move.
static func runners(_arg: int = 0) -> void:
	var tp: Thing
	var next: Thing
	var wastarget: bool

	tp = mlist
	while tp != null:
		# remember this in case the monster's "next" is changed
		next = tp.l_next
		if not on(tp, ISHELD) and on(tp, ISRUN):
			_runners_orig_pos.copy_from(tp.t_pos)
			wastarget = on(tp, ISTARGET)
			if await move_monst(tp) == -1:
				tp = next
				continue
			if on(tp, ISFLY) and dist_cp(hero, tp.t_pos) >= 3:
				await move_monst(tp)
			if wastarget and not ce(_runners_orig_pos, tp.t_pos):
				tp.t_flags &= ~ISTARGET
				to_death = false
		if fixes and next != null and not _on_mlist(next):
			# FIX N5: a dragon's flame killed the monster that was next:
			# go on with the one now after tp
			next = tp.l_next
		tp = next
	if has_hit:
		await Io.endmsg()
		has_hit = false


## move_monst:
##	Execute a single turn of running for a monster
static func move_monst(tp: Thing) -> int:
	if not on(tp, ISSLOW) or tp.t_turn:
		if await do_chase(tp) == -1:
			return -1
	if on(tp, ISHASTE):
		if await do_chase(tp) == -1:
			return -1
	tp.t_turn = not tp.t_turn	# C: tp->t_turn ^= TRUE
	return 0


## relocate:
##	Make the monster's new location be the specified one, updating
##	all the relevant state.
static func relocate(th: Thing, new_loc: Coord) -> void:
	var oroom: Room

	if not ce(new_loc, th.t_pos):
		mvaddch(th.t_pos.y, th.t_pos.x, th.t_oldch)
		if fixes:	# FIX 3: the room it leaves, so a change of room is seen
			oroom = th.t_room
		th.t_room = roomin(new_loc)
		set_oldch(th, new_loc)
		if not fixes:
			oroom = th.t_room
		INDEX(th.t_pos.y, th.t_pos.x).p_monst = null

		# (oroom was taken after t_room changed: find_dest() is never
		# called here. Kept: docs/FIDELITY.md; fixed by FIX 3)
		if oroom != th.t_room:
			th.t_dest = find_dest(th)
		th.t_pos.copy_from(new_loc)
		INDEX(new_loc.y, new_loc.x).p_monst = th
	move(new_loc.y, new_loc.x)
	if see_monst(th):
		addch(th.t_disguise)
	elif on(player, SEEMONST):
		standout()
		addch(th.t_type)
		standend()


## do_chase:
##	Make one thing chase another.
static func do_chase(th: Thing) -> int:
	var cp: Coord
	var rer: Room	# room of chaser
	var ree: Room	# room of chasee
	var mindist := 32767
	var curdist: int
	var stoprun := false	# TRUE means we are there
	var door: bool
	var obj: Thing

	rer = th.t_room		# Find room of chaser
	if on(th, ISGREED) and rer.r_goldval == 0:
		th.t_dest = hero	# If gold has been taken, run after hero
	if th.t_dest == hero:	# Find room of chasee
		ree = proom
	else:
		ree = roomin(th.t_dest)
	# We don't count doors as inside rooms for this routine
	door = chat(th.t_pos.y, th.t_pos.x) == DOOR
	# If the object of our desire is in a different room,
	# and we are not in a corridor, run to the door nearest to
	# our goal.
	while true:	# C: over:
		if rer != ree:
			for i in rer.r_nexits:
				cp = rer.r_exit[i]
				curdist = dist_cp(th.t_dest, cp)
				if curdist < mindist:
					_do_chase_this.copy_from(cp)
					mindist = curdist
			if door:
				rer = passages[flat(th.t_pos.y, th.t_pos.x) & F_PNUM]
				door = false
				continue	# C: goto over
		else:
			_do_chase_this.copy_from(th.t_dest)
			# For dragons check and see if (a) the hero is on a straight
			# line from it, and (b) that it is within shooting distance,
			# but outside of striking range.
			if th.t_type == ord("D") and (th.t_pos.y == hero.y or th.t_pos.x == hero.x \
					or absi(th.t_pos.y - hero.y) == absi(th.t_pos.x - hero.x)) \
					and dist_cp(th.t_pos, hero) <= BOLT_LENGTH * BOLT_LENGTH \
					and not on(th, ISCANC) and rnd(DRAGONSHOT) == 0:
				delta.y = Misc.sign_(hero.y - th.t_pos.y)
				delta.x = Misc.sign_(hero.x - th.t_pos.x)
				if has_hit:
					await Io.endmsg()
				await Sticks.fire_bolt(th.t_pos, delta, "flame")
				running = false
				count = 0
				quiet = 0
				if to_death and not on(th, ISTARGET):
					to_death = false
					kamikaze = false
				return 0
		break
	# This now contains what we want to run to this time
	# so we run to it.  If we hit it we either want to fight it
	# or stop running
	if not chase(th, _do_chase_this):
		if ce(_do_chase_this, hero):
			return await Fight.attack(th)
		elif ce(_do_chase_this, th.t_dest):
			obj = lvl_obj
			while obj != null:
				if th.t_dest == obj.o_pos:
					lvl_obj = List._detach(lvl_obj, obj)
					th.t_pack = List._attach(th.t_pack, obj)
					INDEX(obj.o_pos.y, obj.o_pos.x).p_ch = \
						PASSAGE if (th.t_room.r_flags & ISGONE) != 0 else FLOOR
					th.t_dest = find_dest(th)
					break
				obj = obj.l_next
			if th.t_type != ord("F"):
				stoprun = true
	else:
		if th.t_type == ord("F"):
			return 0
	relocate(th, _chase_ch_ret)
	# And stop running if need be
	if stoprun and ce(th.t_pos, th.t_dest):
		th.t_flags &= ~ISRUN
	return 0


## set_oldch:
##	Set the oldch character for the monster
static func set_oldch(tp: Thing, cp: Coord) -> void:
	var sch: int

	if ce(tp.t_pos, cp):
		return

	sch = tp.t_oldch
	tp.t_oldch = CCHAR(mvinch(cp.y, cp.x))
	if not on(player, ISBLIND):
		if (sch == FLOOR or tp.t_oldch == FLOOR) \
				and (tp.t_room.r_flags & ISDARK) != 0:
			tp.t_oldch = ord(" ")
		elif dist_cp(cp, hero) <= LAMPDIST and see_floor:
			tp.t_oldch = chat(cp.y, cp.x)


## see_monst:
##	Return TRUE if the hero can see the monster
static func see_monst(mp: Thing) -> bool:
	var y: int
	var x: int

	if on(player, ISBLIND):
		return false
	if on(mp, ISINVIS) and not on(player, CANSEE):
		return false
	y = mp.t_pos.y
	x = mp.t_pos.x
	if dist(y, x, hero.y, hero.x) < LAMPDIST:
		if y != hero.y and x != hero.x \
				and not Io.step_ok(chat(y, hero.x)) and not Io.step_ok(chat(hero.y, x)):
			return false
		return true
	if mp.t_room != proom:
		return false
	return not (mp.t_room.r_flags & ISDARK)


## runto:
##	Set a monster running after the hero.
static func runto(runner: Coord) -> void:
	var tp: Thing

	# If we couldn't find him, something is funny
	if MASTER:
		tp = moat(runner.y, runner.x)
		if tp == null:
			# C: msg(); the NULL dereference below follows (port_nonblocking)
			push_error(sprintf("couldn't find monster in runto at (%d,%d)", [runner.y, runner.x]))
	else:
		tp = moat(runner.y, runner.x)
	# Start the beastie running
	tp.t_flags |= ISRUN
	tp.t_flags &= ~ISHELD
	tp.t_dest = find_dest(tp)


## chase:
##	Find the spot for the chaser(er) to move closer to the
##	chasee(ee).  Returns TRUE if we want to keep on chasing later
##	FALSE if we reach the goal.
static func chase(tp: Thing, ee: Coord) -> bool:
	var obj: Thing
	var curdist: int
	var thisdist: int
	var er: Coord = tp.t_pos
	var ch: int
	var plcnt := 1

	# If the thing is confused, let it move randomly. Invisible
	# Stalkers are slightly confused all of the time, and bats are
	# quite confused all the time
	if (on(tp, ISHUH) and rnd(5) != 0) or (tp.t_type == ord("P") and rnd(5) == 0) \
			or (tp.t_type == ord("B") and rnd(2) == 0):
		# get a valid random move
		_chase_ch_ret.copy_from(Move.rndmove(tp))
		curdist = dist_cp(_chase_ch_ret, ee)
		# Small chance that it will become un-confused
		if rnd(20) == 0:
			tp.t_flags &= ~ISHUH
	# Otherwise, find the empty spot next to the chaser that is
	# closest to the chasee.
	else:
		var ey: int
		var ex: int
		# This will eventually hold where we move to get closer
		# If we can't find an empty spot, we stay where we are.
		curdist = dist_cp(er, ee)
		_chase_ch_ret.copy_from(er)

		ey = er.y + 1
		if ey >= NUMLINES - 1:
			ey = NUMLINES - 2
		ex = er.x + 1
		if ex >= NUMCOLS:
			ex = NUMCOLS - 1

		for x in range(er.x - 1, ex + 1):
			if x < 0:
				continue
			_chase_tryp.x = x
			for y in range(er.y - 1, ey + 1):
				_chase_tryp.y = y
				if not diag_ok(er, _chase_tryp):
					continue
				ch = winat(y, x)
				if Io.step_ok(ch):
					# If it is a scroll, it might be a scare monster scroll
					# so we need to look it up to see what type it is.
					if ch == SCROLL:
						obj = lvl_obj
						while obj != null:
							if y == obj.o_pos.y and x == obj.o_pos.x:
								break
							obj = obj.l_next
						if obj != null and obj.o_which == S_SCARE:
							continue
					# It can also be a Xeroc, which we shouldn't step on
					obj = moat(y, x)
					if obj != null and obj.t_type == ord("X"):
						continue
					# If we didn't find any scrolls at this place or it
					# wasn't a scare scroll, then this place counts
					thisdist = dist(y, x, ee.y, ee.x)
					if thisdist < curdist:
						plcnt = 1
						_chase_ch_ret.copy_from(_chase_tryp)
						curdist = thisdist
					elif thisdist == curdist:
						plcnt += 1	# C: && rnd(++plcnt) == 0
						if rnd(plcnt) == 0:
							_chase_ch_ret.copy_from(_chase_tryp)
							curdist = thisdist
	return curdist != 0 and not ce(_chase_ch_ret, hero)


## roomin:
##	Find what room some coordinates are in. NULL means they aren't
##	in any room.
static func roomin(cp: Coord) -> Room:
	var fp: int

	fp = flat(cp.y, cp.x)
	if (fp & F_PASS) != 0:
		return passages[fp & F_PNUM]

	for rp in rooms:
		if cp.x <= rp.r_pos.x + rp.r_max.x and rp.r_pos.x <= cp.x \
				and cp.y <= rp.r_pos.y + rp.r_max.y and rp.r_pos.y <= cp.y:
			return rp

	# C: msg(); the callers then dereference NULL (port_nonblocking,
	# docs/FIDELITY.md). MASTER: abort() follows the message.
	push_error(sprintf("in some bizarre place (%d, %d)", [cp.y, cp.x]))
	return null


## diag_ok:
##	Check to see if the move is legal if it is diagonal
static func diag_ok(sp: Coord, ep: Coord) -> bool:
	if ep.x < 0 or ep.x >= NUMCOLS or ep.y <= 0 or ep.y >= NUMLINES - 1:
		return false
	if ep.x == sp.x or ep.y == sp.y:
		return true
	return Io.step_ok(chat(ep.y, sp.x)) and Io.step_ok(chat(sp.y, ep.x))


## cansee:
##	Returns true if the hero can see a certain coordinate.
static func cansee(y: int, x: int) -> bool:
	var rer: Room

	if on(player, ISBLIND):
		return false
	if dist(y, x, hero.y, hero.x) < LAMPDIST:
		if (flat(y, x) & F_PASS) != 0:
			if y != hero.y and x != hero.x \
					and not Io.step_ok(chat(y, hero.x)) and not Io.step_ok(chat(hero.y, x)):
				return false
		return true
	# We can only see if the hero in the same room as
	# the coordinate and the room is lit or if it is close.
	_cansee_tp.y = y
	_cansee_tp.x = x
	rer = roomin(_cansee_tp)
	return rer == proom and not (rer.r_flags & ISDARK)


## find_dest:
##	find the proper destination for the monster
##	(the parameter tp is reused as the inner loop variable, as in C)
static func find_dest(tp: Thing) -> Coord:
	var obj: Thing
	var prob: int

	prob = monsters[tp.t_type - ord("A")].m_carry
	if prob <= 0 or tp.t_room == proom or see_monst(tp):
		return hero
	obj = lvl_obj
	while obj != null:
		if obj.o_type == SCROLL and obj.o_which == S_SCARE:
			obj = obj.l_next
			continue
		if roomin(obj.o_pos) == tp.t_room and rnd(100) < prob:
			if fixes:	# FIX 4: a loop variable of its own; tp stays the monster
				var mp := mlist
				while mp != null:
					if mp.t_dest == obj.o_pos:
						break
					mp = mp.l_next
				if mp == null:
					return obj.o_pos
				obj = obj.l_next
				continue
			tp = mlist
			while tp != null:
				if tp.t_dest == obj.o_pos:
					break
				tp = tp.l_next
			if tp == null:
				return obj.o_pos
		obj = obj.l_next
	return hero


## dist:
##	Calculate the "distance" between to points.  Actually,
##	this calculates d^2, not d, but that's good enough for
##	our purposes, since it's only used comparitively.
static func dist(y1: int, x1: int, y2: int, x2: int) -> int:
	return (x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1)


## dist_cp:
##	Call dist() with appropriate arguments for coord pointers
static func dist_cp(c1: Coord, c2: Coord) -> int:
	return dist(c1.y, c1.x, c2.y, c2.x)


## (port, FIX N5) Is the monster still on mlist? (A monster that was killed
## has been detached from it.)
static func _on_mlist(tp: Thing) -> bool:
	var mp := mlist
	while mp != null:
		if mp == tp:
			return true
		mp = mp.l_next
	return false
