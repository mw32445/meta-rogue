## struct room (rogue.h). The 9 rooms and 13 passages are allocated once and
## mutated in place: struct room * pointers compare by identity.
class_name Room
extends RefCounted

var r_pos := Coord.new()	## upper left corner
var r_max := Coord.new()	## size of room
var r_gold := Coord.new()	## where the gold is
var r_goldval := 0		## how much the gold is worth
var r_flags := 0		## short: ISDARK, ISGONE, ISMAZE
var r_nexits := 0
var r_exit: Array[Coord] = []	## coord r_exit[12]


func _init() -> void:
	for i in 12:
		r_exit.append(Coord.new())


func copy_from(o: Room) -> void:
	r_pos.copy_from(o.r_pos)
	r_max.copy_from(o.r_max)
	r_gold.copy_from(o.r_gold)
	r_goldval = o.r_goldval
	r_flags = o.r_flags
	r_nexits = o.r_nexits
	for i in 12:
		r_exit[i].copy_from(o.r_exit[i])
