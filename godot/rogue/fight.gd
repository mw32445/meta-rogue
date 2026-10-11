## fight.c: All the fighting gets done here
##
## @(#)fight.c	4.67 (Berkeley) 09/06/83
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## set_mname() and prname() return their C static buffer (tbuf) as a String.
## A `char *` monster name that may be NULL (hit/miss/prname er, ee, mname)
## is a Variant holding null or a String.
class_name Fight
extends RogueBase

## #define EQSTR(a, b) (strcmp(a, b) == 0)	(unused)

## strings for hitting
const h_names: Array[String] = [
	" scored an excellent hit on ",
	" hit ",
	" have injured ",
	" swing and hit ",
	" scored an excellent hit on ",
	" hit ",
	" has injured ",
	" swings and hits ",
]

## strings for missing
const m_names: Array[String] = [
	" miss",
	" swing and miss",
	" barely miss",
	" don't hit",
	" misses",
	" swings and misses",
	" barely misses",
	" doesn't hit",
]

## adjustments to hit probabilities due to strength
const str_plus: Array[int] = [
	-7, -6, -5, -4, -3, -2, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1,
	1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3,
]

## adjustments to damage done due to strength
const add_dam: Array[int] = [
	-7, -6, -5, -4, -3, -2, -1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 2, 3,
	3, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6,
]


## fight:
##	The player attacks the monster.
static func fight(mp: Coord, weap: Thing, thrown: bool) -> int:
	var tp: Thing
	var did_hit := true
	var mname: String
	var ch: int

	# Find the monster we want to fight
	if MASTER:
		tp = moat(mp.y, mp.x)
		if tp == null:
			await debug("Fight what @ %d,%d", [mp.y, mp.x])
	else:
		tp = moat(mp.y, mp.x)
	# Since we are fighting, things are not quiet so no healing takes
	# place.
	count = 0
	quiet = 0
	Chase.runto(mp)
	# Let him know it was really a xeroc (if it was one).
	ch = 0
	if tp.t_type == ord("X") and tp.t_disguise != ord("X") and not on(player, ISBLIND):
		tp.t_disguise = ord("X")
		if on(player, ISHALU):
			ch = rnd(26) + ord("A")
			mvaddch(tp.t_pos.y, tp.t_pos.x, ch)
		await Io.msg(Misc.choose_str("heavy!  That's a nasty critter!",
			"wait!  That's a xeroc!"))
		if not thrown:
			return 0	# FALSE
	mname = set_mname(tp)
	did_hit = false
	has_hit = terse and not to_death
	if await roll_em(player, tp, weap, thrown):
		did_hit = false
		if thrown:
			await thunk(weap, mname, terse)
		else:
			await hit(null, mname, terse)
		if on(player, CANHUH):
			did_hit = true
			tp.t_flags |= ISHUH
			player.t_flags &= ~CANHUH
			await Io.endmsg()
			has_hit = false
			await Io.msg("your hands stop glowing %s", [Init.pick_color("red")])
		if tp.t_stats.s_hpt <= 0:
			await killed(tp, true)
		elif did_hit and not on(player, ISBLIND):
			await Io.msg("%s appears confused", [mname])
		did_hit = true
	else:
		if thrown:
			await bounce(weap, mname, terse)
		else:
			await miss(null, mname, terse)
	return int(did_hit)


