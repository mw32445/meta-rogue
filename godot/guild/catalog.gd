## The Fighters' Guild: its catalog (docs/GUILD.md).
##
## What the Guild sells, as facts of the game: every kind with the game's own
## name and dungeon frequency (in o_which order, exactly as in RogueBase's
## tables; godot/tests/guild_test.gd checks them after RogueBase.reset()), the
## order of its lines, and the limits of the game and of the engine.
##
## The prices are not here. They are in godot/guild_prices.txt, a text file the
## players can edit; GuildPrices reads it. PRICES, at the end, is its built-in
## copy: what a line that can't be read falls back to, and what an exported game
## writes when it finds no file. godot/tests/prices_test.gd checks that the two
## are the same and that they give the prices the Guild had before the file.
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

## Training: the student starts with strength 16 (at most 31, Rogue's limit)
## and 12 max hit points.
const STR_START := 16
const STR_MAX := 31
const HP_START := 12

## Weapons, in o_which order: [game name, dungeon frequency, damage when wielded
## (Weapons.init_dam, shown)]. The student's weapon comes +1,+1 whatever it is.
const WEAPONS: Array = [
	["mace", 11, "2x4"],
	["long sword", 11, "3x4"],
	["short bow", 12, "1x1"],
	["arrow", 12, "1x1"],
	["dagger", 8, "1x6"],
	["two handed sword", 10, "4x4"],
	["dart", 12, "1x1"],
	["shuriken", 12, "1x2"],
	["spear", 12, "2x3"],
]
## The weapons offered as the student's ([your weapon] in the price list) and as
## spares ([spare weapons]), in the order of their lines (o_which): light to heavy.
const WEAPON_START_ORDER: Array[int] = [4, 8, 0, 1, 5]
const WEAPON_SPARE_ORDER: Array[int] = [8, 0, 1, 5]
## The weapon the Guild issues (MACE) and its +1,+1.
const WEAPON_ISSUED := 0
const BOW := 2
const ARROW := 3

## Armour, in o_which order: [game name, dungeon frequency]. The student's
## armour comes +1 whatever it is. Its armour class is a_class below.
const ARMORS: Array = [
	["leather armor", 20],
	["ring mail", 15],
	["studded leather armor", 15],
	["scale mail", 13],
	["chain mail", 12],
	["splint mail", 10],
	["banded mail", 10],
	["plate mail", 5],
]
const ARMOR_ORDER: Array[int] = [0, 2, 1, 3, 4, 5, 6, 7]
const ARMOR_ISSUED := 1
## RogueBase.a_class: the armour class of each kind at +0 (lower is better).
const A_CLASS: Array[int] = [8, 7, 7, 6, 5, 4, 4, 3]

## Rings, in o_which order: [game name, dungeon frequency]. All are known;
## protection, add strength, dexterity and increase damage come +1.
## Teleportation and aggravate monster are cursed, as in the dungeon.
const RINGS: Array = [
	["protection", 9],
	["add strength", 9],
	["sustain strength", 5],
	["searching", 10],
	["see invisible", 10],
	["adornment", 1],
	["aggravate monster", 10],
	["dexterity", 8],
	["increase damage", 8],
	["regeneration", 4],
	["slow digestion", 9],
	["teleportation", 5],
	["stealth", 7],
	["maintain armor", 5],
]
const RING_BONUS: Array[int] = [0, 1, 7, 8]	# R_PROTECT R_ADDSTR R_ADDHIT R_ADDDAM
const RING_CURSED: Array[int] = [6, 11]		# R_AGGR R_TELEPORT
const RING_ADORNMENT := 5			# R_NOP
## Polishing a ring of adornment doubles what a winner sells it for: its worth,
## 10 plus the value of the stone it is set in (which the hero only sees in the
## dungeon), times 2 per polish (Rip.total_winner). At most 20 polishes, whatever
## the price list says: the dearest stone, 310 << 20, stays a 32-bit number.
const POLISH_LIMIT := 20

## Wands and staves, in o_which order: [game name, dungeon frequency]. Known.
const STICKS: Array = [
	["light", 12],
	["invisibility", 6],
	["lightning", 3],
	["fire", 3],
	["cold", 3],
	["polymorph", 15],
	["magic missile", 10],
	["haste monster", 10],
	["slow monster", 11],
	["drain life", 9],
	["nothing", 1],
	["teleport away", 6],
	["teleport to", 6],
	["cancellation", 5],
]
const STICK_LIGHT := 0

