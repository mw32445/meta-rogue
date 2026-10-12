## The Fighters' Guild's skills in the game (guild mode; docs/GUILD.md, "Skills"):
## what Rogue 5.4.4 does not have. RogueBase.skill() says which the hero has (always
## none out of guild mode); each rule a skill changes calls in here from its place
## in the game (Fight, Potions, Misc, Chase, Monsters, Weapons, Sticks, Pack).
##
## Throw Anything: a ring or a scroll of enchant weapon a monster was hit with stays
## in its pack, marked ISMONWORN, and works on it (mon_bonus, mon_wears,
## mon_enchants); it is not dropped when the monster dies (Fight.remove_mon).
class_name Skills
extends RogueBase

static var _cp := Coord.new()


# ---- what a monster was hit with (Throw Anything) ---------------------------------

## The bonus a monster has from the rings of a kind it was hit with.
static func mon_bonus(tp: Thing, which: int) -> int:
	var n := 0
	var obj := tp.t_pack
	while obj != null:
		if (obj.o_flags & ISMONWORN) != 0 and obj.o_type == RING and obj.o_which == which:
			n += obj.o_arm
		obj = obj.l_next
	return n


## Whether a monster was hit with a ring of a kind.
static func mon_wears(tp: Thing, which: int) -> bool:
	var obj := tp.t_pack
	while obj != null:
		if (obj.o_flags & ISMONWORN) != 0 and obj.o_type == RING and obj.o_which == which:
			return true
		obj = obj.l_next
	return false


## The damage a monster adds from the scrolls of enchant weapon it was hit with.
static func mon_enchants(tp: Thing) -> int:
	var n := 0
	var obj := tp.t_pack
	while obj != null:
		if (obj.o_flags & ISMONWORN) != 0 and obj.o_type == SCROLL and obj.o_which == S_ENCH:
			n += 1
		obj = obj.l_next
	return n


# ---- Low-Light Vision ---------------------------------------------------------------

## Low-Light Vision is at work: the hero has it and stands in a dark room (not a
## corridor, a maze or a passage's door), and is not blind.
static func low_light() -> bool:
	return skill(SK_LOW_LIGHT) > 0 and (proom.r_flags & (ISGONE | ISDARK)) == ISDARK \
		and (flat(hero.y, hero.x) & F_PASS) == 0 and not on(player, ISBLIND)


## A square that Low-Light Vision shows: at most 2 away, in the hero's dark room
## (its floor, walls and doors).
static func low_light_sees(y: int, x: int) -> bool:
	return low_light() and Chase.dist(y, x, hero.y, hero.x) < 9 and in_room(proom, y, x)


## Whether a square is in a room, walls included (roomin() without its complaint
## about squares in no room).
static func in_room(rp: Room, y: int, x: int) -> bool:
	return x >= rp.r_pos.x and x < rp.r_pos.x + rp.r_max.x \
		and y >= rp.r_pos.y and y < rp.r_pos.y + rp.r_max.y


# ---- monsters moved by a skill's effect -----------------------------------------------

## Teleport a monster to a random place on the level (as the wand of teleport away
## does, without sending it after the hero). A venus flytrap lets go of the hero.
static func mon_teleport(tp: Thing) -> void:
	if tp.t_type == ord("F"):
		player.t_flags &= ~ISHELD
	var new_pos := Coord.new()
	while true:
		Rooms.find_floor(null, new_pos, 0, true)
		if not ce(new_pos, hero):
			break
	Chase.relocate(tp, new_pos)


## Every other monster of the level wakes and goes to this one (a ring or a scroll
## of aggravate monster(s) it was hit with). Fight.killed sends them back after the
## hero when it dies.
static func aggravate_to(tp: Thing) -> void:
	var mp := mlist
	while mp != null:
		if mp != tp:
			mp.t_dest = tp.t_pos
			mp.t_flags |= ISRUN
		mp = mp.l_next


## A monster goes: those going to it go after the hero again.
static func forget(tp: Thing) -> void:
	var mp := mlist
	while mp != null:
		if mp.t_dest == tp.t_pos:
			mp.t_dest = hero
		mp = mp.l_next


## Whether a monster is going to another one (drawn by aggravate monster).
static func drawn(th: Thing) -> bool:
	if th.t_dest == hero or th.t_dest == null:
		return false
	var mp := mlist
	while mp != null:
		if th.t_dest == mp.t_pos:
			return true
		mp = mp.l_next
	return false


