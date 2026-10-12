## The Fighters' Guild: puts the Guild's purchases into the hero's starting pack
## (docs/GUILD.md).
##
## Main.main() awaits apply(RogueBase.loadout) right after Init.init_materials(),
## in guild mode, once per new game (never for a restored one). The issued kit is
## already in the pack then (Init.init_player) and the kinds have their names,
## colours, stones and materials. apply() uses the game's own helpers: objects
## start as Things.new_thing() starts them, then Weapons.init_weapon(),
## Sticks.fix_stick() and Pack.add_pack() make them what they are. A dagger, a
## wand or a staff draws on the RNG, so a loadout changes the dungeon of a seed.
##
## The loadout (GuildShop.loadout() makes one; godot/tests/replay.gd reads one
## from a JSON file, so numbers may be floats). Every key is optional:
##   "maxpack": int          pack slots, 23 (Rogue's MAXPACK) to 52
##   "str": int              strength points to add (Misc.chg_str; at most 31)
##   "hp": int               max hit points to add
##   "weapon": {"which": w, "enh": k}
##                           the student's weapon (o_which; MACE is issued): it is
##                           the issued one, changed in place, +1,+1 plus k
##                           enhancements (each +1 to the lower of hit and damage,
##                           damage first); a dagger is a single dagger
##   "bow": {"enh": k}       enhancements of the issued +1,+0 short bow
##   "armor": {"which": a, "enh": k}
##                           the student's armour (RING_MAIL is issued), +1 plus k
##   "arrows": n             arrows added to the issued stack
##   "weapons": [{"which": w, "enh": k}, ...]   spare weapons, +0,+0 plus k
##   "armors": [{"which": a, "enh": k}, ...]    spare armour, +0 plus k
##   "missiles": [{"which": w, "count": n}, ...]
##                           a stack of n darts, shuriken or daggers each, +0,+0
##   "rings": [{"which": r, "enh": k}, ...]
##                           protection, add strength, dexterity and increase
##                           damage come +1+k; adornment is polished k times (at
##                           most GuildCatalog.POLISH_LIMIT, 20: a winner sells it
##                           for its worth * 2^k, see Rip.total_winner);
##                           teleportation and aggravate monster are cursed
##   "sticks": [{"which": s, "enh": k, "charges": c}, ...]
##                           c charges; without "charges", as the built-in price
##                           list gives them: 5 (light 15) plus 2 per k
##   "potions", "scrolls": [{"which": p, "count": n}, ...]
##   "food": n               rations added
##   "know_potions", "know_scrolls": [p, ...]   kinds identified for the run
## The counts (hit points, arrows, missiles, charges) are in the loadout: applying
## one needs no price list. Every weapon, armour, ring and stick is known
## (ISKNOW), and every kind bought or identified is known for the run (oi_know).
## All of it must fit in the pack: apply() never lets add_pack() refuse (it would
## stop for a message), so a purchase that does not fit is left out with an error.
class_name Loadout
extends RogueBase


