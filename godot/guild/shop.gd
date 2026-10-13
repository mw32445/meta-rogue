## The Fighters' Guild: the Quartermaster's stores, as rules (docs/GUILD.md).
##
## No UI here. The Guild screen (guild_screen.gd) shows offers() and calls buy()
## and refund(); godot/tests/guild_test.gd tests the rules. The loadout() it
## produces is what Loadout.apply() puts into the hero's starting pack.
##
## Every price and amount comes from the GuildPrices it is given (the price list,
## godot/guild_prices.txt): a line's price for k = how many of it were bought
## already. The shops of the tests take the built-in list.
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
const NEEDS := "needs"		## a skill needs another first
const NEEDED := "needed"	## another skill needs this one

## The sections of the stores, in screen order (keys 1-9).
const SECTIONS: Array[String] = ["Train", "Arms", "Armour", "Rings", "Wands", "Potions",
	"Scrolls", "Stores", "Skills"]
## The section of the skills.
const SKILLS_SECTION := 8

var hall: HallOfFame
var prices: GuildPrices
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
var missiles: Array[int] = []	## purchases per line of GuildCatalog.MISSILES
var slots := 0			## pack slots
var skills := {}		## skill name (GuildCatalog.SKILLS) -> level
## The kind the last identification named (-1: none yet).
var last_named := -1

var _pot_rng := RandomNumberGenerator.new()
var _scr_rng := RandomNumberGenerator.new()


## A shop for a Hall of Fame (none: an empty one) with a price list (none: the
## built-in one).
func _init(h: HallOfFame = null, p: GuildPrices = null) -> void:
	hall = h if h != null else HallOfFame.new()
	prices = p if p != null else GuildPrices.defaults()
	coffers = hall.coffers(prices)
	pot_known.resize(C.POTIONS.size())
	pot_count.resize(C.POTIONS.size())
	scr_known.resize(C.SCROLLS.size())
	scr_count.resize(C.SCROLLS.size())
	missiles.resize(C.MISSILES.size())
	_pot_rng.seed = HallOfFame.fnv("potions".to_utf8_buffer(), hall.digest)
	_scr_rng.seed = HallOfFame.fnv("scrolls".to_utf8_buffer(), hall.digest)


# ---- the ledger ---------------------------------------------------------------

## Gold spent so far: every purchase at its price, as if bought in order (so a
## return gives back exactly what the purchase cost).
func spent() -> int:
	var t := _total("training", "strength", strength)
	t += _total("training", "hit points", hit_points)
	t += _swap("your weapon", C.WEAPONS, weapon, C.WEAPON_ISSUED)
	t += _total("enhancing", "weapon", weapon_enh) + _total("enhancing", "weapon", bow_enh)
	for w in C.WEAPON_SPARE_ORDER:
		t += _total("spare weapons", C.WEAPONS[w][0], _owned(spare_weapons, w))
	for w in spare_weapons:
		t += _total("enhancing", "weapon", w.enh)
	t += _swap("your armour", C.ARMORS, armor, C.ARMOR_ISSUED)
	t += _total("enhancing", "armour", armor_enh)
	for a in C.ARMOR_ORDER:
		t += _total("spare armour", C.ARMORS[a][0], _owned(spare_armors, a))
	for a in spare_armors:
		t += _total("enhancing", "armour", a.enh)
	for which in C.RINGS.size():
		t += _total("rings", C.RINGS[which][0], _owned(rings, which))
	for r in rings:
		t += _total("enhancing", "polish" if r.which == C.RING_ADORNMENT else "ring", r.enh)
	for which in C.STICKS.size():
		t += _total("wands", C.STICKS[which][0], _owned(sticks, which))
	for st in sticks:
		t += _total("enhancing", "wand charges", st.enh)
	t += _total("potions", "identify", pot_ids) + _total("scrolls", "identify", scr_ids)
	for i in C.POTIONS.size():
		t += _total("potions", C.POTIONS[i][0], pot_count[i])
	for i in C.SCROLLS.size():
		t += _total("scrolls", C.SCROLLS[i][0], scr_count[i])
	t += _total("stores", "food", food)
	for i in C.MISSILES.size():
		t += _total("stores", C.MISSILES[i][1], missiles[i])
	t += _total("stores", "pack slot", slots)
	for sk in C.SKILLS:
		t += _total("skills", sk[0], skill_level(sk[0]))
	return t