## attack:
##	The monster attacks the player
static func attack(mp: Thing) -> int:
	var mname: String
	var oldhp: int

	# Since this is an attack, stop running and any healing that was
	# going on at the time.
	running = false
	count = 0
	quiet = 0
	if to_death and not on(mp, ISTARGET):
		to_death = false
		kamikaze = false
	if mp.t_type == ord("X") and mp.t_disguise != ord("X") and not on(player, ISBLIND):
		mp.t_disguise = ord("X")
		if on(player, ISHALU):
			mvaddch(mp.t_pos.y, mp.t_pos.x, rnd(26) + ord("A"))
	mname = set_mname(mp)
	oldhp = pstats.s_hpt
	if await roll_em(mp, player, null, false):
		if mp.t_type != ord("I"):
			if has_hit:
				await Io.addmsg(".  ")
			await hit(mname, null, false)
		else:
			if has_hit:
				await Io.endmsg()
		has_hit = false
		if pstats.s_hpt <= 0:
			await Rip.death(mp.t_type)	# Bye bye life ...
		elif not kamikaze:
			oldhp -= pstats.s_hpt
			if oldhp > max_hit:
				max_hit = oldhp
			if pstats.s_hpt <= max_hit:
				to_death = false
		if not on(mp, ISCANC):
			match mp.t_type:
				ord("A"):
					# If an aquator hits, you can lose armor class.
					await Move.rust_armor(cur_armor)
				ord("I"):
					# The ice monster freezes you
					player.t_flags &= ~ISRUN
					if no_command == 0:
						await Io.addmsg("you are frozen")
						if not terse:
							await Io.addmsg(" by the %s", [mname])
						await Io.endmsg()
					no_command += rnd(2) + 2
					if no_command > BORE_LEVEL:
						await Rip.death(ord("h"))
				ord("R"):
					# Rattlesnakes have poisonous bites
					if not Monsters.save(VS_POISON):
						if not ISWEARING(R_SUSTSTR):
							Misc.chg_str(-1)
							if not terse:
								await Io.msg("you feel a bite in your leg and now feel weaker")
							else:
								await Io.msg("a bite has weakened you")
						elif not to_death:
							if not terse:
								await Io.msg("a bite momentarily weakens you")
							else:
								await Io.msg("bite has no effect")
				ord("W"), ord("V"):
					# Wraiths might drain energy levels, and Vampires
					# can steal max_hp
					if rnd(100) < (15 if mp.t_type == ord("W") else 30):
						var fewer: int

						if mp.t_type == ord("W"):
							if pstats.s_exp == 0:
								await Rip.death(ord("W"))	# All levels gone
							pstats.s_lvl -= 1
							if pstats.s_lvl == 0:
								pstats.s_exp = 0
								pstats.s_lvl = 1
							else:
								pstats.s_exp = e_levels[pstats.s_lvl - 1] + 1
							fewer = roll(1, 10)
						else:
							fewer = roll(1, 3)
						pstats.s_hpt -= fewer
						max_hp -= fewer
						if pstats.s_hpt <= 0:
							pstats.s_hpt = 1
						if max_hp <= 0:
							await Rip.death(mp.t_type)
						await Io.msg("you suddenly feel weaker")
				ord("F"):
					# Venus Flytrap stops the poor guy from moving
					player.t_flags |= ISHELD
					vf_hit += 1
					monsters[ord("F") - ord("A")].m_stats.s_dmg = sprintf("%dx1", [vf_hit])
					pstats.s_hpt -= 1
					if pstats.s_hpt <= 0:
						await Rip.death(ord("F"))
				ord("L"):
					# Leperachaun steals some gold
					var lastpurse: int

					lastpurse = purse
					purse -= GOLDCALC()
					if not Monsters.save(VS_MAGIC):
						purse -= GOLDCALC() + GOLDCALC() + GOLDCALC() + GOLDCALC()
					if purse < 0:
						purse = 0
					await remove_mon(mp.t_pos, mp, false)
					mp = null
					if purse != lastpurse:
						await Io.msg("your purse feels lighter")
				ord("N"):
					var obj: Thing
					var steal: Thing
					var nobj: int

					# Nymph's steal a magic item, look through the pack
					# and pick out one we like.
					steal = null
					nobj = 0
					obj = pack
					while obj != null:
						if obj != cur_armor and obj != cur_weapon \
								and obj != cur_ring[LEFT] and obj != cur_ring[RIGHT] \
								and Potions.is_magic(obj):
							nobj += 1	# C: && rnd(++nobj) == 0
							if rnd(nobj) == 0:
								steal = obj
						obj = obj.l_next
					if steal != null:
						await remove_mon(mp.t_pos, moat(mp.t_pos.y, mp.t_pos.x), false)
						mp = null
						Pack.leave_pack(steal, false, false)
						var nm: String = await Things.inv_name(steal, true)
						await Io.msg("she stole %s!", [nm])
						List.discard(steal)
				_:
					pass
	elif mp.t_type != ord("I"):
		if has_hit:
			await Io.addmsg(".  ")
			has_hit = false
		if mp.t_type == ord("F"):
			pstats.s_hpt -= vf_hit
			if pstats.s_hpt <= 0:
				await Rip.death(mp.t_type)	# Bye bye life ...
		await miss(mname, null, false)
	if fight_flush and not to_death:
		MachDep.flush_type()
	count = 0
	await Io.status()
	if mp == null:
		return -1
	else:
		return 0


