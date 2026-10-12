## sticks.c: Functions to implement the various sticks one might find
## while wandering around the dungeon.
##
## @(#)sticks.c	4.39 (Berkeley) 02/05/99
class_name Sticks
extends RogueBase


## fix_stick:
##	Set up a new stick
static func fix_stick(cur: Thing) -> void:
	if ws_type[cur.o_which] == "staff":
		cur.o_damage = "2x3"
	else:
		cur.o_damage = "1x1"
	cur.o_hurldmg = "1x1"

	match cur.o_which:
		WS_LIGHT:
			cur.o_charges = rnd(10) + 10
		_:
			cur.o_charges = rnd(5) + 3


## do_zap:
##	Perform a zap with a wand
static func do_zap() -> void:
	var obj: Thing
	var tp: Thing
	var y: int
	var x: int
	var name: String
	var monster: int
	var oldch: int
	var bolt := _do_zap_bolt	# static THING bolt

	obj = await Pack.get_item("zap with", STICK)
	if obj == null:
		return
	if obj.o_type != STICK:
		after = false
		await Io.msg("you can't zap with that!")
		return
	if obj.o_charges == 0:
		await Io.msg("nothing happens")
		return
	# the Serpentine Cult: a zap at a snake is asked first
	if cult_member() and not await Skills.cult_allows(Skills.zap_targets(obj)):
		return
	match obj.o_which:
		WS_LIGHT:
			# Reddy Kilowat wand.  Light up the room
			ws_info[WS_LIGHT].oi_know = true
			if proom.r_flags & ISGONE:
				await Io.msg("the corridor glows and then fades")
			else:
				proom.r_flags &= ~ISDARK
				# Light the room and put the player back up
				await Rooms.enter_room(hero)
				await Io.addmsg("the room is lit")
				if not terse:
					await Io.addmsg(" by a shimmering %s light", [Init.pick_color("blue")])
				await Io.endmsg()
		WS_DRAIN:
			# take away 1/2 of hero's hit points, then take it away
			# evenly from the monsters in the room (or next to hero
			# if he is in a passage)
			if pstats.s_hpt < 2:
				await Io.msg("you are too weak to use it")
				return
			else:
				await drain()
		WS_INVIS, WS_POLYMORPH, WS_TELAWAY, WS_TELTO, WS_CANCEL:
			y = hero.y
			x = hero.x
			while Io.step_ok(winat(y, x)):
				y += delta.y
				x += delta.x
			tp = moat(y, x)
			if tp != null:
				monster = tp.t_type
				if monster == ord("F"):
					player.t_flags &= ~ISHELD
					if fixes:	# FIX 26: the hold ends, and with it the flytrap's count
						vf_hit = 0
				match obj.o_which:
					WS_INVIS:
						tp.t_flags |= ISINVIS
						if Chase.cansee(y, x):
							mvaddch(y, x, tp.t_oldch)
					WS_POLYMORPH:
						var pp: Thing

						pp = tp.t_pack
						mlist = List._detach(mlist, tp)
						if Chase.see_monst(tp):
							mvaddch(y, x, chat(y, x))
						oldch = tp.t_oldch
						delta.y = y
						delta.x = x
						monster = to_schar(rnd(26) + ord("A"))
						Monsters.new_monster(tp, monster, delta)
						if Chase.see_monst(tp):
							mvaddch(y, x, monster)
						tp.t_oldch = oldch
						tp.t_pack = pp
						# C: oi_know |= see_monst(tp) (no short-circuit)
						ws_info[WS_POLYMORPH].oi_know = bool(int(ws_info[WS_POLYMORPH].oi_know)
							| int(Chase.see_monst(tp)))
					WS_CANCEL:
						tp.t_flags |= ISCANC
						tp.t_flags &= ~(ISINVIS | CANHUH)
						tp.t_disguise = tp.t_type
						if Chase.see_monst(tp):
							mvaddch(y, x, tp.t_disguise)
					WS_TELAWAY, WS_TELTO:
						var new_pos := Coord.new()

						if obj.o_which == WS_TELAWAY:
							while true:
								Rooms.find_floor(null, new_pos, 0, true)	# limit FALSE
								if not ce(new_pos, hero):
									break
						else:
							new_pos.y = hero.y + delta.y
							new_pos.x = hero.x + delta.x
						tp.t_dest = hero
						tp.t_flags |= ISRUN
						Chase.relocate(tp, new_pos)
		WS_MISSILE:
			ws_info[WS_MISSILE].oi_know = true
			bolt.o_type = ord("*")
			bolt.o_hurldmg = "1x4"
			bolt.o_hplus = 100
			bolt.o_dplus = 1
			bolt.o_flags = ISMISL
			if cur_weapon != null:
				bolt.o_launch = cur_weapon.o_which
			elif fixes:	# FIX D1: no launcher: o_hurldmg (bolt is static: o_launch was stale)
				bolt.o_launch = -1
			Weapons.do_motion(bolt, delta.y, delta.x)
			tp = moat(bolt.o_pos.y, bolt.o_pos.x)
			if tp != null and not Monsters.save_throw(VS_MAGIC, tp):
				await Weapons.hit_monster(bolt.o_pos.y, bolt.o_pos.x, bolt)
			elif terse:
				await Io.msg("missile vanishes" if fixes else "missle vanishes")	# FIX typo
			else:
				await Io.msg("the missile vanishes with a puff of smoke" if fixes	# FIX typo
					else "the missle vanishes with a puff of smoke")
		WS_HASTE_M, WS_SLOW_M:
			y = hero.y
			x = hero.x
			while Io.step_ok(winat(y, x)):
				y += delta.y
				x += delta.x
			tp = moat(y, x)
			if tp != null:
				if obj.o_which == WS_HASTE_M:
					if on(tp, ISSLOW):
						tp.t_flags &= ~ISSLOW
					else:
						tp.t_flags |= ISHASTE
				else:
					if on(tp, ISHASTE):
						tp.t_flags &= ~ISHASTE
					else:
						tp.t_flags |= ISSLOW
					tp.t_turn = true
				delta.y = y
				delta.x = x
				Chase.runto(delta)
		WS_ELECT, WS_FIRE, WS_COLD:
			if obj.o_which == WS_ELECT:
				name = "bolt"
			elif obj.o_which == WS_FIRE:
				name = "flame"
			else:
				name = "ice"
			await fire_bolt(hero, delta, name)
			ws_info[obj.o_which].oi_know = true
		WS_NOP:
			pass
		_:
			if MASTER:
				await Io.msg("what a bizarre schtick!")
	obj.o_charges -= 1


