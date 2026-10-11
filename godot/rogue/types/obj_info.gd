## struct obj_info (rogue.h). oi_name / oi_guess are char * and may be NULL
## (null here), which is distinct from "".
class_name ObjInfo
extends RefCounted

var oi_name: Variant = null	## String or null
var oi_prob := 0
var oi_worth := 0
var oi_guess: Variant = null	## String or null
var oi_know := false


func _init(name: Variant = null, prob := 0, worth := 0, guess: Variant = null, know := false) -> void:
	oi_name = name
	oi_prob = prob
	oi_worth = worth
	oi_guess = guess
	oi_know = know


func copy_from(o: ObjInfo) -> void:
	oi_name = o.oi_name
	oi_prob = o.oi_prob
	oi_worth = o.oi_worth
	oi_guess = o.oi_guess
	oi_know = o.oi_know


func dup() -> ObjInfo:
	var r := ObjInfo.new()
	r.copy_from(self)
	return r