## What the first n of a line cost: its prices for k = 0 to n - 1.
func _total(section: String, name: String, n: int) -> int:
	var t := 0
	for k in n:
		t += prices.price(section, name, k)
	return t


## The student's weapon (or armour) costs its price less the issued one's.
func _swap(section: String, table: Array, which: int, issued: int) -> int:
	return prices.price(section, table[which][0]) - prices.price(section, table[issued][0])


## The next spare of a kind: k is how many of it the list holds.
func _spare_price(section: String, table: Array, list: Array, which: int) -> int:
	return prices.price(section, table[which][0], _owned(list, which))


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
	return C.HP_START + hp_step() * hit_points


## Max hit points per purchase.
func hp_step() -> int:
	return prices.amount("training", "hit points per purchase")


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
			return _pay(prices.price("training", "strength", strength), 0, "strength")
		"hp":
			return _pay(prices.price("training", "hit points", hit_points), 0, "hit_points")
		"sw":
			if not C.WEAPON_START_ORDER.has(n):
				return NO_SUCH
			if n == weapon:
				return ALREADY
			if _swap("your weapon", C.WEAPONS, n, weapon) > left():
				return NO_GOLD
			weapon = n
			return DONE
		"xw":
			if not C.WEAPON_SPARE_ORDER.has(n):
				return NO_SUCH
			var why := _check(_spare_price("spare weapons", C.WEAPONS, spare_weapons, n), 1)
			if why == DONE:
				spare_weapons.append({"which": n, "enh": 0})
			return why
		"ew":
			if arg == "you":
				return _pay(prices.price("enhancing", "weapon", weapon_enh), 0, "weapon_enh")
			if arg == "bow":
				return _pay(prices.price("enhancing", "weapon", bow_enh), 0, "bow_enh")
			return _enhance(spare_weapons, n, "weapon")
		"sa":
			if not C.ARMOR_ORDER.has(n):
				return NO_SUCH
			if n == armor:
				return ALREADY
			if _swap("your armour", C.ARMORS, n, armor) > left():
				return NO_GOLD
			armor = n
			return DONE
		"xa":
			if not C.ARMOR_ORDER.has(n):
				return NO_SUCH
			var why := _check(_spare_price("spare armour", C.ARMORS, spare_armors, n), 1)
			if why == DONE:
				spare_armors.append({"which": n, "enh": 0})
			return why
		"ea":
			if arg == "you":
				return _pay(prices.price("enhancing", "armour", armor_enh), 0, "armor_enh")
			return _enhance(spare_armors, n, "armour")
		"rg":
			if n < 0 or n >= C.RINGS.size():
				return NO_SUCH
			var why := _check(prices.price("rings", C.RINGS[n][0], _owned(rings, n)), 1)
			if why == DONE:
				rings.append({"which": n, "enh": 0})
			return why
		"er":
			if n < 0 or n >= rings.size() or not C.is_bonus_ring(rings[n].which):
				return NO_SUCH
			return _enhance(rings, n, "ring")
		"pr":
			if n < 0 or n >= rings.size() or rings[n].which != C.RING_ADORNMENT:
				return NO_SUCH
			if rings[n].enh >= polish_max():
				return AT_MAX
			return _enhance(rings, n, "polish")
		"wd":
			if n < 0 or n >= C.STICKS.size():
				return NO_SUCH
			var why := _check(prices.price("wands", C.STICKS[n][0], _owned(sticks, n)), 1)
			if why == DONE:
				sticks.append({"which": n, "enh": 0})
			return why
		"ec":
			return _enhance(sticks, n, "wand charges")
		"ip":
			return _identify(true)
		"is":
			return _identify(false)
		"bp":
			if n < 0 or n >= C.POTIONS.size() or not pot_known[n]:
				return NO_SUCH
			var why := _check(prices.price("potions", C.POTIONS[n][0], pot_count[n]), 1)
			if why == DONE:
				pot_count[n] += 1
			return why
		"bs":
			if n < 0 or n >= C.SCROLLS.size() or not scr_known[n]:
				return NO_SUCH
			var why := _check(prices.price("scrolls", C.SCROLLS[n][0], scr_count[n]), 1)
			if why == DONE:
				scr_count[n] += 1
			return why
		"fd":
			return _pay(prices.price("stores", "food", food), 1, "food")
		"ms":
			if n < 0 or n >= C.MISSILES.size():
				return NO_SUCH
			var room := 1 if missiles[n] == 0 and C.MISSILES[n][0] != C.ARROW else 0
			var why := _check(prices.price("stores", C.MISSILES[n][1], missiles[n]), room)
			if why == DONE:
				missiles[n] += 1
			return why
		"pk":
			if pack_size() >= C.PACK_MAX:
				return AT_MAX
			return _pay(prices.price("stores", "pack slot", slots), 0, "slots")
		"sk":
			if n < 0 or n >= C.SKILLS.size():
				return NO_SUCH
			var sk: Array = C.SKILLS[n]
			var have := skill_level(sk[0])
			if have > 0 and not sk[5]:
				return ALREADY
			if sk[4] != "" and skill_level(sk[4]) == 0:
				return NEEDS
			var why := _check(prices.price("skills", sk[0], have), 0)
			if why == DONE:
				skills[sk[0]] = have + 1
			return why
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
			if _swap("your weapon", C.WEAPONS, C.WEAPON_ISSUED, n) > left():
				return NO_GOLD	# a price list where the issued one is dearer
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
			if _swap("your armour", C.ARMORS, C.ARMOR_ISSUED, n) > left():
				return NO_GOLD
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
		"sk":
			if n < 0 or n >= C.SKILLS.size():
				return NO_SUCH
			var name: String = C.SKILLS[n][0]
			if skill_level(name) == 0:
				return NONE
			if needed_by(name) != "":
				return NEEDED
			skills[name] = skill_level(name) - 1
			if skills[name] == 0:
				skills.erase(name)
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