static func apply(l: Dictionary) -> void:
	var obj: Thing

	# The pack's size first: everything below must fit (52: pack letters a-z, A-Z)
	maxpack = clampi(_int(l, "maxpack", MAXPACK), MAXPACK, GuildCatalog.PACK_MAX)

	# Training
	var n := _int(l, "str", 0)
	if n > 0:
		Misc.chg_str(n)
	n = _int(l, "hp", 0)
	if n > 0:
		pstats.s_hpt += n
		pstats.s_maxhp += n

	# The issued weapon, bow, arrows and armour, changed in place
	if l.has("weapon"):
		var w: Variant = l["weapon"]
		var which := _int(w, "which", MACE)
		if which >= 0 and which < MAXWEAPONS:
			var found := cur_weapon.o_flags & ISFOUND
			Weapons.init_weapon(cur_weapon, which)
			if which == DAGGER:
				cur_weapon.o_count = 1	# the one in hand
			cur_weapon.o_hplus = 1
			cur_weapon.o_dplus = 1
			_enhance(cur_weapon, _int(w, "enh", 0))
			cur_weapon.o_flags |= ISKNOW | found
	if l.has("bow"):
		obj = _issued(BOW)
		if obj != null:
			_enhance(obj, _int(l["bow"], "enh", 0))
	n = _int(l, "arrows", 0)
	if n > 0:
		obj = _issued(ARROW)
		if obj != null:
			obj.o_count += n
	if l.has("armor"):
		var a: Variant = l["armor"]
		var which := _int(a, "which", RING_MAIL)
		if which >= 0 and which < MAXARMORS:
			cur_armor.o_which = which
			cur_armor.o_arm = a_class[which] - 1 - maxi(0, _int(a, "enh", 0))
			cur_armor.o_flags |= ISKNOW

	# Spare weapons and armour
	for e in _list(l, "weapons"):
		var which := _int(e, "which", -1)
		if which < 0 or which >= MAXWEAPONS:
			continue
		obj = _new_obj()
		Weapons.init_weapon(obj, which)
		_enhance(obj, _int(e, "enh", 0))
		obj.o_flags |= ISKNOW
		await _add(obj)
	for e in _list(l, "armors"):
		var which := _int(e, "which", -1)
		if which < 0 or which >= MAXARMORS:
			continue
		obj = _new_obj()
		obj.o_type = ARMOR
		obj.o_which = which
		obj.o_arm = a_class[which] - maxi(0, _int(e, "enh", 0))
		obj.o_flags |= ISKNOW
		await _add(obj)
	for e in _list(l, "missiles"):
		var which := _int(e, "which", -1)
		if which != DART and which != SHIRAKEN and which != DAGGER:
			continue
		obj = _new_obj()
		Weapons.init_weapon(obj, which)
		obj.o_count = maxi(1, _int(e, "count", 1))
		obj.o_flags |= ISKNOW
		await _add(obj)

	# Rings and sticks
	for e in _list(l, "rings"):
		var which := _int(e, "which", -1)
		if which < 0 or which >= MAXRINGS:
			continue
		obj = _new_obj()
		obj.o_type = RING
		obj.o_which = which
		match which:
			R_ADDSTR, R_PROTECT, R_ADDHIT, R_ADDDAM:
				obj.o_arm = 1 + maxi(0, _int(e, "enh", 0))
			R_AGGR, R_TELEPORT:
				obj.o_flags |= ISCURSED
			R_NOP:
				obj.o_arm += clampi(_int(e, "enh", 0), 0, GuildCatalog.POLISH_LIMIT)	# polished
		obj.o_flags |= ISKNOW
		ring_info[which].oi_know = true
		await _add(obj)
	for e in _list(l, "sticks"):
		var which := _int(e, "which", -1)
		if which < 0 or which >= MAXSTICKS:
			continue
		obj = _new_obj()
		obj.o_type = STICK
		obj.o_which = which
		Sticks.fix_stick(obj)
		var enh := maxi(0, _int(e, "enh", 0))
		obj.o_charges = maxi(0, _int(e, "charges", GuildShop.charges_of(which, enh)))
		obj.o_flags |= ISKNOW
		ws_info[which].oi_know = true
		await _add(obj)

	# Potions, scrolls and food, one at a time (each one merges with its kind)
	for e in _list(l, "potions"):
		var which := _int(e, "which", -1)
		if which < 0 or which >= MAXPOTIONS:
			continue
		pot_info[which].oi_know = true
		for i in _int(e, "count", 0):
			obj = _new_obj()
			obj.o_type = POTION
			obj.o_which = which
			await _add(obj)
	for e in _list(l, "scrolls"):
		var which := _int(e, "which", -1)
		if which < 0 or which >= MAXSCROLLS:
			continue
		scr_info[which].oi_know = true
		for i in _int(e, "count", 0):
			obj = _new_obj()
			obj.o_type = SCROLL
			obj.o_which = which
			await _add(obj)
	for i in _int(l, "food", 0):
		obj = _new_obj()
		obj.o_type = FOOD
		obj.o_which = 0
		await _add(obj)

	# Kinds identified for this run
	for which in _list(l, "know_potions"):
		if int(which) >= 0 and int(which) < MAXPOTIONS:
			pot_info[int(which)].oi_know = true
	for which in _list(l, "know_scrolls"):
		if int(which) >= 0 and int(which) < MAXSCROLLS:
			scr_info[int(which)].oi_know = true


## A new object as Things.new_thing() starts one, before it picks the kind.
static func _new_obj() -> Thing:
	var cur := List.new_item()
	cur.o_hplus = 0
	cur.o_dplus = 0
	cur.o_damage = "0x0"
	cur.o_hurldmg = "0x0"
	cur.o_arm = 11
	cur.o_count = 1
	cur.o_group = 0
	cur.o_flags = 0
	return cur


## Into the pack, silently. Every add_pack() of a new object takes one more slot
## (pack_room); one that would not fit is left out, so add_pack() never stops
## for its "no room" message.
static func _add(obj: Thing) -> void:
	if inpack >= maxpack:
		push_error("Loadout: no room in the pack for a %s" % chr(obj.o_type))
		return
	await Pack.add_pack(obj, true)


## The issued weapon of a kind (the bow, the arrows), or null.
static func _issued(which: int) -> Thing:
	var op := pack
	while op != null:
		if op.o_type == WEAPON and op.o_which == which:
			return op
		op = op.l_next
	return null


## enh enhancements of a weapon: each +1 to the lower of hit and damage.
static func _enhance(weap: Thing, enh: int) -> void:
	var p := GuildCatalog.enhanced(weap.o_hplus, weap.o_dplus, maxi(0, enh))
	weap.o_hplus = p.x
	weap.o_dplus = p.y


static func _int(d: Variant, key: String, def: int) -> int:
	if d is Dictionary and d.has(key) and (d[key] is int or d[key] is float):
		return int(d[key])
	return def


static func _list(d: Dictionary, key: String) -> Array:
	return d[key] if d.has(key) and d[key] is Array else []
