## The Fighters' Guild: the Quartermaster's stores, as rules (docs/GUILD.md).
##
## No UI here. The Guild screen (guild_screen.gd) shows offers() and calls buy()
## and refund(); godot/tests/guild_test.gd tests the rules. The loadout() it
## produces is what Loadout.apply() puts into the hero's starting pack.
##
## Rules:
## - Everything is paid from the coffers (HallOfFame.coffers()); spent() never
##   exceeds them. What is not spent is not kept.
## - Everything can be returned for its full price until the student descends,
##   except an identification: it is final.
## - The pack: 23 slots plus those bought, counted the way Pack.pack_room() counts:
##   one per potion, scroll and ration, one per other item, one per stack of darts,
##   shuriken or daggers; extra arrows join the issued stack. The issued kit takes
##   5. A pack slot can be returned only while the purchases still fit.
## - Identifying a potion or a scroll names one random unknown kind, weighted by
##   dungeon frequency. The draws come from a RandomNumberGenerator seeded from a
##   hash of the Hall of Fame file, one stream per category: the same Hall of Fame
##   always names the same kinds in the same order, so leaving and coming back
##   cannot re-roll them. They change when the Hall of Fame does.
class_name GuildShop
extends RefCounted

const C := preload("res://guild/catalog.gd")	## GuildCatalog

## Why a purchase or a return was refused ("" when it was done).
const DONE := ""
const NO_GOLD := "gold"		## the coffers can't pay for it
const NO_ROOM := "room"		## the pack can't hold it
const AT_MAX := "max"		## it goes no further
const FINAL := "final"		## an identification is not taken back
const NONE := "none"		## nothing of the kind to return
const ISSUED := "issued"	## the issued kit is not returned
const ALREADY := "already"	## that is the student's choice already
const ALL_KNOWN := "known"	## every kind is identified already
const IN_USE := "in use"	## the pack slot holds purchases
const NO_SUCH := "no such"	## not an offer

## The sections of the stores, in screen order (keys 1-8).
const SECTIONS: Array[String] = ["Training", "Arms", "Armour", "Rings", "Wands", "Potions",
	"Scrolls", "Stores"]

var hall: HallOfFame
var coffers := 0

## Purchases.
var strength := 0		## +1 strength each
var hit_points := 0		## +2 max hit points each
var weapon := C.WEAPON_ISSUED	## the kind of the student's weapon
var weapon_enh := 0
var bow_enh := 0
var spare_weapons: Array = []	## {"which", "enh"}, in purchase order
var armor := C.ARMOR_ISSUED	## the kind of the student's armour
var armor_enh := 0
var spare_armors: Array = []	## {"which", "enh"}
var rings: Array = []		## {"which", "enh"}: enh is +N on a bonus ring, polishes on adornment
var sticks: Array = []		## {"which", "enh"}: enh is +2 charges each
var pot_known: Array[bool] = []	## identified kinds
var pot_ids := 0		## identifications bought (final)
var pot_count: Array[int] = []	## potions bought, per kind
var scr_known: Array[bool] = []
var scr_ids := 0
var scr_count: Array[int] = []
var food := 0			## rations
var missiles: Array[int] = []	## purchases per row of GuildCatalog.MISSILES
var slots := 0			## pack slots
## The kind the last identification named (-1: none yet).
var last_named := -1

var _pot_rng := RandomNumberGenerator.new()
var _scr_rng := RandomNumberGenerator.new()


func _init(h: HallOfFame = null) -> void:
	hall = h if h != null else HallOfFame.new()
	coffers = hall.coffers()
	pot_known.resize(C.POTIONS.size())
	pot_count.resize(C.POTIONS.size())
	scr_known.resize(C.SCROLLS.size())
	scr_count.resize(C.SCROLLS.size())
	missiles.resize(C.MISSILES.size())
	_pot_rng.seed = HallOfFame.fnv("potions".to_utf8_buffer(), hall.digest)
	_scr_rng.seed = HallOfFame.fnv("scrolls".to_utf8_buffer(), hall.digest)


# ---- the ledger ---------------------------------------------------------------

