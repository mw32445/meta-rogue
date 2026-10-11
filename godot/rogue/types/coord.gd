## coord (rogue.h). A reference type so that pointers to coords (t_dest = &hero,
## &obj->o_pos, &rp->r_gold) see live updates. C struct assignment `a = b` is
## a.copy_from(b); never rebind a coord field that something may point at.
class_name Coord
extends RefCounted

var x := 0
var y := 0


func _init(px := 0, py := 0) -> void:
	x = px
	y = py


func copy_from(o: Coord) -> void:
	x = o.x
	y = o.y


func dup() -> Coord:
	return Coord.new(x, y)