## drain:
##	Do drain hit points from player shtick
static func drain() -> void:
	var mp: Thing
	var corp: Room
	var cnt: int
	var inpass: bool
	# static THING *drainee[40]: filled before it is read on every call, so a
	# local here. C overflows it with 40+ monsters to drain (UB); this does not.
	var drainee: Array[Thing] = []

	# First cnt how many things we need to spread the hit points among
	cnt = 0
	if chat(hero.y, hero.x) == DOOR:
		corp = passages[flat(hero.y, hero.x) & F_PNUM]
	else:
		corp = null
	inpass = (proom.r_flags & ISGONE) != 0
	mp = mlist
	while mp != null:
		if mp.t_room == proom or mp.t_room == corp or \
				(inpass and chat(mp.t_pos.y, mp.t_pos.x) == DOOR and \
				passages[flat(mp.t_pos.y, mp.t_pos.x) & F_PNUM] == proom):
			drainee.append(mp)	# C: *dp++ = mp
		mp = mp.l_next
	cnt = drainee.size()	# C: cnt = (int)(dp - drainee)
	if cnt == 0:
		await Io.msg("you have a tingling feeling")
		return
	# *dp = NULL: the end of drainee
	pstats.s_hpt /= 2
	cnt = pstats.s_hpt / cnt
	# Now zot all of the monsters
	for dp in drainee:
		mp = dp
		mp.t_stats.s_hpt -= cnt
		if mp.t_stats.s_hpt <= 0:
			await Fight.killed(mp, Chase.see_monst(mp))
		else:
			Chase.runto(mp.t_pos)