## +1 enhancement of item i of a list ({"which", "enh"}), at the price of line
## name of [enhancing] with k = its enhancements.
func _enhance(list: Array, i: int, name: String) -> String:
	if i < 0 or i >= list.size():
		return NO_SUCH
	var why := _check(prices.price("enhancing", name, list[i].enh), 0)
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
	var ids := pot_ids if potions else scr_ids
	if prices.price("potions" if potions else "scrolls", "identify", ids) > left():
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
## - a heading: "head".
func offers(section: int) -> Array:
	var out: Array = []
	var p := prices
	match section:
		0:
			out.append(_offer("str", "Strength", _change(C.STR_START, strength_now()), "next +1",
				p.price("training", "strength", strength),
				"max" if strength_now() >= C.STR_MAX else ""))
			out.append(_offer("hp", "Hit points", _change(C.HP_START, hp_now()),
				"next +%d" % hp_step(), p.price("training", "hit points", hit_points), ""))
		1:
			out.append({"head": "Your weapon"})
			for w in C.WEAPON_START_ORDER:
				var o := _offer("sw:%d" % w, C.title(C.WEAPONS[w][0]), "damage " + C.WEAPONS[w][2],
					"", p.price("your weapon", C.WEAPONS[w][0]), "yours" if w == weapon else "")
				o.mark = "*" if w == weapon else ""
				out.append(o)
			out.append({"head": "Spare weapons"})
			for w in C.WEAPON_SPARE_ORDER:
				out.append(_offer("xw:%d" % w, C.title(C.WEAPONS[w][0]), "damage " + C.WEAPONS[w][2],
					_have(_owned(spare_weapons, w)),
					_spare_price("spare weapons", C.WEAPONS, spare_weapons, w), ""))
			out.append({"head": "Enhance"})
			out.append(_weapon_enh("ew:you", C.title(C.WEAPONS[weapon][0]) + " (yours)", 1, 1,
				weapon_enh))
			out.append(_weapon_enh("ew:bow", "Short bow", 1, 0, bow_enh))
			for i in spare_weapons.size():
				out.append(_weapon_enh("ew:%d" % i, C.title(C.WEAPONS[spare_weapons[i].which][0])
					+ " (spare)", 0, 0, spare_weapons[i].enh))
		2:
			out.append({"head": "Your armour"})
			for a in C.ARMOR_ORDER:
				var o := _offer("sa:%d" % a, C.title(C.ARMORS[a][0]),
					"protection %d" % (11 - C.A_CLASS[a]), "",
					p.price("your armour", C.ARMORS[a][0]), "yours" if a == armor else "")
				o.mark = "*" if a == armor else ""
				out.append(o)
			out.append({"head": "Spare armour"})
			for a in C.ARMOR_ORDER:
				out.append(_offer("xa:%d" % a, C.title(C.ARMORS[a][0]),
					"protection %d" % (10 - C.A_CLASS[a]), _have(_owned(spare_armors, a)),
					_spare_price("spare armour", C.ARMORS, spare_armors, a), ""))
			out.append({"head": "Enhance"})
			out.append(_armor_enh("ea:you", C.title(C.ARMORS[armor][0]) + " (yours)", 1, armor_enh))
			for i in spare_armors.size():
				out.append(_armor_enh("ea:%d" % i, C.title(C.ARMORS[spare_armors[i].which][0])
					+ " (spare)", 0, spare_armors[i].enh))
		3:
			out.append({"head": "Rings"})
			for r in _by_price("rings", C.RINGS):
				var o := _offer("rg:%d" % r, C.title(C.RINGS[r][0]), _have(_owned(rings, r)), "",
					p.price("rings", C.RINGS[r][0], _owned(rings, r)), "")
				if C.is_cursed_ring(r):
					o.note = "cursed"
				elif C.is_bonus_ring(r):
					o.note = "comes +1"
				out.append(o)
			var head := false
			for i in rings.size():
				if C.is_bonus_ring(rings[i].which):
					if not head:
						out.append({"head": "Enhance"})
						head = true
					out.append(_offer("er:%d" % i, C.title(C.RINGS[rings[i].which][0]),
						_change_s("+%d" % 1, "+%d" % (1 + rings[i].enh)), "next +1",
						p.price("enhancing", "ring", rings[i].enh), ""))
			head = false
			for i in rings.size():
				if rings[i].which == C.RING_ADORNMENT:
					if not head:
						out.append({"head": "Polish"})
						head = true
					var e: int = rings[i].enh
					out.append(_offer("pr:%d" % i, "Adornment",
						_change_s("worth x1", "x%d" % (1 << e)), "next x2",
						p.price("enhancing", "polish", e), "max" if e >= polish_max() else ""))
		4:
			out.append({"head": "Wands and staves"})
			for st in _by_price("wands", C.STICKS):
				out.append(_offer("wd:%d" % st, C.title(C.STICKS[st][0]), _have(_owned(sticks, st)),
					"", p.price("wands", C.STICKS[st][0], _owned(sticks, st)), ""))
			if not sticks.is_empty():
				out.append({"head": "Recharge"})
			for i in sticks.size():
				var base := charges_of(sticks[i].which, 0, p)
				out.append(_offer("ec:%d" % i, C.title(C.STICKS[sticks[i].which][0]),
					_change(base, charges_of(sticks[i].which, sticks[i].enh, p)) + " charges",
					"next +%d" % p.amount("enhancing", "charges per purchase"),
					p.price("enhancing", "wand charges", sticks[i].enh), ""))
		5, 6:
			var potions := section == 5
			var list := "potions" if potions else "scrolls"
			var table: Array = C.POTIONS if potions else C.SCROLLS
			var known: Array[bool] = pot_known if potions else scr_known
			var count: Array[int] = pot_count if potions else scr_count
			var nk := known.count(true)
			out.append(_offer("ip" if potions else "is",
				"Identify a %s" % ("potion" if potions else "scroll"),
				"%d of %d known" % [nk, table.size()], "final",
				p.price(list, "identify", pot_ids if potions else scr_ids),
				"all known" if nk == table.size() else ""))
			if nk > 0:
				out.append({"head": "Known %s" % list})
			for k in _by_price(list, table):
				if known[k]:
					out.append(_offer(("bp:%d" if potions else "bs:%d") % k, C.title(table[k][0]),
						_have(count[k]), "", p.price(list, table[k][0], count[k]), ""))
		7:
			out.append(_offer("fd", "Food ration", "have " + _change(1, 1 + food), "next +1",
				p.price("stores", "food", food), ""))
			for i in C.MISSILES.size():
				var m: Array = C.MISSILES[i]
				var each := missile_count(i)
				var info := ""
				if missiles[i] > 0:
					info = ("+%d" if m[0] == C.ARROW else "have %d") % (each * missiles[i])
				out.append(_offer("ms:%d" % i, "%d %s" % [each, m[1]], info, "",
					p.price("stores", m[1], missiles[i]), ""))
			out.append(_offer("pk", "A bigger pack", _change(C.PACK_START, pack_size()) + " slots",
				"next +1", p.price("stores", "pack slot", slots),
				"max" if pack_size() >= C.PACK_MAX else ""))
		SKILLS_SECTION:
			for i in C.SKILLS.size():
				var sk: Array = C.SKILLS[i]
				var lvl := skill_level(sk[0])
				var o: Dictionary
				if sk[5]:	# levels: the gold multiplier
					o = _offer("sk:%d" % i, sk[1], "gold " + _change_s("x1", "x%d" % (lvl + 1)),
						"next x%d" % (lvl + 2), p.price("skills", sk[0], lvl), "")
				else:
					var locked: bool = lvl == 0 and sk[4] != "" and skill_level(sk[4]) == 0
					o = _offer("sk:%d" % i, sk[1], sk[2], "needs res." if locked else "",
						p.price("skills", sk[0], 0), "yours" if lvl > 0 else "")
					o.mark = "*" if lvl > 0 else ""
				o["text"] = sk[3]
				out.append(o)
	return out