## Potions and scrolls, in o_which order: [game name, dungeon frequency]. A kind
## is for sale once it is identified. Identifying names one random unknown kind,
## weighted by dungeon frequency, for this run (no item comes with it, and it is
## not refunded).
const POTIONS: Array = [
	["confusion", 7],
	["hallucination", 8],
	["poison", 8],
	["gain strength", 13],
	["see invisible", 3],
	["healing", 13],
	["monster detection", 6],
	["magic detection", 6],
	["raise level", 2],
	["extra healing", 5],
	["haste self", 5],
	["restore strength", 13],
	["blindness", 5],
	["levitation", 6],
]
const SCROLLS: Array = [
	["monster confusion", 7],
	["magic mapping", 4],
	["hold monster", 2],
	["sleep", 3],
	["enchant armor", 7],
	["identify potion", 10],
	["identify scroll", 10],
	["identify weapon", 6],
	["identify armor", 7],
	["identify ring, wand or staff", 10],
	["scare monster", 3],
	["food detection", 2],
	["teleportation", 5],
	["enchant weapon", 8],
	["create monster", 4],
	["remove curse", 7],
	["aggravate monsters", 3],
	["protect armor", 2],
]

## Missiles, in the order of their lines: [o_which, their name in the price
## list]. Extra arrows go onto the issued stack; darts, shuriken and daggers
## make one stack each (one pack slot).
const MISSILES: Array = [
	[3, "arrows"],
	[6, "darts"],
	[7, "shuriken"],
	[4, "daggers"],
]

## The skills (docs/GUILD.md, "Skills"), in the shop's order: [name (in [skills] of
## the price list, and RogueBase's SK_* constants), title, what the list says,
## the description (shown under the list), the skill it needs ("" for none), whether
## it has levels (bought again and again) or is bought once].
const SKILLS: Array = [
	["frost resistance", "Frost Resistance", "no instant kill",
		"Ice Monster can no longer instant kill you.", "", false],
	["frost immunity", "Frost Immunity", "no freezing",
		"Ice Monster can no longer freeze you. Needs Frost Resistance.", "frost resistance", false],
	["sure sight", "Sure Sight", "immune to blind", "Immune to Blind.", "", false],
	["high intellect", "High Intellect", "immune to confusion",
		"Immune to Confusion. Both Medusa effect and potion impact.", "", false],
	["low-light vision", "Low-Light Vision", "+1 tile in dark rooms",
		"See 1 extra tile in dark rooms in all directions.", "", false],
	["throw anything", "Throw Anything", "thrown items work",
		"Thrown items have effects. Hitting enemies with armor does damage to them (1x4), potions"
		+ " and scrolls work on them, a ring has its effect on that monster, and a wand expends a"
		+ " charge. All items are listed in the throw menu. You cannot throw the amulet.", "", false],
	["coin scrounger", "Coin Scrounger", "",
		"Doubles amount of money gained on pickup. Each level after this increases the multiplier"
		+ " to 3x, 4x, 5x, etc.", "", true],
	["safe pockets", "Safe Pockets", "no stealing",
		"Leprechauns and Nymphs may no longer steal from you, instead they attack you like normal"
		+ " monsters. They do Zombie level damage.", "", false],
	["serpentine cult", "Serpentine Cult", "snakes sleep",
		"If a Rattlesnake bites, it no longer reduces your strength, and the bite has a 25% chance"
		+ " of increasing your strength instead, once per snake. All snakes start as sleeping. If you kill any"
		+ " snakes, you will be banished from the cult, and all snakes will do 50% more damage to"
		+ " you for the rest of the run, in addition to losing all benefits. You must repeat a"
		+ " hostile action against a snake to confirm it.", "", false],
	["advanced recovery", "Advanced Recovery", "heal as level +1",
		"Your HP recovery is from one level higher than your current level.", "", false],
]