## set_mname:
##	return the monster name for the given monster
static func set_mname(tp: Thing) -> String:
	var ch: int
	var mname: String

	if not Chase.see_monst(tp) and not on(player, SEEMONST):
		return "it" if terse else "something"
	elif on(player, ISHALU):
		move(tp.t_pos.y, tp.t_pos.x)
		ch = inch() & 0x7f	# toascii(inch())
		if not isupper(ch):
			ch = rnd(26)
		else:
			ch -= ord("A")
		mname = monsters[ch].m_name
	else:
		mname = monsters[tp.t_type - ord("A")].m_name
	# C: strcpy(&tbuf[4], mname) after the static "the "
	return "the " + mname


## swing:
##	Returns true if the swing hits
static func swing(at_lvl: int, op_arm: int, wplus: int) -> int:
	var res := rnd(20)
	var need := (20 - at_lvl) - op_arm

	return int(res + wplus >= need)


## roll_em:
##	Roll several attacks
static func roll_em(thatt: Thing, thdef: Thing, weap: Thing, hurl: bool) -> bool:
	var att: Stats
	var def: Stats
	var cp: String	# char *cp is the string cp from index ci on
	var ci: int
	var ndice: int
	var nsides: int
	var def_arm: int
	var did_hit := false
	var hplus: int
	var dplus: int
	var damage: int

	att = thatt.t_stats
	def = thdef.t_stats
	if weap == null:
		cp = att.s_dmg
		dplus = 0
		hplus = 0
	else:
		hplus = 0 if weap == null else weap.o_hplus
		dplus = 0 if weap == null else weap.o_dplus
		if weap == cur_weapon:
			if ISRING(LEFT, R_ADDDAM):
				dplus += cur_ring[LEFT].o_arm
			elif ISRING(LEFT, R_ADDHIT):
				hplus += cur_ring[LEFT].o_arm
			if ISRING(RIGHT, R_ADDDAM):
				dplus += cur_ring[RIGHT].o_arm
			elif ISRING(RIGHT, R_ADDHIT):
				hplus += cur_ring[RIGHT].o_arm
		cp = weap.o_damage
		if hurl:
			if (weap.o_flags & ISMISL) != 0 and cur_weapon != null \
					and cur_weapon.o_which == weap.o_launch:
				cp = weap.o_hurldmg
				hplus += cur_weapon.o_hplus
				dplus += cur_weapon.o_dplus
			elif weap.o_launch < 0:
				cp = weap.o_hurldmg
	# If the creature being attacked is not running (alseep or held)
	# then the attacker gets a plus four bonus to hit.
	if not on(thdef, ISRUN):
		hplus += 4
	def_arm = def.s_arm
	if def == pstats:
		if cur_armor != null:
			def_arm = cur_armor.o_arm
		if ISRING(LEFT, R_PROTECT):
			def_arm -= cur_ring[LEFT].o_arm
		if ISRING(RIGHT, R_PROTECT):
			def_arm -= cur_ring[RIGHT].o_arm
	ci = 0
	while cat(cp, ci) != 0:	# C: cp != NULL && *cp != '\0'
		ndice = atoi(cp.substr(ci))
		ci = cp.find("x", ci)	# C: cp = strchr(cp, 'x')
		if ci == -1:
			break
		ci += 1
		nsides = atoi(cp.substr(ci))
		if swing(att.s_lvl, def_arm, hplus + str_plus[att.s_str]):
			var proll: int

			proll = roll(ndice, nsides)
			if MASTER:
				if ndice + nsides > 0 and proll <= 0:
					await debug("Damage for %dx%d came out %d, dplus = %d, add_dam = %d, def_arm = %d",
						[ndice, nsides, proll, dplus, add_dam[att.s_str], def_arm])
			damage = dplus + proll + add_dam[att.s_str]
			def.s_hpt -= maxi(0, damage)
			did_hit = true
		ci = cp.find("/", ci)	# C: cp = strchr(cp, '/')
		if ci == -1:
			break
		ci += 1
	return did_hit