## Gold spent so far: every purchase at its price, as if bought in order.
func spent() -> int:
	var t := C.grow_total(C.STR_PRICE, 2, 1, strength)
	t += C.grow_total(C.HP_PRICE, 2, 1, hit_points)
	t += C.WEAPONS[weapon][2] + C.grow_total(C.WEAPON_ENH_PRICE, 2, 1, weapon_enh)
	t += C.grow_total(C.WEAPON_ENH_PRICE, 2, 1, bow_enh)
	for w in spare_weapons:
		t += C.WEAPONS[w.which][3] + C.grow_total(C.WEAPON_ENH_PRICE, 2, 1, w.enh)
	t += C.ARMORS[armor][2] + C.grow_total(C.ARMOR_ENH_PRICE, 2, 1, armor_enh)
	for a in spare_armors:
		t += C.ARMORS[a.which][3] + C.grow_total(C.ARMOR_ENH_PRICE, 2, 1, a.enh)
	for which in C.RINGS.size():
		t += C.grow_total(C.RINGS[which][2], C.RING_COPY_FACTOR, 1, _owned(rings, which))
	for r in rings:
		if r.which == C.RING_ADORNMENT:
			t += C.grow_total(C.POLISH_PRICE, 2, 1, r.enh)
		else:
			t += C.grow_total(C.RING_ENH_PRICE, 2, 1, r.enh)
	for which in C.STICKS.size():
		t += C.grow_total(C.STICKS[which][2], C.STICK_COPY_FACTOR, 1, _owned(sticks, which))
	for s in sticks:
		t += C.grow_total(C.CHARGE_PRICE, 2, 1, s.enh)
	t += C.IDENTIFY_PRICE * (pot_ids + scr_ids)
	for i in C.POTIONS.size():
		t += C.grow_total(C.POTIONS[i][2], 2, 1, pot_count[i])
	for i in C.SCROLLS.size():
		t += C.grow_total(C.SCROLLS[i][2], 2, 1, scr_count[i])
	t += C.grow_total(C.FOOD_PRICE, C.FOOD_NUM, C.FOOD_DEN, food)
	for i in C.MISSILES.size():
		t += C.MISSILES[i][2] * missiles[i]
	t += C.grow_total(C.PACK_PRICE, C.PACK_NUM, C.PACK_DEN, slots)
	return t


## Gold left in the coffers.
func left() -> int:
	return coffers - spent()


## Pack slots the purchases and the issued kit take.
func pack_load() -> int:
	var n := C.PACK_ISSUED + spare_weapons.size() + spare_armors.size() + rings.size() \
		+ sticks.size() + food
	for c in pot_count:
		n += c
	for c in scr_count:
		n += c
	for i in C.MISSILES.size():
		if missiles[i] > 0 and C.MISSILES[i][0] != C.ARROW:
			n += 1
	return n


## Pack slots.
func pack_size() -> int:
	return C.PACK_START + slots


## Strength and max hit points after training.
func strength_now() -> int:
	return C.STR_START + strength


func hp_now() -> int:
	return C.HP_START + C.HP_STEP * hit_points


# ---- buying and returning -----------------------------------------------------