## A monster's turn: the rings it was hit with. Regeneration heals it 1 a turn (as
## the hero's ring does); teleportation moves it now and then (1 in 50 a turn, as
## the hero's does).
static func mon_turn(tp: Thing) -> void:
	if mon_wears(tp, R_REGEN) and tp.t_stats.s_hpt < tp.t_stats.s_maxhp:
		tp.t_stats.s_hpt += 1
	if mon_wears(tp, R_TELEPORT) and rnd(50) == 0:
		mon_teleport(tp)


# ---- Throw Anything: what a thrown item does to the monster it hits -----------------

## The item obj hit the monster tp (Fight.fight): it works on it, as if the monster
## drank the potion, read the scroll, wore the ring or was zapped with the wand.
## Armour's damage is roll_em's. Returns false if tp did not live through it.
static func thrown_at(obj: Thing, tp: Thing) -> bool:
	match obj.o_type:
		POTION:
			await _potion_on(obj, tp)
		SCROLL:
			await _scroll_on(obj, tp)
		RING:
			await _ring_on(obj, tp)
		STICK:
			await _stick_on(obj, tp)
	return Chase._on_mlist(tp)


static func _potion_on(obj: Thing, tp: Thing) -> void:
	var st: Stats = tp.t_stats
	var said := ""
	match obj.o_which:
		P_CONFUSE:
			tp.t_flags |= ISHUH
			said = "%s appears confused"
		P_BLIND:
			tp.t_flags |= ISHUH
			said = "%s stumbles about blindly"
		P_POISON:
			if not mon_wears(tp, R_SUSTSTR):
				st.s_str = maxi(3, st.s_str - (rnd(3) + 1))
			said = "%s looks very sick"
		P_STRENGTH:
			st.s_str = mini(31, st.s_str + 1)
			said = "%s looks stronger"
		P_RESTORE:
			st.s_str = maxi(st.s_str, monsters[tp.t_type - ord("A")].m_stats.s_str)
		P_HEALING:
			st.s_hpt += roll(st.s_lvl, 4)
			if st.s_hpt > st.s_maxhp:
				st.s_maxhp += 1
				st.s_hpt = st.s_maxhp
			said = "%s looks better"
		P_XHEAL:
			st.s_hpt += roll(st.s_lvl, 8)
			if st.s_hpt > st.s_maxhp:
				if st.s_hpt > st.s_maxhp + st.s_lvl + 1:
					st.s_maxhp += 1
				st.s_maxhp += 1
				st.s_hpt = st.s_maxhp
			said = "%s looks much better"
		P_RAISE:
			var more := roll(1, 8)
			st.s_lvl += 1
			st.s_maxhp += more
			st.s_hpt += more
			st.s_exp += 10
			said = "%s looks more skillful"
		P_HASTE:
			if on(tp, ISHASTE):
				tp.t_flags &= ~(ISHASTE | ISRUN)	# it faints from exhaustion: asleep
				said = "%s faints from exhaustion"
			else:
				if on(tp, ISSLOW):
					tp.t_flags &= ~ISSLOW
				else:
					tp.t_flags |= ISHASTE
				said = "%s speeds up"
		_:	# hallucination, see invisible, the detections, levitation: nothing to see
			pass
	if said != "" and Chase.see_monst(tp):
		pot_info[obj.o_which].oi_know = true
		await Io.msg(said, [Fight.set_mname(tp)])


static func _scroll_on(obj: Thing, tp: Thing) -> void:
	var said := ""
	match obj.o_which:
		S_CONFUSE:
			tp.t_flags |= ISHUH
			said = "%s appears confused"
		S_SLEEP:
			tp.t_flags &= ~ISRUN
			said = "%s falls asleep"
		S_HOLD:
			for y in range(tp.t_pos.y - 2, tp.t_pos.y + 3):
				for x in range(tp.t_pos.x - 2, tp.t_pos.x + 3):
					if y >= 0 and y < NUMLINES and x >= 0 and x < NUMCOLS:
						var mp := moat(y, x)
						if mp != null and on(mp, ISRUN):
							mp.t_flags &= ~ISRUN
							mp.t_flags |= ISHELD
			said = "%s freezes"
		S_TELEP:
			var seen := Chase.see_monst(tp)
			var nm := Fight.set_mname(tp)
			mon_teleport(tp)
			if seen:
				scr_info[S_TELEP].oi_know = true
				await Io.msg("%s vanishes", [nm])
			return
		S_CREATE:
			_create_near(tp)
		S_AGGR:
			aggravate_to(tp)
			scr_info[S_AGGR].oi_know = true
			await Io.msg("you hear a high pitched humming noise")
			return
		S_ARMOR:
			tp.t_stats.s_arm -= 1
			said = "%s glows faintly for a moment"
		S_ENCH:
			obj.o_flags |= ISMONWORN
			tp.t_pack = List._attach(tp.t_pack, obj)
			said = "%s glows faintly for a moment"
		_:	# magic mapping, the identifications, remove curse, protect armor, food
			# detection, scare monster: nothing it can use
			pass
	if said != "" and Chase.see_monst(tp):
		scr_info[obj.o_which].oi_know = true
		await Io.msg(said, [Fight.set_mname(tp)])