## How many of a skill (GuildCatalog.SKILLS' name) the student has: its level, or 0.
func skill_level(name: String) -> int:
	return int(skills.get(name, 0))


## The title of the skill that a skill needs and the student lacks ("" if none).
func needs(name: String) -> String:
	for sk in C.SKILLS:
		if sk[0] == name and sk[4] != "" and skill_level(sk[4]) == 0:
			return _title_of(sk[4])
	return ""


## The title of a skill the student has that needs this one ("" if none).
func needed_by(name: String) -> String:
	for sk in C.SKILLS:
		if sk[4] == name and skill_level(sk[0]) > 0:
			return sk[1]
	return ""


static func _title_of(name: String) -> String:
	for sk in C.SKILLS:
		if sk[0] == name:
			return sk[1]
	return name


## Charges of a wand or staff the Guild sells, recharged enh times, by a price
## list (none: the built-in one).
static func charges_of(which: int, enh: int, p: GuildPrices = null) -> int:
	if p == null:
		p = GuildPrices.defaults()
	var base := p.amount("wands", "light charges" if which == C.STICK_LIGHT else "charges")
	return base + p.amount("enhancing", "charges per purchase") * enh


## How many missiles of a line (GuildCatalog.MISSILES) one purchase gives.
func missile_count(i: int) -> int:
	return prices.amount("stores", C.MISSILES[i][1] + " per purchase")


