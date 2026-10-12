## PLACE (rogue.h): one square of the level map.
class_name Place
extends RefCounted

var p_ch := 0		## char (zeroed like the C global array)
var p_flags := 0	## char, stored 0..255 (only ever used as bit masks)
var p_monst: Thing = null
