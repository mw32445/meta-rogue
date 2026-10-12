## STONE (rogue.h)
class_name Stone
extends RefCounted

var st_name := ""
var st_value := 0


func _init(name := "", value := 0) -> void:
	st_name = name
	st_value = value