## How many times a ring of adornment can be polished.
func polish_max() -> int:
	return prices.amount("enhancing", "polish max")


func _offer(id: String, label: String, info: String, note: String, price: int,
		status: String) -> Dictionary:
	return {"id": id, "label": label, "info": info, "note": note, "price": price,
		"status": status, "mark": ""}


func _weapon_enh(id: String, label: String, hplus: int, dplus: int, enh: int) -> Dictionary:
	var now := C.enhanced(hplus, dplus, enh)
	var nxt := C.enhanced(now.x, now.y, 1)
	return _offer(id, label, _change_s(C.plus_str(hplus, dplus), C.plus_str(now.x, now.y)),
		"next +1 " + ("dmg" if nxt.y > now.y else "hit"), prices.price("enhancing", "weapon", enh),
		"")


func _armor_enh(id: String, label: String, plus: int, enh: int) -> Dictionary:
	return _offer(id, label, _change_s("+%d" % plus, "+%d" % (plus + enh)), "next +1",
		prices.price("enhancing", "armour", enh), "")


## "16" or "16 -> 18"
static func _change(base: int, now: int) -> String:
	return _change_s(str(base), str(now))


static func _change_s(base: String, now: String) -> String:
	return base if base == now else "%s -> %s" % [base, now]


static func _have(n: int) -> String:
	return "have %d" % n if n > 0 else ""