## Buy one of an offer (an id from offers()). Returns DONE or why not.
func buy(id: String) -> String:
	var kind := id.get_slice(":", 0)
	var arg := id.get_slice(":", 1)
	var n := int(arg) if arg.is_valid_int() else -1
	match kind:
		"str":
			if strength_now() >= C.STR_MAX:
				return AT_MAX
			return _pay(C.grow(C.STR_PRICE, 2, 1, strength), 0, "strength")
		"hp":
			return _pay(C.grow(C.HP_PRICE, 2, 1, hit_points), 0, "hit_points")
		"sw":
			if not C.WEAPON_START_ORDER.has(n):
				return NO_SUCH
			if n == weapon:
				return ALREADY
			if C.WEAPONS[n][2] - C.WEAPONS[weapon][2] > left():
				return NO_GOLD
			weapon = n
			return DONE
		"xw":
			if not C.WEAPON_SPARE_ORDER.has(n):
				return NO_SUCH
			var why := _check(C.WEAPONS[n][3], 1)
			if why == DONE:
				spare_weapons.append({"which": n, "enh": 0})
			return why
		"ew":
			if arg == "you":
				return _pay(C.grow(C.WEAPON_ENH_PRICE, 2, 1, weapon_enh), 0, "weapon_enh")
			if arg == "bow":
				return _pay(C.grow(C.WEAPON_ENH_PRICE, 2, 1, bow_enh), 0, "bow_enh")
			return _enhance(spare_weapons, n, C.WEAPON_ENH_PRICE)
		"sa":
			if not C.ARMOR_ORDER.has(n):
				return NO_SUCH
			if n == armor:
				return ALREADY
			if C.ARMORS[n][2] - C.ARMORS[armor][2] > left():
				return NO_GOLD
			armor = n
			return DONE
		"xa":
			if not C.ARMOR_ORDER.has(n):
				return NO_SUCH
			var why := _check(C.ARMORS[n][3], 1)
			if why == DONE:
				spare_armors.append({"which": n, "enh": 0})
			return why
		"ea":
			if arg == "you":
				return _pay(C.grow(C.ARMOR_ENH_PRICE, 2, 1, armor_enh), 0, "armor_enh")
			return _enhance(spare_armors, n, C.ARMOR_ENH_PRICE)
		"rg":
			if n < 0 or n >= C.RINGS.size():
				return NO_SUCH
			var why := _check(C.grow(C.RINGS[n][2], C.RING_COPY_FACTOR, 1, _owned(rings, n)), 1)
			if why == DONE:
				rings.append({"which": n, "enh": 0})
			return why
		"er":
			if n < 0 or n >= rings.size() or not C.is_bonus_ring(rings[n].which):
				return NO_SUCH
			return _enhance(rings, n, C.RING_ENH_PRICE)
		"pr":
			if n < 0 or n >= rings.size() or rings[n].which != C.RING_ADORNMENT:
				return NO_SUCH
			if rings[n].enh >= C.POLISH_MAX:
				return AT_MAX
			return _enhance(rings, n, C.POLISH_PRICE)
		"wd":
			if n < 0 or n >= C.STICKS.size():
				return NO_SUCH
			var why := _check(C.grow(C.STICKS[n][2], C.STICK_COPY_FACTOR, 1, _owned(sticks, n)), 1)
			if why == DONE:
				sticks.append({"which": n, "enh": 0})
			return why
		"ec":
			return _enhance(sticks, n, C.CHARGE_PRICE)
		"ip":
			return _identify(true)
		"is":
			return _identify(false)
		"bp":
			if n < 0 or n >= C.POTIONS.size() or not pot_known[n]:
				return NO_SUCH
			var why := _check(C.grow(C.POTIONS[n][2], 2, 1, pot_count[n]), 1)
			if why == DONE:
				pot_count[n] += 1
			return why
		"bs":
			if n < 0 or n >= C.SCROLLS.size() or not scr_known[n]:
				return NO_SUCH
			var why := _check(C.grow(C.SCROLLS[n][2], 2, 1, scr_count[n]), 1)
			if why == DONE:
				scr_count[n] += 1
			return why
		"fd":
			return _pay(C.grow(C.FOOD_PRICE, C.FOOD_NUM, C.FOOD_DEN, food), 1, "food")
		"ms":
			if n < 0 or n >= C.MISSILES.size():
				return NO_SUCH
			var room := 1 if missiles[n] == 0 and C.MISSILES[n][0] != C.ARROW else 0
			var why := _check(C.MISSILES[n][2], room)
			if why == DONE:
				missiles[n] += 1
			return why
		"pk":
			if pack_size() >= C.PACK_MAX:
				return AT_MAX
			return _pay(C.grow(C.PACK_PRICE, C.PACK_NUM, C.PACK_DEN, slots), 0, "slots")
	return NO_SUCH


