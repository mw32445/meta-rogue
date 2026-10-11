## struct stats (rogue.h): a fighting being's statistics.
class_name Stats
extends RefCounted

var s_str := 0		## str_t (unsigned int)
var s_exp := 0
var s_lvl := 0
var s_arm := 0
var s_hpt := 0
var s_dmg := ""		## char s_dmg[13]
var s_maxhp := 0


func _init(str_ := 0, exp := 0, lvl := 0, arm := 0, hpt := 0, dmg := "", maxhp := 0) -> void:
	s_str = str_
	s_exp = exp
	s_lvl = lvl
	s_arm = arm
	s_hpt = hpt
	s_dmg = dmg
	s_maxhp = maxhp


func copy_from(o: Stats) -> void:
	s_str = o.s_str
	s_exp = o.s_exp
	s_lvl = o.s_lvl
	s_arm = o.s_arm
	s_hpt = o.s_hpt
	s_dmg = o.s_dmg
	s_maxhp = o.s_maxhp


func dup() -> Stats:
	var s := Stats.new()
	s.copy_from(self)
	return s
