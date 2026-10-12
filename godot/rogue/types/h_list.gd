## struct h_list (rogue.h): help / identify / killname table entry.
class_name HList
extends RefCounted

var h_ch := 0
var h_desc: Variant = null	## String or null
var h_print := false


func _init(ch := 0, desc: Variant = null, print_ := false) -> void:
	h_ch = ch
	h_desc = desc
	h_print = print_
