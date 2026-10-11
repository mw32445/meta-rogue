## move.c: hero movement commands
##
## @(#)move.c	4.49 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## The global `coord nh` (used to hold the new hero position) is
## RogueBase.nh; rndmove()'s static coord ret is RogueBase._rndmove_ret.
class_name Move
extends RogueBase


## do_run:
##	Start the hero running
static func do_run(ch: int) -> void:
	running = true
	after = false
	runch = ch


## do_move:
##	Check to see that a move is legal.  If it is handle the
## consequences (fighting, picking up, etc.)
static func do_move(dy: int, dx: int) -> void:
	var ch: int
	var fl: int
	var goto_over := false		# C: goto over (jumps into the else branch)
	var goto_hit_bound: bool	# C: goto hit_bound
	var goto_move_stuff: bool	# C: goto move_stuff

	firstmove = false
	if no_move != 0:
		no_move -= 1
		await Io.msg("you are still stuck in the bear trap")
		return
	while true:
		# Do a confused move (maybe)
		if not goto_over and on(player, ISHUH) and rnd(5) != 0:
			nh.copy_from(rndmove(player))
			if ce(nh, hero):
				after = false
				running = false
				to_death = false
				return
		else:
			# C: over:
			nh.y = hero.y + dy
			nh.x = hero.x + dx

		# Check if he tried to move off the screen or make an illegal
		# diagonal move, and stop him if he did.
		goto_hit_bound = false
		if nh.x < 0 or nh.x >= NUMCOLS or nh.y <= 0 or nh.y >= NUMLINES - 1:
			goto_hit_bound = true	# C: goto hit_bound
		else:
			if not Chase.diag_ok(hero, nh):
				after = false
				running = false
				return
			if running and ce(hero, nh):
				running = false	# C: after = running = FALSE
				after = false
			fl = flat(nh.y, nh.x)
			ch = winat(nh.y, nh.x)
			if not (fl & F_REAL) and ch == FLOOR:
				if not on(player, ISLEVIT):
					ch = TRAP	# C: chat(nh.y, nh.x) = ch = TRAP
					INDEX(nh.y, nh.x).p_ch = ch
					INDEX(nh.y, nh.x).p_flags |= F_REAL
			elif on(player, ISHELD) and ch != ord("F"):
				await Io.msg("you are being held")
				return
		# switch (ch): case ' ', '|', '-' (and the hit_bound label in it)
		if goto_hit_bound or ch == ord(" ") or ch == ord("|") or ch == ord("-"):
			# C: hit_bound:
			if passgo and running and (proom.r_flags & ISGONE) != 0 \
					and not on(player, ISBLIND):
				var b1: bool
				var b2: bool

				match runch:
					ord("h"), ord("l"):
						b1 = hero.y != 1 and turn_ok(hero.y - 1, hero.x)
						b2 = hero.y != NUMLINES - 2 and turn_ok(hero.y + 1, hero.x)
						if b1 != b2:	# C: if (!(b1 ^ b2)) break;
							if b1:
								runch = ord("k")
								dy = -1
							else:
								runch = ord("j")
								dy = 1
							dx = 0
							turnref()
							goto_over = true
							continue	# C: goto over
					ord("j"), ord("k"):
						b1 = hero.x != 0 and turn_ok(hero.y, hero.x - 1)
						b2 = hero.x != NUMCOLS - 1 and turn_ok(hero.y, hero.x + 1)
						if b1 != b2:	# C: if (!(b1 ^ b2)) break;
							if b1:
								runch = ord("h")
								dx = -1
							else:
								runch = ord("l")
								dx = 1
							dy = 0
							turnref()
							goto_over = true
							continue	# C: goto over
			running = false
			after = false
			return	# C: break (end of the switch)
		goto_move_stuff = false
		match ch:
			DOOR:
				running = false
				if (flat(hero.y, hero.x) & F_PASS) != 0:
					await Rooms.enter_room(nh)
				goto_move_stuff = true	# C: goto move_stuff
			TRAP:
				ch = await be_trapped(nh)
				if ch == T_DOOR or ch == T_TELEP:
					return
				goto_move_stuff = true	# C: goto move_stuff
			PASSAGE:
				# when you're in a corridor, you don't know if you're in
				# a maze room or not, and there ain't no way to find out
				# if you're leaving a maze room, so it is necessary to
				# always recalculate proom.
				proom = Chase.roomin(hero)
				goto_move_stuff = true	# C: goto move_stuff
			FLOOR:
				if not (fl & F_REAL):
					await be_trapped(hero)
				goto_move_stuff = true	# C: goto move_stuff
			_:
				# C: case STAIRS: seenstairs = TRUE; falls through into default
				if ch == STAIRS:
					seenstairs = true
				running = false
				if isupper(ch) or moat(nh.y, nh.x) != null:
					await Fight.fight(nh, cur_weapon, false)
				else:
					if ch != STAIRS:
						take = ch
					goto_move_stuff = true	# (move_stuff: follows here in C)
		if goto_move_stuff:
			# C: move_stuff:
			mvaddch(hero.y, hero.x, Pack.floor_at())
			if (fl & F_PASS) != 0 and chat(oldpos.y, oldpos.x) == DOOR:
				await Rooms.leave_room(nh)
			hero.copy_from(nh)
		return