## Return one of an offer for its full price. Returns DONE or why not.
func refund(id: String) -> String:
	var kind := id.get_slice(":", 0)
	var arg := id.get_slice(":", 1)
	var n := int(arg) if arg.is_valid_int() else -1
	match kind:
		"str":
			return _undo("strength")
		"hp":
			return _undo("hit_points")
		"sw":
			if n != weapon:
				return NONE
			if n == C.WEAPON_ISSUED:
				return ISSUED
			weapon = C.WEAPON_ISSUED
			return DONE
		"xw":
			return _drop_last(spare_weapons, n)
		"ew":
			if arg == "you":
				return _undo("weapon_enh")
			if arg == "bow":
				return _undo("bow_enh")
			return _unenhance(spare_weapons, n)
		"sa":
			if n != armor:
				return NONE
			if n == C.ARMOR_ISSUED:
				return ISSUED
			armor = C.ARMOR_ISSUED
			return DONE
		"xa":
			return _drop_last(spare_armors, n)
		"ea":
			if arg == "you":
				return _undo("armor_enh")
			return _unenhance(spare_armors, n)
		"rg":
			return _drop_last(rings, n)
		"er", "pr":
			return _unenhance(rings, n)
		"wd":
			return _drop_last(sticks, n)
		"ec":
			return _unenhance(sticks, n)
		"ip", "is":
			return FINAL
		"bp":
			if n < 0 or n >= pot_count.size() or pot_count[n] == 0:
				return NONE
			pot_count[n] -= 1
			return DONE
		"bs":
			if n < 0 or n >= scr_count.size() or scr_count[n] == 0:
				return NONE
			scr_count[n] -= 1
			return DONE
		"fd":
			return _undo("food")
		"ms":
			if n < 0 or n >= missiles.size() or missiles[n] == 0:
				return NONE
			missiles[n] -= 1
			return DONE
		"pk":
			if slots == 0:
				return NONE
			if pack_load() > pack_size() - 1:
				return IN_USE
			slots -= 1
			return DONE
	return NO_SUCH


## DONE if the coffers can pay price and the pack can take room more slots.
func _check(price: int, room: int) -> String:
	if price > left():
		return NO_GOLD
	if pack_load() + room > pack_size():
		return NO_ROOM
	return DONE


## Buy one more of a counted purchase (a member variable).
func _pay(price: int, room: int, counter: String) -> String:
	var why := _check(price, room)
	if why == DONE:
		set(counter, int(get(counter)) + 1)
	return why


func _undo(counter: String) -> String:
	if int(get(counter)) == 0:
		return NONE
	set(counter, int(get(counter)) - 1)
	return DONE


## +1 enhancement of item i of a list ({"which", "enh"}): base * 2^enh.
func _enhance(list: Array, i: int, base: int) -> String:
	if i < 0 or i >= list.size():
		return NO_SUCH
	var why := _check(C.grow(base, 2, 1, list[i].enh), 0)
	if why == DONE:
		list[i].enh += 1
	return why


func _unenhance(list: Array, i: int) -> String:
	if i < 0 or i >= list.size():
		return NO_SUCH
	if list[i].enh == 0:
		return NONE
	list[i].enh -= 1
	return DONE


## Return the last one bought of a kind, with its enhancements.
func _drop_last(list: Array, which: int) -> String:
	for i in range(list.size() - 1, -1, -1):
		if list[i].which == which:
			list.remove_at(i)
			return DONE
	return NONE


## How many of a kind a list holds.
static func _owned(list: Array, which: int) -> int:
	var n := 0
	for e in list:
		if e.which == which:
			n += 1
	return n


## Name one random unknown potion (or scroll) kind, weighted by dungeon frequency.
func _identify(potions: bool) -> String:
	var table: Array = C.POTIONS if potions else C.SCROLLS
	var known: Array[bool] = pot_known if potions else scr_known
	var weight := 0
	for i in table.size():
		if not known[i]:
			weight += table[i][1]
	if weight == 0:
		return ALL_KNOWN
	if C.IDENTIFY_PRICE > left():
		return NO_GOLD
	var r := (_pot_rng if potions else _scr_rng).randi_range(0, weight - 1)
	for i in table.size():
		if known[i]:
			continue
		r -= table[i][1]
		if r < 0:
			known[i] = true
			last_named = i
			break
	if potions:
		pot_ids += 1
	else:
		scr_ids += 1
	return DONE


