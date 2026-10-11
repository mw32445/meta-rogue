## THING (union thing, rogue.h): a monster, the player, or an object.
## Both union halves are separate fields here; the C code never type-puns.
## A new Thing is zero-filled like calloc: "" strings, null pointers, 0 ints.
## C `*a = *b` is a.copy_from(b): embedded structs by value, pointers (list
## links, t_dest, t_room, t_pack, o_label) by reference.
class_name Thing
extends RefCounted

## ---- common
var l_next: Thing = null
var l_prev: Thing = null

## ---- monster / player half (_t)
var t_pos := Coord.new()
var t_turn := false
var t_type := 0			## char
var t_disguise := 0		## char
var t_oldch := 0		## char (signed, may be -1 from CCHAR(ERR))
var t_dest: Coord = null	## coord *: &hero, &obj.o_pos, &room.r_gold, &monster.t_pos
var t_flags := 0		## short, stored 0..0xffff
var t_stats := Stats.new()
var t_room: Room = null
var t_pack: Thing = null
var t_reserved := 0

## ---- object half (_o)
var o_type := 0
var o_pos := Coord.new()
var o_text: Variant = null	## char * (unused by the game)
var o_launch := 0
var o_packch := 0		## char
var o_damage := ""		## char o_damage[8]
var o_hurldmg := ""		## char o_hurldmg[8]
var o_count := 0
var o_which := 0
var o_hplus := 0
var o_dplus := 0
var o_arm := 0
var o_flags := 0
var o_group := 0
var o_label: Variant = null	## char *: String or null

## #define o_charges o_arm
var o_charges: int:
	get:
		return o_arm
	set(v):
		o_arm = v

## #define o_goldval o_arm
var o_goldval: int:
	get:
		return o_arm
	set(v):
		o_arm = v


func copy_from(o: Thing) -> void:
	l_next = o.l_next
	l_prev = o.l_prev
	t_pos.copy_from(o.t_pos)
	t_turn = o.t_turn
	t_type = o.t_type
	t_disguise = o.t_disguise
	t_oldch = o.t_oldch
	t_dest = o.t_dest
	t_flags = o.t_flags
	t_stats.copy_from(o.t_stats)
	t_room = o.t_room
	t_pack = o.t_pack
	t_reserved = o.t_reserved
	o_type = o.o_type
	o_pos.copy_from(o.o_pos)
	o_text = o.o_text
	o_launch = o.o_launch
	o_packch = o.o_packch
	o_damage = o.o_damage
	o_hurldmg = o.o_hurldmg
	o_count = o.o_count
	o_which = o.o_which
	o_hplus = o.o_hplus
	o_dplus = o.o_dplus
	o_arm = o.o_arm
	o_flags = o.o_flags
	o_group = o.o_group
	o_label = o.o_label


## memset(thing, 0, sizeof(THING)) / calloc state, keeping object identity
## (and the identity of the embedded coords, which pointers may reference).
func zero() -> void:
	l_next = null
	l_prev = null
	t_pos.x = 0
	t_pos.y = 0
	t_turn = false
	t_type = 0
	t_disguise = 0
	t_oldch = 0
	t_dest = null
	t_flags = 0
	t_stats.copy_from(Stats.new())
	t_room = null
	t_pack = null
	t_reserved = 0
	o_type = 0
	o_pos.x = 0
	o_pos.y = 0
	o_text = null
	o_launch = 0
	o_packch = 0
	o_damage = ""
	o_hurldmg = ""
	o_count = 0
	o_which = 0
	o_hplus = 0
	o_dplus = 0
	o_arm = 0
	o_flags = 0
	o_group = 0
	o_label = null