## fire_bolt:
##	Fire a bolt in a given direction from a specific starting place
static func fire_bolt(start: Coord, dir: Coord, name: String) -> void:
	var c1: int	# coord *c1: an index into spotpos
	var tp: Thing = null
	var dirch := 0
	var ch: int
	var hit_hero: bool
	var used: bool
	var changed: bool
	var pos := _fire_bolt_pos	# static coord pos
	var spotpos := _fire_bolt_spotpos	# static coord spotpos[BOLT_LENGTH]
	# UB: C leaves THING bolt uninitialized (roll_em reads o_flags, o_launch,
	# o_damage). docs/FIDELITY.md: zero-filled with o_launch = -1, so the bolt
	# uses its o_hurldmg "6x6" (the oracle does the same).
	var bolt := Thing.new()
	bolt.o_launch = -1

	bolt.o_type = WEAPON
	bolt.o_which = FLAME
	bolt.o_hurldmg = "6x6"
	bolt.o_hplus = 100
	bolt.o_dplus = 0
	weap_info[FLAME].oi_name = name
	match dir.y + dir.x:
		0:
			dirch = ord("/")
		1, -1:
			dirch = ord("-") if dir.y == 0 else ord("|")
		2, -2:
			dirch = ord("\\")
	pos.copy_from(start)
	hit_hero = start != hero
	used = false
	changed = false
	c1 = 0
	while c1 <= BOLT_LENGTH - 1 and not used:
		pos.y += dir.y
		pos.x += dir.x
		spotpos[c1].copy_from(pos)
		ch = winat(pos.y, pos.x)
		# C: switch (ch); case DOOR can jump to the label "def" on default
		var goto_def := false
		match ch:
			DOOR, 124, 45, 32:	# DOOR '|' '-' ' '
				# this code is necessary if the hero is on a door
				# and he fires at the wall the door is in, it would
				# otherwise loop infinitely
				if ch == DOOR and ce(hero, pos):
					goto_def = true	# C: goto def
				else:
					# (case DOOR falls through to '|', '-' and ' ')
					if not changed:
						hit_hero = not hit_hero
					changed = false
					dir.y = -dir.y
					dir.x = -dir.x
					c1 -= 1
					await Io.msg("the %s bounces", [name])
			_:
				goto_def = true
		if goto_def:
			# def:
			var hit_monst := false	# C: !hit_hero && (tp = moat(...)) != NULL
			if not hit_hero:
				tp = moat(pos.y, pos.x)
				hit_monst = tp != null
			if hit_monst:
				hit_hero = true
				changed = not changed
				tp.t_oldch = chat(pos.y, pos.x)
				if not Monsters.save_throw(VS_MAGIC, tp):
					bolt.o_pos.copy_from(pos)
					used = true
					if tp.t_type == ord("D") and name == "flame":
						await Io.addmsg("the flame bounces")
						if not terse:
							await Io.addmsg(" off the dragon")
						await Io.endmsg()
					else:
						await Weapons.hit_monster(pos.y, pos.x, bolt)
				elif ch != ord("M") or tp.t_disguise == ord("M"):
					if start == hero:
						Chase.runto(pos)
					if terse:
						await Io.msg("%s misses", [name])
					else:
						await Io.msg("the %s whizzes past %s", [name, Fight.set_mname(tp)])
			elif hit_hero and ce(pos, hero):
				hit_hero = false
				changed = not changed
				if not Monsters.save(VS_MAGIC):
					pstats.s_hpt -= roll(6, 6)
					if pstats.s_hpt <= 0:
						if start == hero:
							await Rip.death(ord("b"))
						else:
							await Rip.death(moat(start.y, start.x).t_type)
					used = true
					if terse:
						await Io.msg("the %s hits", [name])
					else:
						await Io.msg("you are hit by the %s", [name])
				else:
					await Io.msg("the %s whizzes by you", [name])
			mvaddch(pos.y, pos.x, dirch)
			refresh()
		c1 += 1
	for c2 in range(0, c1):
		mvaddch(spotpos[c2].y, spotpos[c2].x, chat(spotpos[c2].y, spotpos[c2].x))


## charge_str:
##	Return an appropriate string for a wand charge
static func charge_str(obj: Thing) -> String:
	var buf: String	# static char buf[20]

	if not (obj.o_flags & ISKNOW):
		buf = ""
	elif terse:
		buf = sprintf(" [%d]", [obj.o_charges])
	else:
		buf = sprintf(" [%d charges]", [obj.o_charges])
	return buf