# ---- what the stores offer ----------------------------------------------------

## The lines of a section, in screen order. A line is a Dictionary:
## - an offer: "id" (for buy/refund), "label", "info" (what the student has),
##   "note", "price" (of the next one; 0 is free) and "status" (when it cannot be
##   bought: "max", "yours", ...; else ""), "mark" ("*" on the student's choice);
## - a heading: "head"; a line of text: "text".
func offers(section: int) -> Array:
	var out: Array = []
	match section:
		0:
			out.append(_offer("str", "Strength", _change(C.STR_START, strength_now()), "next +1",
				C.grow(C.STR_PRICE, 2, 1, strength), "max" if strength_now() >= C.STR_MAX else ""))
			out.append(_offer("hp", "Hit points", _change(C.HP_START, hp_now()),
				"next +%d" % C.HP_STEP, C.grow(C.HP_PRICE, 2, 1, hit_points), ""))
			out.append({"text": ""})
			out.append({"text": "Every student is issued some food, a +1 ring mail, a +1,+1 mace,"})
			out.append({"text": "a +1 short bow, 25 to 39 arrows and a pack of 23 slots."})
			out.append({"text": "Anything more is paid for from the coffers, here and now."})
		1:
			out.append({"head": "Your weapon: it comes +1,+1 (a lighter one costs nothing)"})
			for w in C.WEAPON_START_ORDER:
				var o := _offer("sw:%d" % w, C.title(C.WEAPONS[w][0]), "damage " + C.WEAPONS[w][4],
					"", C.WEAPONS[w][2], "yours" if w == weapon else "")
				o.mark = "*" if w == weapon else ""
				out.append(o)
			out.append({"head": "Spare weapons, +0,+0"})
			for w in C.WEAPON_SPARE_ORDER:
				out.append(_offer("xw:%d" % w, C.title(C.WEAPONS[w][0]), "damage " + C.WEAPONS[w][4],
					_have(_owned(spare_weapons, w)), C.WEAPONS[w][3], ""))
			out.append({"head": "The smithy: +1 to the lower of hit and damage"})
			out.append(_weapon_enh("ew:you", C.title(C.WEAPONS[weapon][0]) + " (yours)", 1, 1,
				weapon_enh))
			out.append(_weapon_enh("ew:bow", "Short bow", 1, 0, bow_enh))
			for i in spare_weapons.size():
				out.append(_weapon_enh("ew:%d" % i, C.title(C.WEAPONS[spare_weapons[i].which][0])
					+ " (spare)", 0, 0, spare_weapons[i].enh))
		2:
			out.append({"head": "Your armour: it comes +1 (a lighter one costs nothing)"})
			for a in C.ARMOR_ORDER:
				var o := _offer("sa:%d" % a, C.title(C.ARMORS[a][0]),
					"protection %d" % (11 - C.A_CLASS[a]), "", C.ARMORS[a][2], "yours" if a == armor else "")
				o.mark = "*" if a == armor else ""
				out.append(o)
			out.append({"head": "Spare armour, +0"})
			for a in C.ARMOR_ORDER:
				out.append(_offer("xa:%d" % a, C.title(C.ARMORS[a][0]),
					"protection %d" % (10 - C.A_CLASS[a]), _have(_owned(spare_armors, a)),
					C.ARMORS[a][3], ""))
			out.append({"head": "The armourer: -1 armour class"})
			out.append(_armor_enh("ea:you", C.title(C.ARMORS[armor][0]) + " (yours)", 1, armor_enh))
			for i in spare_armors.size():
				out.append(_armor_enh("ea:%d" % i, C.title(C.ARMORS[spare_armors[i].which][0])
					+ " (spare)", 0, spare_armors[i].enh))
		3:
			out.append({"head": "Rings, known; the second of a kind costs four times as much"})
			for r in _by_price(C.RINGS):
				var o := _offer("rg:%d" % r, C.title(C.RINGS[r][0]), _have(_owned(rings, r)), "",
					C.grow(C.RINGS[r][2], C.RING_COPY_FACTOR, 1, _owned(rings, r)), "")
				if C.is_cursed_ring(r):
					o.note = "cursed"
				elif C.is_bonus_ring(r):
					o.note = "comes +1"
				out.append(o)
			var head := false
			for i in rings.size():
				if C.is_bonus_ring(rings[i].which):
					if not head:
						out.append({"head": "The enchanter: +1 to a ring"})
						head = true
					out.append(_offer("er:%d" % i, C.title(C.RINGS[rings[i].which][0]),
						_change_s("+%d" % 1, "+%d" % (1 + rings[i].enh)), "next +1",
						C.grow(C.RING_ENH_PRICE, 2, 1, rings[i].enh), ""))
			head = false
			for i in rings.size():
				if rings[i].which == C.RING_ADORNMENT:
					if not head:
						out.append({"head": "Polishing: a winner sells the ring for twice as much"})
						head = true
					var e: int = rings[i].enh
					out.append(_offer("pr:%d" % i, "Adornment",
						_change_s("worth x1", "x%d" % (1 << e)), "next x2",
						C.grow(C.POLISH_PRICE, 2, 1, e), "max" if e >= C.POLISH_MAX else ""))
		4:
			out.append({"head": "Wands and staves, known: %d charges (light %d)" % [C.STICK_CHARGES,
				C.STICK_LIGHT_CHARGES]})
			for s in _by_price(C.STICKS):
				out.append(_offer("wd:%d" % s, C.title(C.STICKS[s][0]), _have(_owned(sticks, s)), "",
					C.grow(C.STICKS[s][2], C.STICK_COPY_FACTOR, 1, _owned(sticks, s)), ""))
			if not sticks.is_empty():
				out.append({"head": "Recharging: +%d charges" % C.CHARGE_STEP})
			for i in sticks.size():
				var base := charges_of(sticks[i].which, 0)
				out.append(_offer("ec:%d" % i, C.title(C.STICKS[sticks[i].which][0]),
					_change(base, charges_of(sticks[i].which, sticks[i].enh)) + " charges",
					"next +%d" % C.CHARGE_STEP, C.grow(C.CHARGE_PRICE, 2, 1, sticks[i].enh), ""))
		5, 6:
			var potions := section == 5
			var table: Array = C.POTIONS if potions else C.SCROLLS
			var known: Array[bool] = pot_known if potions else scr_known
			var count: Array[int] = pot_count if potions else scr_count
			var nk := known.count(true)
			out.append(_offer("ip" if potions else "is", "Identify a %s" % ("potion" if potions else "scroll"),
				"%d of %d known" % [nk, table.size()], "final", C.IDENTIFY_PRICE,
				"all known" if nk == table.size() else ""))
			if potions:
				out.append({"text": "The alchemist names one unknown kind, the common ones more often."})
				out.append({"text": "No bottle comes with the name, and a name is not taken back."})
			else:
				out.append({"text": "The scribe reads out one unknown kind, the common ones more often."})
				out.append({"text": "No scroll comes with the reading, and a reading is not taken back."})
			if nk > 0:
				out.append({"head": "Known %s, for sale" % ("potions" if potions else "scrolls")})
			for k in _by_price(table):
				if known[k]:
					out.append(_offer(("bp:%d" if potions else "bs:%d") % k, C.title(table[k][0]),
						_have(count[k]), "", C.grow(table[k][2], 2, 1, count[k]), ""))
		7:
			out.append(_offer("fd", "Food ration", "have " + _change(1, 1 + food), "next +1",
				C.grow(C.FOOD_PRICE, C.FOOD_NUM, C.FOOD_DEN, food), ""))
			for i in C.MISSILES.size():
				var m: Array = C.MISSILES[i]
				var info := ""
				if missiles[i] > 0:
					info = ("+%d" if m[0] == C.ARROW else "have %d") % (m[1] * missiles[i])
				out.append(_offer("ms:%d" % i, m[3], info, "", m[2], ""))
			out.append(_offer("pk", "A bigger pack", _change(C.PACK_START, pack_size()) + " slots",
				"next +1", C.grow(C.PACK_PRICE, C.PACK_NUM, C.PACK_DEN, slots),
				"max" if pack_size() >= C.PACK_MAX else ""))
			out.append({"text": ""})
			out.append({"text": "Extra arrows go onto your quiver. Darts, shuriken and daggers"})
			out.append({"text": "make one stack each. A bigger pack holds one more thing."})
	return out


