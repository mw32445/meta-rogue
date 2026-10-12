## init.c: global variable initializaton
##
## @(#)init.c	4.31 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## The static bool used[] and init_materials()' static bool metused[] are
## RogueBase._init_used and RogueBase._init_materials_metused.
## p_colors[], r_stones[] and ws_made[] (RogueBase) hold strings of the tables
## below, as the C char * pointers do.
class_name Init
extends RogueBase


## init_player:
##	Roll her up
static func init_player() -> void:
	var obj: Thing

	pstats.copy_from(max_stats)	# pstats = max_stats;
	food_left = HUNGERTIME
	# Give him some food
	obj = List.new_item()
	obj.o_type = FOOD
	obj.o_count = 1
	await Pack.add_pack(obj, true)
	# And his suit of armor
	obj = List.new_item()
	obj.o_type = ARMOR
	obj.o_which = RING_MAIL
	obj.o_arm = a_class[RING_MAIL] - 1
	obj.o_flags |= ISKNOW
	obj.o_count = 1
	cur_armor = obj
	await Pack.add_pack(obj, true)
	# Give him his weaponry.  First a mace.
	obj = List.new_item()
	Weapons.init_weapon(obj, MACE)
	obj.o_hplus = 1
	obj.o_dplus = 1
	obj.o_flags |= ISKNOW
	await Pack.add_pack(obj, true)
	cur_weapon = obj
	# Now a +1 bow
	obj = List.new_item()
	Weapons.init_weapon(obj, BOW)
	obj.o_hplus = 1
	obj.o_flags |= ISKNOW
	await Pack.add_pack(obj, true)
	# Now some arrows
	obj = List.new_item()
	Weapons.init_weapon(obj, ARROW)
	obj.o_count = rnd(15) + 25
	obj.o_flags |= ISKNOW
	await Pack.add_pack(obj, true)


# Contains defintions and functions for dealing with things like
# potions and scrolls

const rainbow: Array[String] = [
	"amber",
	"aquamarine",
	"black",
	"blue",
	"brown",
	"clear",
	"crimson",
	"cyan",
	"ecru",
	"gold",
	"green",
	"grey",
	"magenta",
	"orange",
	"pink",
	"plaid",
	"purple",
	"red",
	"silver",
	"tan",
	"tangerine",
	"topaz",
	"turquoise",
	"vermilion",
	"violet",
	"white",
	"yellow",
]

## #define NCOLORS (sizeof rainbow / sizeof (char *))
const NCOLORS := 27
const cNCOLORS := NCOLORS

const sylls: Array[String] = [
	"a", "ab", "ag", "aks", "ala", "an", "app", "arg", "arze", "ash",
	"bek", "bie", "bit", "bjor", "blu", "bot", "bu", "byt", "comp",
	"con", "cos", "cre", "dalf", "dan", "den", "do", "e", "eep", "el",
	"eng", "er", "ere", "erk", "esh", "evs", "fa", "fid", "fri", "fu",
	"gan", "gar", "glen", "gop", "gre", "ha", "hyd", "i", "ing", "ip",
	"ish", "it", "ite", "iv", "jo", "kho", "kli", "klis", "la", "lech",
	"mar", "me", "mi", "mic", "mik", "mon", "mung", "mur", "nej",
	"nelg", "nep", "ner", "nes", "nes", "nih", "nin", "o", "od", "ood",
	"org", "orn", "ox", "oxy", "pay", "ple", "plu", "po", "pot",
	"prok", "re", "rea", "rhov", "ri", "ro", "rog", "rok", "rol", "sa",
	"san", "sat", "sef", "seh", "shu", "ski", "sna", "sne", "snik",
	"sno", "so", "sol", "sri", "sta", "sun", "ta", "tab", "tem",
	"ther", "ti", "tox", "trol", "tue", "turs", "u", "ulk", "um", "un",
	"uni", "ur", "val", "viv", "vly", "vom", "wah", "wed", "werg",
	"wex", "whon", "wun", "xo", "y", "yot", "yu", "zant", "zeb", "zim",
	"zok", "zon", "zum",
]

## (sizeof sylls) / (sizeof (char *))
const NSYLLS := 147