## The kinds of a table, dearest first (by the price of a first one; ties in
## table order).
func _by_price(list: String, table: Array) -> Array[int]:
	var first: Array[int] = []
	var order: Array[int] = []
	for i in table.size():
		first.append(prices.price(list, table[i][0], 0))
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		return first[a] > first[b] or (first[a] == first[b] and a < b))
	return order


# ---- the loadout --------------------------------------------------------------

## What the student takes into the dungeon (the schema is in loadout.gd).
func loadout() -> Dictionary:
	var l := {}
	l["maxpack"] = pack_size()
	l["str"] = strength
	l["hp"] = hp_step() * hit_points
	if weapon != C.WEAPON_ISSUED or weapon_enh > 0:
		l["weapon"] = {"which": weapon, "enh": weapon_enh}
	if bow_enh > 0:
		l["bow"] = {"enh": bow_enh}
	if armor != C.ARMOR_ISSUED or armor_enh > 0:
		l["armor"] = {"which": armor, "enh": armor_enh}
	l["weapons"] = spare_weapons.duplicate(true)
	l["armors"] = spare_armors.duplicate(true)
	l["rings"] = rings.duplicate(true)
	l["sticks"] = []
	for st in sticks:
		l["sticks"].append({"which": st.which, "enh": st.enh,
			"charges": charges_of(st.which, st.enh, prices)})
	l["arrows"] = 0
	var ms: Array = []
	for i in C.MISSILES.size():
		var m: Array = C.MISSILES[i]
		if missiles[i] == 0:
			continue
		if m[0] == C.ARROW:
			l["arrows"] = missile_count(i) * missiles[i]
		else:
			ms.append({"which": m[0], "count": missile_count(i) * missiles[i]})
	l["missiles"] = ms
	l["potions"] = _counted(pot_count)
	l["scrolls"] = _counted(scr_count)
	l["food"] = food
	l["know_potions"] = _known(pot_known)
	l["know_scrolls"] = _known(scr_known)
	l["skills"] = skills.duplicate()
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