## The built-in price list: the text of godot/guild_prices.txt (see above).
const PRICES := """# The Fighters' Guild: the Quartermaster's price list
#
# Before every new game the Guild outfits its student with the gold in its
# coffers. This file says how much gold that is and what everything costs.
# Change a number or a formula with any text editor and save the file: the
# Guild reads it each time it opens.
#
# The file
#   [training]             a heading: the part of the stores below it
#   strength = 100 * 2^k   a name, then "=", then a number or a formula
#   # ...                  a comment: the rest of the line is not read
# Everything before the "=" is the name. Keep the names as they are: the Guild
# knows its goods by them. A line you delete keeps its original value.
#
# Formulas
#   k        how many of that item you have already bought (0 for the first)
#   base     the item's own number in its list ([rings], [wands], [potions],
#            [scrolls])
#   + - * /  plus, minus, times, divided by
#   ^        to the power of: 2^k doubles the price with each one bought,
#            1.5^k makes each one half as dear again
#   ( )      brackets: (a + b) * c
#   floor ceil round min max pow sqrt abs clamp lerp
#            floor(x) rounds down, ceil(x) up, round(x) to the nearest;
#            min(a, b) is the smaller, max(a, b) the larger; pow(a, b) is a^b;
#            sqrt(x) the square root; abs(x) is x without a minus sign;
#            clamp(x, low, high) keeps x between low and high; lerp(a, b, t)
#            goes from a to b as t goes from 0 to 1: a + (b - a) * t
# Prices are rounded down to whole gold pieces.
#
# A line the Guild can't read is shown at the bottom of its screen (and all of
# them on its help page, ?), and the original value is used for it.
#
# Not in this file, because they are facts of the game: what the items do and
# how often they turn up in the dungeon, strength 31 at most, 52 items in a
# pack at most, the 20 places of the Hall of Fame, and the kit every student
# is issued.

[coffers]
# The gold the Guild gives each new student. It comes from the Hall of Fame,
# the top 20 scores: best = the best score, sum = all the scores added up,
# n = how many heroes are in it (0 to 20). lerp(0.5, 1.5, n / 20) grows from
# 0.5 with no heroes to 1.5 with twenty.
coffers = best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20)

[training]
# Strength starts at 16 and rises by 1, up to 31. Hit points start at 12.
strength = 100 * 2^k
hit points = 60 * 2^k
hit points per purchase = 2

[your weapon]
# You are issued a mace +1,+1. Changing it for another weapon (which keeps the
# +1,+1) costs that weapon's price less the mace's; changing back refunds it.
dagger = 0
spear = 0
mace = 0
long sword = 190
two handed sword = 540

[spare weapons]
# An extra weapon, +0,+0. k: how many of that kind you have bought.
spear = 40
mace = 60
long sword = 250
two handed sword = 600

[your armour]
# You are issued ring mail +1. Changing it for another kind (which keeps the
# +1) costs that kind's price less the ring mail's; changing back refunds it.
leather armor = 0
studded leather armor = 0
ring mail = 0
scale mail = 140
chain mail = 340
splint mail = 640
banded mail = 640
plate mail = 1040

[spare armour]
# An extra suit of armour, +0.
leather armor = 20
studded leather armor = 60
ring mail = 60
scale mail = 200
chain mail = 400
splint mail = 700
banded mail = 700
plate mail = 1100

[enhancing]
# k: how many times that one item has been enhanced already.
# weapon: +1 to its hit or damage bonus, whichever is lower.
# ring: +1 to a ring of protection, add strength, dexterity or increase damage.
# polish: a ring of adornment; each polish doubles what a winner sells it for.
# wand charges: recharging a wand or a staff.
weapon = 75 * 2^k
armour = 100 * 2^k           # +1 to a suit of armour
ring = 150 * 2^k
polish = 5 * 2^k
polish max = 7               # 20 at most
wand charges = 40 * 2^k
charges per purchase = 2

[rings]
# Each kind's number (base) is what the first one costs; price is what the
# next one costs when you have k of that kind.
price = base * 4^k
regeneration = 800
slow digestion = 625
stealth = 550
increase damage = 500
protection = 450
add strength = 450
dexterity = 400
sustain strength = 350
maintain armor = 350
see invisible = 275
searching = 225
teleportation = 175
aggravate monster = 10
adornment = 0

[wands]
# Wands and staves. Each kind's number (base) is what the first one costs;
# price is what the next one costs when you have k of that kind.
price = base * 2^k
charges = 5                  # a new one's charges
light charges = 15           # a new wand of light's
teleport away = 300
slow monster = 250
lightning = 250
fire = 250
cold = 250
cancellation = 200
drain life = 150
polymorph = 120
magic missile = 80
teleport to = 60
light = 50
invisibility = 5
haste monster = 5
nothing = 5

[potions]
# identify names one random kind you don't know, for this game: no potion
# comes with it, and it can't be returned (k: how many you have had named).
# price is what a potion of a kind you know costs when you have k of it.
identify = 40
price = base * 2^k
raise level = 250
extra healing = 200
gain strength = 180
healing = 120
haste self = 100
restore strength = 60
magic detection = 50
see invisible = 40
monster detection = 30
levitation = 20
confusion = 5
hallucination = 5
poison = 5
blindness = 5

[scrolls]
# As the potions.
identify = 40
price = base * 2^k
enchant armor = 200
enchant weapon = 200
scare monster = 160
teleportation = 160
protect armor = 120
magic mapping = 100
hold monster = 70
remove curse = 50
identify ring, wand or staff = 40
identify potion = 30
identify armor = 30
identify scroll = 25
identify weapon = 25
monster confusion = 20
food detection = 20
create monster = 10
sleep = 5
aggravate monsters = 5

[stores]
# food: a ration. pack slot: one more place in your pack (23 to start, 52 at
# most). Arrows go onto the issued stack and take no place; darts, shuriken
# and daggers make one stack each.
food = 30 * 1.3^k
pack slot = 50 * 1.5^k
arrows = 10
arrows per purchase = 10
darts = 8
darts per purchase = 10
shuriken = 25
shuriken per purchase = 5
daggers = 30
daggers per purchase = 2

[skills]
# Skills for this game. Each is bought once, except coin scrounger: each level
# adds 1 to what gold is multiplied by (x2, then x3, ...), and k is how many
# levels you have already. frost immunity needs frost resistance.
frost resistance = 200
frost immunity = 300
sure sight = 100
high intellect = 500
low-light vision = 700
throw anything = 200
coin scrounger = 1000 * (k + 1)
safe pockets = 300
serpentine cult = 0
advanced recovery = 800
"""


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