## Charges of a wand or staff the Guild sells.
static func charges_of(which: int, enh: int) -> int:
	var base := C.STICK_LIGHT_CHARGES if which == C.STICK_LIGHT else C.STICK_CHARGES
	return base + C.CHARGE_STEP * enh


func _offer(id: String, label: String, info: String, note: String, price: int,
		status: String) -> Dictionary:
	return {"id": id, "label": label, "info": info, "note": note, "price": price,
		"status": status, "mark": ""}


func _weapon_enh(id: String, label: String, hplus: int, dplus: int, enh: int) -> Dictionary:
	var now := C.enhanced(hplus, dplus, enh)
	var nxt := C.enhanced(now.x, now.y, 1)
	return _offer(id, label, _change_s(C.plus_str(hplus, dplus), C.plus_str(now.x, now.y)),
		"next +1 " + ("dmg" if nxt.y > now.y else "hit"), C.grow(C.WEAPON_ENH_PRICE, 2, 1, enh), "")


func _armor_enh(id: String, label: String, plus: int, enh: int) -> Dictionary:
	return _offer(id, label, _change_s("+%d" % plus, "+%d" % (plus + enh)), "next +1",
		C.grow(C.ARMOR_ENH_PRICE, 2, 1, enh), "")


## "16" or "16 -> 18"
static func _change(base: int, now: int) -> String:
	return _change_s(str(base), str(now))