## prname:
##	The print name of a combatant
static func prname(mname: Variant, upper: bool) -> String:
	var tbuf := ""

	if mname == null:
		tbuf = "you"
	else:
		tbuf = mname
	if upper and tbuf != "":	# (*tbuf = toupper('\0') leaves "" as it is)
		tbuf = chr(toupper(cat(tbuf, 0))) + tbuf.substr(1)
	return tbuf


## thunk:
##	A missile hits a monster
static func thunk(weap: Thing, mname: String, noend: bool) -> void:
	if to_death:
		return
	if weap.o_type == WEAPON:
		await Io.addmsg("the %s hits ", [weap_info[weap.o_which].oi_name])
	else:
		await Io.addmsg("you hit ")
	await Io.addmsg("%s", [mname])
	if not noend:
		await Io.endmsg()


## hit:
##	Print a message to indicate a succesful hit
static func hit(er: Variant, ee: Variant, noend: bool) -> void:
	var i: int
	var s: String

	if to_death:
		return
	await Io.addmsg(prname(er, true))
	if terse:
		s = " hit"
	else:
		i = rnd(4)
		if er != null:
			i += 4
		s = h_names[i]
	await Io.addmsg(s)
	if not terse:
		await Io.addmsg(prname(ee, false))
	if not noend:
		await Io.endmsg()


## miss:
##	Print a message to indicate a poor swing
static func miss(er: Variant, ee: Variant, noend: bool) -> void:
	var i: int

	if to_death:
		return
	await Io.addmsg(prname(er, true))
	if terse:
		i = 0
	else:
		i = rnd(4)
	if er != null:
		i += 4
	await Io.addmsg(m_names[i])
	if not terse:
		await Io.addmsg(" %s", [prname(ee, false)])
	if not noend:
		await Io.endmsg()


## bounce:
##	A missile misses a monster
static func bounce(weap: Thing, mname: String, noend: bool) -> void:
	if to_death:
		return
	if weap.o_type == WEAPON:
		await Io.addmsg("the %s misses ", [weap_info[weap.o_which].oi_name])
	else:
		await Io.addmsg("you missed ")
	await Io.addmsg(mname)
	if not noend:
		await Io.endmsg()


## remove_mon:
##	Remove a monster from the screen
static func remove_mon(mp: Coord, tp: Thing, waskill: bool) -> void:
	var obj: Thing
	var nexti: Thing

	obj = tp.t_pack
	while obj != null:
		nexti = obj.l_next
		obj.o_pos.copy_from(tp.t_pos)
		tp.t_pack = List._detach(tp.t_pack, obj)
		if waskill:
			await Weapons.fall(obj, false)
		else:
			List.discard(obj)
		obj = nexti
	INDEX(mp.y, mp.x).p_monst = null
	mvaddch(mp.y, mp.x, tp.t_oldch)
	mlist = List._detach(mlist, tp)
	if on(tp, ISTARGET):
		kamikaze = false
		to_death = false
		if fight_flush:
			MachDep.flush_type()
	List.discard(tp)


## killed:
##	Called to put a monster to death
static func killed(tp: Thing, pr: bool) -> void:
	var mname: String

	pstats.s_exp += tp.t_stats.s_exp

	# If the monster was a venus flytrap, un-hold him
	match tp.t_type:
		ord("F"):
			player.t_flags &= ~ISHELD
			vf_hit = 0
			monsters[ord("F") - ord("A")].m_stats.s_dmg = "000x0"
		ord("L"):
			var gold: Thing

			if Weapons.fallpos(tp.t_pos, tp.t_room.r_gold) and level >= max_level:
				gold = List.new_item()
				gold.o_type = GOLD
				gold.o_goldval = GOLDCALC()
				if Monsters.save(VS_MAGIC):
					gold.o_goldval += GOLDCALC() + GOLDCALC() \
						+ GOLDCALC() + GOLDCALC()
				tp.t_pack = List._attach(tp.t_pack, gold)
	# Get rid of the monster.
	mname = set_mname(tp)
	await remove_mon(tp.t_pos, tp, true)
	if pr:
		if has_hit:
			await Io.addmsg(".  Defeated ")
			has_hit = false
		else:
			if not terse:
				await Io.addmsg("you have ")
			await Io.addmsg("defeated ")
		await Io.msg(mname)
	# Do adjustments if he went up a level
	await Misc.check_level()
	if fight_flush:
		MachDep.flush_type()