## turn_ok:
##	Decide whether it is legal to turn onto the given space
static func turn_ok(y: int, x: int) -> bool:
	var pp: Place

	pp = INDEX(y, x)
	return pp.p_ch == DOOR \
		or (pp.p_flags & (F_REAL | F_PASS)) == (F_REAL | F_PASS)


## turnref:
##	Decide whether to refresh at a passage turning or not
static func turnref() -> void:
	var pp: Place

	pp = INDEX(hero.y, hero.x)
	if not (pp.p_flags & F_SEEN):
		if jump:
			leaveok(stdscr, true)
			refresh()
			leaveok(stdscr, false)
		pp.p_flags |= F_SEEN


## door_open:
##	Called to illuminate a room.  If it is dark, remove anything
##	that might move.
static func door_open(rp: Room) -> void:
	var y: int
	var x: int

	if not (rp.r_flags & ISGONE):
		y = rp.r_pos.y
		while y < rp.r_pos.y + rp.r_max.y:
			x = rp.r_pos.x
			while x < rp.r_pos.x + rp.r_max.x:
				if isupper(winat(y, x)):
					await Monsters.wake_monster(y, x)
				x += 1
			y += 1


## be_trapped:
##	The guy stepped on a trap.... Make him pay.
static func be_trapped(tc: Coord) -> int:
	var pp: Place
	var arrow: Thing
	var tr: int

	if on(player, ISLEVIT):
		return T_RUST	# anything that's not a door or teleport
	running = false
	count = 0	# C: count = FALSE
	pp = INDEX(tc.y, tc.x)
	pp.p_ch = TRAP
	tr = pp.p_flags & F_TMASK
	pp.p_flags |= F_SEEN
	match tr:
		T_DOOR:
			level += 1
			await NewLevel.new_level()
			await Io.msg("you fell into a trap!")
		T_BEAR:
			no_move += BEARTIME()
			await Io.msg("you are caught in a bear trap")
		T_MYST:
			match rnd(11):
				0: await Io.msg("you are suddenly in a parallel dimension")
				1: await Io.msg("the light in here suddenly seems %s", [Init.rainbow[rnd(Init.cNCOLORS)]])
				2: await Io.msg("you feel a sting in the side of your neck")
				3: await Io.msg("multi-colored lines swirl around you, then fade")
				4: await Io.msg("a %s light flashes in your eyes", [Init.rainbow[rnd(Init.cNCOLORS)]])
				5: await Io.msg("a spike shoots past your ear!")
				6: await Io.msg("%s sparks dance across your armor", [Init.rainbow[rnd(Init.cNCOLORS)]])
				7: await Io.msg("you suddenly feel very thirsty")
				8: await Io.msg("you feel time speed up suddenly")
				9: await Io.msg("time now seems to be going slower")
				10: await Io.msg("you pack turns %s!", [Init.rainbow[rnd(Init.cNCOLORS)]])
		T_SLEEP:
			no_command += SLEEPTIME()
			player.t_flags &= ~ISRUN
			await Io.msg("a strange white mist envelops you and you fall asleep")
		T_ARROW:
			if Fight.swing(pstats.s_lvl - 1, pstats.s_arm, 1):
				pstats.s_hpt -= roll(1, 6)
				if pstats.s_hpt <= 0:
					await Io.msg("an arrow killed you")
					await Rip.death(ord("a"))
				else:
					await Io.msg("oh no! An arrow shot you")
			else:
				arrow = List.new_item()
				Weapons.init_weapon(arrow, ARROW)
				arrow.o_count = 1
				arrow.o_pos.copy_from(hero)
				await Weapons.fall(arrow, false)
				await Io.msg("an arrow shoots past you")
		T_TELEP:
			# since the hero's leaving, look() won't put a TRAP
			# down for us, so we have to do it ourself
			await Wizard.teleport()
			mvaddch(tc.y, tc.x, TRAP)
		T_DART:
			if not Fight.swing(pstats.s_lvl + 1, pstats.s_arm, 1):
				await Io.msg("a small dart whizzes by your ear and vanishes")
			else:
				pstats.s_hpt -= roll(1, 4)
				if pstats.s_hpt <= 0:
					await Io.msg("a poisoned dart killed you")
					await Rip.death(ord("d"))
				if not ISWEARING(R_SUSTSTR) and not Monsters.save(VS_POISON):
					Misc.chg_str(-1)
				await Io.msg("a small dart just hit you in the shoulder")
		T_RUST:
			await Io.msg("a gush of water hits you on the head")
			await rust_armor(cur_armor)
	MachDep.flush_type()
	return tr


