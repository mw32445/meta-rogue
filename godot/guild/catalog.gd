## The Fighters' Guild: the Quartermaster's price list (docs/GUILD.md).
##
## The one data file for tuning the Guild: every kind it sells, with the game's own
## name and dungeon frequency for that kind (in o_which order, exactly as in
## RogueBase's tables; godot/tests/guild_test.gd checks them after RogueBase.reset())
## and the Guild's price. Prices are whole gold pieces. In the growth rules, k is
## the number of that line already bought, so the first one costs the base price.
##
## The Guild never reads RogueBase's item tables (they are empty before the first
## game and cumulative after init_probs()); it reads these.
class_name GuildCatalog
extends RefCounted

## The Hall of Fame the Guild draws on: 20 entries in guild mode.
const HALL_SIZE := 20

## Pack slots: Rogue's 23, and at most 52 (pack letters a-z, then A-Z).
const PACK_START := 23
const PACK_MAX := 52
## What every student is issued (Init.init_player): food, ring mail, a mace, a
## bow and arrows, five pack slots.
const PACK_ISSUED := 5
## A bigger pack: +1 slot for 50 * 1.5^k.
const PACK_PRICE := 50
const PACK_NUM := 3
const PACK_DEN := 2

## Training. Strength +1 for 100 * 2^k, up to 31 (Rogue's limit); the student
## starts with 16. Max hit points +2 for 60 * 2^k; the student starts with 12.
const STR_START := 16
const STR_MAX := 31
const STR_PRICE := 100
const HP_START := 12
const HP_STEP := 2
const HP_PRICE := 60

## Enhancements, per item: 75 * 2^k for +1 to the lower of a weapon's hit and
## damage bonuses (damage first); 100 * 2^k for -1 armour class.
const WEAPON_ENH_PRICE := 75
const ARMOR_ENH_PRICE := 100

## Weapons, in o_which order: [game name, dungeon frequency, price as your
## weapon (over the mace the Guild issues; -1: not offered), price of a spare
## (+0,+0; -1: not sold), damage when wielded (Weapons.init_dam, shown)]. Your
## weapon comes +1,+1 whatever it is.
const WEAPONS: Array = [
	["mace", 11, 0, 60, "2x4"],
	["long sword", 11, 190, 250, "3x4"],
	["short bow", 12, -1, -1, "1x1"],
	["arrow", 12, -1, -1, "1x1"],
	["dagger", 8, 0, -1, "1x6"],
	["two handed sword", 10, 540, 600, "4x4"],
	["dart", 12, -1, -1, "1x1"],
	["shuriken", 12, -1, -1, "1x2"],
	["spear", 12, 0, 40, "2x3"],
]
## The order of the weapon lines (o_which): light to heavy.
const WEAPON_START_ORDER: Array[int] = [4, 8, 0, 1, 5]
const WEAPON_SPARE_ORDER: Array[int] = [8, 0, 1, 5]
## The weapon the Guild issues (MACE) and its +1,+1.
const WEAPON_ISSUED := 0
const BOW := 2
const ARROW := 3

## Armour, in o_which order: [game name, dungeon frequency, price as your armour
## (over the ring mail the Guild issues), price of a spare (+0)]. Your armour
## comes +1 whatever it is. Its armour class is a_class below.
const ARMORS: Array = [
	["leather armor", 20, 0, 20],
	["ring mail", 15, 0, 60],
	["studded leather armor", 15, 0, 60],
	["scale mail", 13, 140, 200],
	["chain mail", 12, 340, 400],
	["splint mail", 10, 640, 700],
	["banded mail", 10, 640, 700],
	["plate mail", 5, 1040, 1100],
]
const ARMOR_ORDER: Array[int] = [0, 2, 1, 3, 4, 5, 6, 7]
const ARMOR_ISSUED := 1
## RogueBase.a_class: the armour class of each kind at +0 (lower is better).
const A_CLASS: Array[int] = [8, 7, 7, 6, 5, 4, 4, 3]

## Rings, in o_which order: [game name, dungeon frequency, price of the first
## one]. A second ring of the same kind costs 4 times as much, a third 16 times:
## base * 4^k. All are known; protection, add strength, dexterity and increase
## damage come +1. Teleportation and aggravate monster are cursed, as in the
## dungeon. Adornment is free.
const RINGS: Array = [
	["protection", 9, 500],
	["add strength", 9, 500],
	["sustain strength", 5, 400],
	["searching", 10, 250],
	["see invisible", 10, 300],
	["adornment", 1, 0],
	["aggravate monster", 10, 10],
	["dexterity", 8, 450],
	["increase damage", 8, 550],
	["regeneration", 4, 900],
	["slow digestion", 9, 700],
	["teleportation", 5, 200],
	["stealth", 7, 600],
	["maintain armor", 5, 400],
]
const RING_COPY_FACTOR := 4
const RING_BONUS: Array[int] = [0, 1, 7, 8]	# R_PROTECT R_ADDSTR R_ADDHIT R_ADDDAM
const RING_CURSED: Array[int] = [6, 11]		# R_AGGR R_TELEPORT
const RING_ADORNMENT := 5			# R_NOP
## +1 more to a bonus ring: 150 * 2^k.
const RING_ENH_PRICE := 150
## Polishing a ring of adornment doubles what a winner sells it for (10, 20, ...,
## 1280); each polish costs half the value it adds: 5 * 2^k, at most 7 times.
const ADORN_WORTH := 10
const POLISH_PRICE := 5
const POLISH_MAX := 7

