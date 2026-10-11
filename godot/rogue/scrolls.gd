## scrolls.c: Read a scroll and let it happen
##
## @(#)scrolls.c	4.44 (Berkeley) 02/05/99
class_name Scrolls
extends RogueBase


## read_scroll:
##	Read a scroll from the pack and do the appropriate thing
static func read_scroll() -> void:
	var obj: Thing
	var pp: Place
	var ch: int
	var i: int
	var discardit := false
	var cur_room: Room
	var orig_obj: Thing
	var mp := _read_scroll_mp	# static coord mp
	# int y, x: the loop variables of the for loops below

	obj = await Pack.get_item("read", SCROLL)
	if obj == null:
		return
	if obj.o_type != SCROLL:
		if not terse:
			await Io.msg("there is nothing on it to read")
		else:
			await Io.msg("nothing to read")
		return
	# Calculate the effect it has on the poor guy.
	if obj == cur_weapon:
		cur_weapon = null
	# Get rid of the thing
	discardit = obj.o_count == 1
	Pack.leave_pack(obj, false, false)
	orig_obj = obj

	match obj.o_which:
		S_CONFUSE:
			# Scroll of monster confusion.  Give him that power.
			player.t_flags |= CANHUH
			await Io.msg("your hands begin to glow %s", [Init.pick_color("red")])
		S_ARMOR:
			if cur_armor != null:
				cur_armor.o_arm -= 1
				cur_armor.o_flags &= ~ISCURSED
				await Io.msg("your armor glows %s for a moment", [Init.pick_color("silver")])
		S_HOLD:
			# Hold monster scroll.  Stop all monsters within two spaces
			# from chasing after the hero.
			ch = 0
			for x in range(hero.x - 2, hero.x + 2 + 1):
				if x >= 0 and x < NUMCOLS:
					for y in range(hero.y - 2, hero.y + 2 + 1):
						if y >= 0 and y <= NUMLINES - 1:
							obj = moat(y, x)
							if obj != null and on(obj, ISRUN):
								obj.t_flags &= ~ISRUN
								obj.t_flags |= ISHELD
								ch += 1
			if ch != 0:
				await Io.addmsg("the monster")
				if ch > 1:
					await Io.addmsg("s around you")
				await Io.addmsg(" freeze")
				if ch == 1:
					await Io.addmsg("s")
				await Io.endmsg()
				scr_info[S_HOLD].oi_know = true
			else:
				await Io.msg("you feel a strange sense of loss")
		S_SLEEP:
			# Scroll which makes you fall asleep
			scr_info[S_SLEEP].oi_know = true
			no_command += rnd(SLEEPTIME()) + 4
			player.t_flags &= ~ISRUN
			await Io.msg("you fall asleep")
		S_CREATE:
			# Create a monster:
			# First look in a circle around him, next try his room
			# otherwise give up
			i = 0
			for y in range(hero.y - 1, hero.y + 1 + 1):
				for x in range(hero.x - 1, hero.x + 1 + 1):
					# Don't put a monster in top of the player.
					if y == hero.y and x == hero.x:
						continue
					# FIX 12: nor on a monster (winat() gives a xeroc's disguise)
					if fixes and moat(y, x) != null:
						continue
					# Or anything else nasty
					ch = winat(y, x)
					if Io.step_ok(ch):
						if ch == SCROLL:
							var sobj: Thing = await Misc.find_obj(y, x)
							if sobj == null:
								if not fixes:
									# UB: a xeroc disguised as a scroll leaves no object
									# here; C dereferences find_obj()'s NULL and crashes
									# (docs/FIDELITY.md: exit status 139, as the oracle).
									await exit(139)
									return
							elif sobj.o_which == S_SCARE:
								continue
						i += 1
						if rnd(i) == 0:
							mp.y = y
							mp.x = x
			if i == 0:
				await Io.msg("you hear a faint cry of anguish in the distance")
			else:
				obj = List.new_item()
				Monsters.new_monster(obj, Monsters.randmonster(false), mp)
		S_ID_POTION, S_ID_SCROLL, S_ID_WEAPON, S_ID_ARMOR, S_ID_R_OR_S:
			const id_type: Array[int] = [0, 0, 0, 0, 0, POTION, SCROLL, WEAPON, ARMOR, R_OR_S]
			# Identify, let him figure something out
			scr_info[obj.o_which].oi_know = true
			await Io.msg("this scroll is an %s scroll", [scr_info[obj.o_which].oi_name])
			await Wizard.whatis(true, id_type[obj.o_which])
		S_MAP:
			# Scroll of magic mapping.
			scr_info[S_MAP].oi_know = true
			await Io.msg("oh, now this scroll has a map on it")
			# take all the things we want to keep hidden out of the window
			for y in range(1, NUMLINES - 1):
				for x in range(0, NUMCOLS):
					pp = INDEX(y, x)
					# C: switch (ch = pp->p_ch) whose cases jump to the labels
					# "def" (on default) and "pass" (on case PASSAGE)
					var label := ""
					ch = pp.p_ch
					match ch:
						DOOR, STAIRS:
							pass

						45, 124:	# '-' '|'
							if not (pp.p_flags & F_REAL):
								pp.p_ch = DOOR
								ch = DOOR
								pp.p_flags |= F_REAL

						32:	# ' '
							if pp.p_flags & F_REAL:
								label = "def"	# C: goto def
							else:
								pp.p_flags |= F_REAL
								pp.p_ch = PASSAGE
								ch = PASSAGE
								label = "pass"	# FALLTHROUGH (into case PASSAGE)

						PASSAGE:
							label = "pass"

						FLOOR:
							if pp.p_flags & F_REAL:
								ch = ord(" ")
							else:
								ch = TRAP
								pp.p_ch = TRAP
								pp.p_flags |= (F_SEEN | F_REAL)

						_:
							label = "def"
					if label == "def":
						# def:
						if pp.p_flags & F_PASS:
							label = "pass"	# C: goto pass
						else:
							ch = ord(" ")
					if label == "pass":
						# pass:
						if not (pp.p_flags & F_REAL):
							pp.p_ch = PASSAGE
						pp.p_flags |= (F_SEEN | F_REAL)
						ch = PASSAGE
					if ch != ord(" "):
						obj = pp.p_monst
						if obj != null:
							obj.t_oldch = ch
						if obj == null or not on(player, SEEMONST):
							mvaddch(y, x, ch)
		S_FDET:
			# Potion of gold detection
			ch = 0	# FALSE
			wclear(hw)
			obj = lvl_obj
			while obj != null:
				if obj.o_type == FOOD:
					ch = 1	# TRUE
					wmove(hw, obj.o_pos.y, obj.o_pos.x)
					waddch(hw, FOOD)
				obj = obj.l_next
			if ch != 0:
				scr_info[S_FDET].oi_know = true
				await Io.show_win("Your nose tingles and you smell food.--More--")
			else:
				await Io.msg("your nose tingles")
		S_TELEP:
			# Scroll of teleportation:
			# Make him dissapear and reappear
			cur_room = proom
			await Wizard.teleport()
			if cur_room != proom:
				scr_info[S_TELEP].oi_know = true
		S_ENCH:
			if cur_weapon == null or cur_weapon.o_type != WEAPON:
				await Io.msg("you feel a strange sense of loss")
			else:
				cur_weapon.o_flags &= ~ISCURSED
				if rnd(2) == 0:
					cur_weapon.o_hplus += 1
				else:
					cur_weapon.o_dplus += 1
				await Io.msg("your %s glows %s for a moment",
					[weap_info[cur_weapon.o_which].oi_name, Init.pick_color("blue")])
		S_SCARE:
			# Reading it is a mistake and produces laughter at her
			# poor boo boo.
			await Io.msg("you hear maniacal laughter in the distance")
		S_REMOVE:
			uncurse(cur_armor)
			uncurse(cur_weapon)
			uncurse(cur_ring[LEFT])
			uncurse(cur_ring[RIGHT])
			await Io.msg(Misc.choose_str("you feel in touch with the Universal Oneness" if fixes
				else "you feel in touch with the Universal Onenes",	# FIX typo
				"you feel as if somebody is watching over you"))
		S_AGGR:
			# This scroll aggravates all the monsters on the current
			# level and sets them running towards the hero
			Misc.aggravate()
			await Io.msg("you hear a high pitched humming noise")
		S_PROTECT:
			if cur_armor != null:
				cur_armor.o_flags |= ISPROT
				await Io.msg("your armor is covered by a shimmering %s shield",
					[Init.pick_color("gold")])
			else:
				await Io.msg("you feel a strange sense of loss")
		_:
			if MASTER:
				await Io.msg("what a puzzling scroll!")
				return
	obj = orig_obj
	await Misc.look(true)	# put the result of the scroll on the screen
	await Io.status()

	await Misc.call_it(scr_info[obj.o_which])

	if discardit:
		List.discard(obj)


## uncurse:
##	Uncurse an item
static func uncurse(obj: Thing) -> void:
	if obj != null:
		obj.o_flags &= ~ISCURSED