## A monster appears next to tp, if there is room (as the scroll of create monster
## does next to the hero).
static func _create_near(tp: Thing) -> void:
	var i := 0
	var mp := Coord.new()
	for y in range(tp.t_pos.y - 1, tp.t_pos.y + 2):
		for x in range(tp.t_pos.x - 1, tp.t_pos.x + 2):
			if (y == tp.t_pos.y and x == tp.t_pos.x) or (y == hero.y and x == hero.x):
				continue
			if y < 1 or y >= NUMLINES - 1 or x < 0 or x >= NUMCOLS or moat(y, x) != null:
				continue
			if winat(y, x) == SCROLL and _scare_at(y, x):
				continue
			if Io.step_ok(winat(y, x)):
				i += 1
				if rnd(i) == 0:
					mp.y = y
					mp.x = x
	if i > 0:
		Monsters.new_monster(List.new_item(), Monsters.randmonster(false), mp)


## A scroll of scare monster lies there.
static func _scare_at(y: int, x: int) -> bool:
	var op := lvl_obj
	while op != null:
		if op.o_pos.y == y and op.o_pos.x == x:
			return op.o_type == SCROLL and op.o_which == S_SCARE
		op = op.l_next
	return false


static func _ring_on(obj: Thing, tp: Thing) -> void:
	match obj.o_which:
		R_TELEPORT, R_PROTECT, R_ADDSTR, R_ADDHIT, R_ADDDAM, R_SUSTSTR, R_REGEN:
			pass	# it works while the monster carries it
		R_AGGR:
			aggravate_to(tp)
			await Io.msg("you hear a high pitched humming noise")
		_:	# searching, see invisible, adornment, slow digestion, stealth, maintain
			# armor: nothing a monster does with it
			return
	obj.o_flags |= ISMONWORN
	tp.t_pack = List._attach(tp.t_pack, obj)


static func _stick_on(obj: Thing, tp: Thing) -> void:
	var y := tp.t_pos.y
	var x := tp.t_pos.x
	var seen := Chase.see_monst(tp)
	var nm := Fight.set_mname(tp)
	if tp.t_type == ord("F") and obj.o_which in [WS_HASTE_M, WS_SLOW_M, WS_TELAWAY, WS_TELTO,
			WS_CANCEL, WS_POLYMORPH]:
		player.t_flags &= ~ISHELD	# as do_zap(): a venus flytrap lets go
	match obj.o_which:
		WS_LIGHT:	# as when zapped: the hero's room is lit
			if proom.r_flags & ISGONE:
				await Io.msg("the corridor glows and then fades")
			else:
				proom.r_flags &= ~ISDARK
				await Rooms.enter_room(hero)
				await Io.msg("the room is lit")
		WS_DRAIN:	# as when zapped: around the hero
			if pstats.s_hpt < 2:
				await Io.msg("you are too weak to use it")
				return
			await Sticks.drain()
		WS_INVIS:
			tp.t_flags |= ISINVIS
			if Chase.cansee(y, x):
				mvaddch(y, x, tp.t_oldch)
		WS_POLYMORPH:
			var pp := tp.t_pack
			mlist = List._detach(mlist, tp)
			if Chase.see_monst(tp):
				mvaddch(y, x, chat(y, x))
			var oldch := tp.t_oldch
			_cp.y = y
			_cp.x = x
			var kind := to_schar(rnd(26) + ord("A"))
			Monsters.new_monster(tp, kind, _cp)
			if Chase.see_monst(tp):
				mvaddch(y, x, kind)
			tp.t_oldch = oldch
			tp.t_pack = pp
			Chase.runto(_cp)	# as do_zap() does after it
		WS_CANCEL:
			tp.t_flags |= ISCANC
			tp.t_flags &= ~(ISINVIS | CANHUH)
			tp.t_disguise = tp.t_type
			if Chase.see_monst(tp):
				mvaddch(y, x, tp.t_disguise)
		WS_TELAWAY:
			tp.t_dest = hero
			tp.t_flags |= ISRUN
			mon_teleport(tp)
		WS_TELTO:
			var new_pos := Coord.new()
			new_pos.y = hero.y + delta.y
			new_pos.x = hero.x + delta.x
			if moat(new_pos.y, new_pos.x) == null and Io.step_ok(winat(new_pos.y, new_pos.x)):
				tp.t_dest = hero
				tp.t_flags |= ISRUN
				Chase.relocate(tp, new_pos)
		WS_HASTE_M:
			if on(tp, ISSLOW):
				tp.t_flags &= ~ISSLOW
			else:
				tp.t_flags |= ISHASTE
		WS_SLOW_M:
			if on(tp, ISHASTE):
				tp.t_flags &= ~ISHASTE
			else:
				tp.t_flags |= ISSLOW
			tp.t_turn = true
		WS_MISSILE:
			if not Monsters.save_throw(VS_MAGIC, tp):
				tp.t_stats.s_hpt -= roll(1, 4) + 1
				await Io.msg("the magic missile hits %s", [nm])
			else:
				await Io.msg("the missile vanishes with a puff of smoke")
		WS_ELECT, WS_FIRE, WS_COLD:
			var name := "bolt" if obj.o_which == WS_ELECT else ("flame" if obj.o_which == WS_FIRE
				else "ice")
			if Monsters.save_throw(VS_MAGIC, tp):
				await Io.msg("the %s whizzes past %s", [name, nm])
			elif tp.t_type == ord("D") and name == "flame":
				await Io.msg("the flame bounces off the dragon")
			else:
				tp.t_stats.s_hpt -= roll(6, 6)
				await Io.msg("the %s hits %s", [name, nm])
		_:	# nothing
			return
	if seen or obj.o_which == WS_LIGHT or obj.o_which == WS_DRAIN:
		ws_info[obj.o_which].oi_know = true