static func _change_s(base: String, now: String) -> String:
	return base if base == now else "%s -> %s" % [base, now]


static func _have(n: int) -> String:
	return "have %d" % n if n > 0 else ""


## The kinds of a table, dearest first (ties in table order).
static func _by_price(table: Array) -> Array[int]:
	var order: Array[int] = []
	for i in table.size():
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return table[a][2] > table[b][2] or (table[a][2] == table[b][2] and a < b))
	return order


# ---- the loadout --------------------------------------------------------------

## What the student takes into the dungeon (the schema is in loadout.gd).
func loadout() -> Dictionary:
	var l := {}
	l["maxpack"] = pack_size()
	l["str"] = strength
	l["hp"] = C.HP_STEP * hit_points
	if weapon != C.WEAPON_ISSUED or weapon_enh > 0:
		l["weapon"] = {"which": weapon, "enh": weapon_enh}
	if bow_enh > 0:
		l["bow"] = {"enh": bow_enh}
	if armor != C.ARMOR_ISSUED or armor_enh > 0:
		l["armor"] = {"which": armor, "enh": armor_enh}
	l["weapons"] = spare_weapons.duplicate(true)
	l["armors"] = spare_armors.duplicate(true)
	l["rings"] = rings.duplicate(true)
	l["sticks"] = sticks.duplicate(true)
	l["arrows"] = 0
	var ms: Array = []
	for i in C.MISSILES.size():
		var m: Array = C.MISSILES[i]
		if missiles[i] == 0:
			continue
		if m[0] == C.ARROW:
			l["arrows"] = m[1] * missiles[i]
		else:
			ms.append({"which": m[0], "count": m[1] * missiles[i]})
	l["missiles"] = ms
	l["potions"] = _counted(pot_count)
	l["scrolls"] = _counted(scr_count)
	l["food"] = food
	l["know_potions"] = _known(pot_known)
	l["know_scrolls"] = _known(scr_known)
	return l


static func _counted(count: Array[int]) -> Array:
	var out: Array = []
	for i in count.size():
		if count[i] > 0:
			out.append({"which": i, "count": count[i]})
	return out


static func _known(known: Array[bool]) -> Array:
	var out: Array = []
	for i in known.size():
		if known[i]:
			out.append(i)
	return out
