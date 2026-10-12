## struct delayed_action (rogue.h): a daemon/fuse slot. d_func is a daemon
## function id (RogueBase.D_*), &"" for NULL; identity comparison works on ids.
class_name DelayedAction
extends RefCounted

var d_type := 0
var d_func: StringName = &""
var d_arg := 0
var d_time := 0