## Wands and staves, in o_which order: [game name, dungeon frequency, price of
## the first one]; copies cost base * 4^k. Known, with 5 charges (light: 15).
const STICKS: Array = [
	["light", 12, 120],
	["invisibility", 6, 5],
	["lightning", 3, 600],
	["fire", 3, 600],
	["cold", 3, 600],
	["polymorph", 15, 300],
	["magic missile", 10, 250],
	["haste monster", 10, 5],
	["slow monster", 11, 650],
	["drain life", 9, 400],
	["nothing", 1, 5],
	["teleport away", 6, 900],
	["teleport to", 6, 150],
	["cancellation", 5, 500],
]
const STICK_COPY_FACTOR := 4
const STICK_CHARGES := 5
const STICK_LIGHT := 0
const STICK_LIGHT_CHARGES := 15
## +2 charges: 80 * 2^k.
const CHARGE_STEP := 2
const CHARGE_PRICE := 80

## Potions and scrolls, in o_which order: [game name, dungeon frequency, base
## price]. A kind is for sale once it is identified; copies cost base * 2^k.
## Identifying names one random unknown kind, weighted by dungeon frequency,
## for this run (no item comes with it, and it is not refunded).
const POTIONS: Array = [
	["confusion", 7, 5],
	["hallucination", 8, 5],
	["poison", 8, 5],
	["gain strength", 13, 180],
	["see invisible", 3, 40],
	["healing", 13, 120],
	["monster detection", 6, 30],
	["magic detection", 6, 50],
	["raise level", 2, 250],
	["extra healing", 5, 200],
	["haste self", 5, 100],
	["restore strength", 13, 60],
	["blindness", 5, 5],
	["levitation", 6, 20],
]
const SCROLLS: Array = [
	["monster confusion", 7, 20],
	["magic mapping", 4, 100],
	["hold monster", 2, 70],
	["sleep", 3, 5],
	["enchant armor", 7, 200],
	["identify potion", 10, 30],
	["identify scroll", 10, 25],
	["identify weapon", 6, 25],
	["identify armor", 7, 30],
	["identify ring, wand or staff", 10, 40],
	["scare monster", 3, 160],
	["food detection", 2, 20],
	["teleportation", 5, 160],
	["enchant weapon", 8, 200],
	["create monster", 4, 10],
	["remove curse", 7, 50],
	["aggravate monsters", 3, 5],
	["protect armor", 2, 120],
]
const IDENTIFY_PRICE := 40

## Stores. A food ration: 30 * 1.3^k (13 rations, about 2,900 gold, stay cheaper
## than two rings of slow digestion, 700 + 2,800). Missiles at a flat price:
## [o_which, how many, price, label]. Extra arrows go onto the issued stack;
## darts, shuriken and daggers make one stack each (one pack slot).
const FOOD_PRICE := 30
const FOOD_NUM := 13
const FOOD_DEN := 10
const MISSILES: Array = [
	[3, 10, 10, "10 arrows"],
	[6, 10, 8, "10 darts"],
	[7, 5, 25, "5 shuriken"],
	[4, 2, 30, "2 daggers"],
]


## floor(base * (num / den)^k): exact while the numbers fit; beyond that (far past
## any Guild's coffers) a float estimate.
static func grow(base: int, num: int, den: int, k: int) -> int:
	var n := base
	var d := 1
	for i in k:
		if n > (1 << 60) / num or d > (1 << 60) / den:
			return int(minf(float(base) * pow(float(num) / den, k), 4.0e18))
		n *= num
		d *= den
	return n / d


## Sum of grow(base, num, den, i) for i < k: what k purchases of a line cost.
static func grow_total(base: int, num: int, den: int, k: int) -> int:
	var t := 0
	for i in k:
		t += grow(base, num, den, i)
	return t


## "two handed sword" -> "Two handed sword"
static func title(s: String) -> String:
	return s.substr(0, 1).to_upper() + s.substr(1)


static func is_bonus_ring(which: int) -> bool:
	return RING_BONUS.has(which)


static func is_cursed_ring(which: int) -> bool:
	return RING_CURSED.has(which)


## What the hit and damage bonuses become after enh enhancements: each adds +1 to
## the lower of the two, damage first when they are equal.
static func enhanced(hplus: int, dplus: int, enh: int) -> Vector2i:
	for i in enh:
		if dplus <= hplus:
			dplus += 1
		else:
			hplus += 1
	return Vector2i(hplus, dplus)


## A weapon bonus as Rogue prints it: "+1,+0".
static func plus_str(hplus: int, dplus: int) -> String:
	return "%s,%s" % [_signed(hplus), _signed(dplus)]


static func _signed(n: int) -> String:
	return ("+%d" % n) if n >= 0 else str(n)