## rndmove:
##	Move in a random direction if the monster/person is confused
static func rndmove(who: Thing) -> Coord:
	var obj: Thing
	var x: int
	var y: int
	var ch: int
	var bad := false	# C: goto bad

	_rndmove_ret.y = who.t_pos.y + rnd(3) - 1
	y = _rndmove_ret.y
	_rndmove_ret.x = who.t_pos.x + rnd(3) - 1
	x = _rndmove_ret.x
	# Now check to see if that's a legal move.  If not, don't move.
	# (I.e., bump into the wall or whatever)
	if y == who.t_pos.y and x == who.t_pos.x:
		return _rndmove_ret
	if not Chase.diag_ok(who.t_pos, _rndmove_ret):
		bad = true	# C: goto bad
	else:
		ch = winat(y, x)
		if not Io.step_ok(ch):
			bad = true	# C: goto bad
		elif ch == SCROLL:
			obj = lvl_obj
			while obj != null:
				if y == obj.o_pos.y and x == obj.o_pos.x:
					break
				obj = obj.l_next
			if obj != null and obj.o_which == S_SCARE:
				bad = true	# C: goto bad
	if not bad:
		return _rndmove_ret

	# C: bad:
	_rndmove_ret.copy_from(who.t_pos)
	return _rndmove_ret


## rust_armor:
##	Rust the given armor, if it is a legal kind to rust, and we
##	aren't wearing a magic ring.
static func rust_armor(arm: Thing) -> void:
	if arm == null or arm.o_type != ARMOR or arm.o_which == LEATHER \
			or arm.o_arm >= 9:
		return

	if (arm.o_flags & ISPROT) != 0 or ISWEARING(R_SUSTARM):
		if not to_death:
			await Io.msg("the rust vanishes instantly")
	else:
		arm.o_arm += 1
		if not terse:
			await Io.msg("your armor appears to be weaker now. Oh my!")
		else:
			await Io.msg("your armor weakens")