# ---- the Serpentine Cult -------------------------------------------------------------

## The monster a thrown item or a wand's zap meets first going from the hero along
## (dy, dx) (stopping at a door, as a thrown item does, if at_doors), or null.
static func first_monster(dy: int, dx: int, at_doors: bool) -> Thing:
	var y := hero.y
	var x := hero.x
	while true:
		y += dy
		x += dx
		if y < 0 or y >= NUMLINES or x < 0 or x >= NUMCOLS:
			return null
		var ch := winat(y, x)
		if not Io.step_ok(ch) or (at_doors and ch == DOOR):
			break
	return moat(y, x)


## The monsters a wand's zap aims at (drain life: all it would drain).
static func zap_targets(obj: Thing) -> Array:
	match obj.o_which:
		WS_LIGHT, WS_NOP:
			return []
		WS_DRAIN:
			var out := []
			var corp: Room = passages[flat(hero.y, hero.x) & F_PNUM] if chat(hero.y, hero.x) == DOOR \
				else null
			var inpass := (proom.r_flags & ISGONE) != 0
			var mp := mlist
			while mp != null:
				if mp.t_room == proom or mp.t_room == corp or (inpass and chat(mp.t_pos.y, mp.t_pos.x)
						== DOOR and passages[flat(mp.t_pos.y, mp.t_pos.x) & F_PNUM] == proom):
					out.append(mp)
				mp = mp.l_next
			return out
	# (a magic missile flies as a thrown thing does, stopping at a door)
	var tp := first_monster(delta.y, delta.x, obj.o_which == WS_MISSILE)
	return [tp] if tp != null else []


## A hostile action against these monsters: in the Serpentine Cult, the first one
## against a snake is stopped with a warning (no time passes); another one right
## after it goes ahead, and those snakes need no more asking. (Command.command
## forgets the warning once a command takes time.) Returns whether it goes ahead.
static func cult_allows(targets: Array) -> bool:
	if not cult_member():
		return true
	var snakes := []
	for tp in targets:
		if is_snake(tp) and not cult_confirmed.has(tp):
			snakes.append(tp)
	if snakes.is_empty():
		return true
	var warned := true
	for tp in snakes:
		warned = warned and cult_warned.has(tp)
	if warned:
		cult_confirmed.append_array(snakes)
		cult_warned = []
		return true
	cult_warned = snakes
	for tp in snakes:
		tp.t_flags &= ~ISTARGET
	after = false
	running = false
	count = 0
	to_death = false	# the fight command stops too: it would do it again itself
	kamikaze = false
	await Io.msg("snakes are sacred to the cult: do it again to attack")
	return false


## A snake dies (by any means): in the cult, the hero is banished from it.
static func cult_kill(tp: Thing) -> void:
	if cult_member() and is_snake(tp):
		cult_banished = true
		await Io.msg("you are banished from the Serpentine Cult!")