## STONE stones[]: { st_name, st_value } (the STONE struct of rogue.h)
const stones: Array[Dictionary] = [
	{"st_name": "agate", "st_value": 25},
	{"st_name": "alexandrite", "st_value": 40},
	{"st_name": "amethyst", "st_value": 50},
	{"st_name": "carnelian", "st_value": 40},
	{"st_name": "diamond", "st_value": 300},
	{"st_name": "emerald", "st_value": 300},
	{"st_name": "germanium", "st_value": 225},
	{"st_name": "granite", "st_value": 5},
	{"st_name": "garnet", "st_value": 50},
	{"st_name": "jade", "st_value": 150},
	{"st_name": "kryptonite", "st_value": 300},
	{"st_name": "lapis lazuli", "st_value": 50},
	{"st_name": "moonstone", "st_value": 50},
	{"st_name": "obsidian", "st_value": 15},
	{"st_name": "onyx", "st_value": 60},
	{"st_name": "opal", "st_value": 200},
	{"st_name": "pearl", "st_value": 220},
	{"st_name": "peridot", "st_value": 63},
	{"st_name": "ruby", "st_value": 350},
	{"st_name": "sapphire", "st_value": 285},
	{"st_name": "stibotantalite", "st_value": 200},
	{"st_name": "tiger eye", "st_value": 50},
	{"st_name": "topaz", "st_value": 60},
	{"st_name": "turquoise", "st_value": 70},
	{"st_name": "taaffeite", "st_value": 300},
	{"st_name": "zircon", "st_value": 80},
]

## #define NSTONES (sizeof stones / sizeof (STONE))
const NSTONES := 26
const cNSTONES := NSTONES

const wood: Array[String] = [
	"avocado wood",
	"balsa",
	"bamboo",
	"banyan",
	"birch",
	"cedar",
	"cherry",
	"cinnibar",
	"cypress",
	"dogwood",
	"driftwood",
	"ebony",
	"elm",
	"eucalyptus",
	"fall",
	"hemlock",
	"holly",
	"ironwood",
	"kukui wood",
	"mahogany",
	"manzanita",
	"maple",
	"oaken",
	"persimmon wood",
	"pecan",
	"pine",
	"poplar",
	"redwood",
	"rosewood",
	"spruce",
	"teak",
	"walnut",
	"zebrawood",
]

## #define NWOOD (sizeof wood / sizeof (char *))
const NWOOD := 33
const cNWOOD := NWOOD

const metal: Array[String] = [
	"aluminum",
	"beryllium",
	"bone",
	"brass",
	"bronze",
	"copper",
	"electrum",
	"gold",
	"iron",
	"lead",
	"magnesium",
	"mercury",
	"nickel",
	"pewter",
	"platinum",
	"steel",
	"silver",
	"silicon",
	"tin",
	"titanium",
	"tungsten",
	"zinc",
]

## #define NMETAL (sizeof metal / sizeof (char *))
const NMETAL := 22
const cNMETAL := NMETAL

## static bool used[MAX3(NCOLORS, NSTONES, NWOOD)] is RogueBase._init_used (33)


## init_colors:
##	Initialize the potion color scheme for this time
static func init_colors() -> void:
	var j: int

	for i in NCOLORS:
		_init_used[i] = false
	for i in MAXPOTIONS:
		while true:
			j = rnd(NCOLORS)
			if not _init_used[j]:	# until (!used[j])
				break
		_init_used[j] = true
		p_colors[i] = rainbow[j]


## Max number of characters in a name
const MAXNAME := 40


## init_names:
##	Generate the names of the various scrolls
##	(C builds each name in the global prbuf through cp; here cp is the
##	text written so far, so cp - prbuf is cp.length())
static func init_names() -> void:
	var nsyl: int
	var cp: String
	var sp: String
	var nwords: int

	for i in MAXSCROLLS:
		cp = ""	# cp = prbuf
		nwords = rnd(3) + 2
		while nwords != 0:	# while (nwords--)  (its final -1 is never read)
			nwords -= 1
			nsyl = rnd(3) + 1
			while nsyl != 0:	# while (nsyl--)  (its final value is never read)
				nsyl -= 1
				sp = sylls[rnd(NSYLLS)]
				if cp.length() + sp.length() > MAXNAME:	# &cp[strlen(sp)] > &prbuf[MAXNAME]
					break
				cp += sp	# while (*sp) *cp++ = *sp++;
			cp += " "	# *cp++ = ' ';
		cp = cp.substr(0, cp.length() - 1)	# *--cp = '\0';
		if fixes:
			# FIX N11: a word the length limit left empty still got its
			# space: drop doubled and trailing spaces (same RNG calls)
			while cp.contains("  "):
				cp = cp.replace("  ", " ")
			while cp.ends_with(" "):
				cp = cp.substr(0, cp.length() - 1)
		prbuf = cp
		s_names[i] = prbuf	# malloc + strcpy(s_names[i], prbuf)


## init_stones:
##	Initialize the ring stone setting scheme for this time
static func init_stones() -> void:
	var j: int

	for i in NSTONES:
		_init_used[i] = false
	for i in MAXRINGS:
		while true:
			j = rnd(NSTONES)
			if not _init_used[j]:	# until (!used[j])
				break
		_init_used[j] = true
		r_stones[i] = stones[j].st_name
		ring_info[i].oi_worth += stones[j].st_value


## init_materials:
##	Initialize the construction materials for wands and staffs
static func init_materials() -> void:
	var j: int
	var str_: String	# char *str

	for i in NWOOD:
		_init_used[i] = false
	for i in NMETAL:
		_init_materials_metused[i] = false
	for i in MAXSTICKS:
		while true:
			if rnd(2) == 0:
				j = rnd(NMETAL)
				if not _init_materials_metused[j]:
					ws_type[i] = "wand"
					str_ = metal[j]
					_init_materials_metused[j] = true
					break
			else:
				j = rnd(NWOOD)
				if not _init_used[j]:
					ws_type[i] = "staff"
					str_ = wood[j]
					if fixes and str_ == "cinnibar":	# FIX typo (init.c wood[])
						str_ = "cinnabar"
					_init_used[j] = true
					break
		ws_made[i] = str_


## sumprobs:
##	Sum up the probabilities for items appearing
##	(name is the MASTER-only third parameter: NT, MP, ... pass a table name
##	under MASTER, and badcheck() reports with it)
static func sumprobs(info: Array[ObjInfo], bound: int, name: String = "") -> void:
	# MASTER: struct obj_info *start = info;  (the table itself: index 0)
	var endp: int
	var ip := 0	# info, as an index into the table

	endp = ip + bound
	while true:	# while (++info < endp)
		ip += 1
		if not (ip < endp):
			break
		info[ip].oi_prob += info[ip - 1].oi_prob
	if MASTER:
		badcheck(name, info, bound)	# badcheck(name, start, bound)


## init_probs:
##	Initialize the probabilities for the various items
static func init_probs() -> void:
	sumprobs(things, NUMTHINGS, "things")
	sumprobs(pot_info, MAXPOTIONS, "potions")
	sumprobs(scr_info, MAXSCROLLS, "scrolls")
	sumprobs(ring_info, MAXRINGS, "rings")
	sumprobs(ws_info, MAXSTICKS, "sticks")
	sumprobs(weap_info, MAXWEAPONS, "weapons")
	sumprobs(arm_info, MAXARMORS, "armor")


## badcheck:
##	Check to see if a series of probabilities sums to 100
##	(#ifdef MASTER in C. C printf()s the table to stdout and waits for
##	RETURN with getchar(); every table is fixed and sums to 100, so this
##	never fires: the port reports with push_error and does not block,
##	see tools/blocking.json port_nonblocking.)
static func badcheck(name: String, info: Array[ObjInfo], bound: int) -> void:
	if info[bound - 1].oi_prob == 100:
		return
	push_error(sprintf("\nBad percentages for %s (bound = %d):\n", [name, bound]))
	for i in bound:	# for (end = &info[bound]; info < end; info++)
		push_error(sprintf("%3d%% %s\n", [info[i].oi_prob, info[i].oi_name]))
	push_error("[hit RETURN to continue]")


## pick_color:
##	If he is halucinating, pick a random color name and return it,
##	otherwise return the given color.
static func pick_color(col: String) -> String:
	return rainbow[rnd(NCOLORS)] if on(player, ISHALU) else col
