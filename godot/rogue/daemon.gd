## daemon.c: Contains functions for dealing with things that happen in the
## future.
##
## @(#)daemon.c	4.7 (Berkeley) 02/05/99
##
## d_list (RogueBase) is the C array of 20 slots, in slot order. A slot's
## d_func is a daemon function id (D_*); _call() dispatches it.
class_name Daemon
extends RogueBase


## d_slot:
##	Find an empty slot in the daemon/fuse list
static func d_slot() -> DelayedAction:
	for dev in d_list:
		if dev.d_type == EMPTY:
			return dev
	if MASTER:
		push_error("Ran out of fuse slots")	# C: debug(), then a NULL dereference
	return null


## find_slot:
##	Find a particular slot in the table
static func find_slot(func_: StringName) -> DelayedAction:
	for dev in d_list:
		if dev.d_type != EMPTY and func_ == dev.d_func:
			return dev
	return null


## start_daemon:
##	Start a daemon, takes a function.
static func start_daemon(func_: StringName, arg: int, type_: int) -> void:
	var dev := d_slot()
	dev.d_type = type_
	dev.d_func = func_
	dev.d_arg = arg
	dev.d_time = DAEMON


## kill_daemon:
##	Remove a daemon from the list
static func kill_daemon(func_: StringName) -> void:
	var dev := find_slot(func_)
	if dev == null:
		return
	# Take it out of the list
	dev.d_type = EMPTY


## do_daemons:
##	Run all the daemons that are active with the current flag,
##	passing the argument to the function.
static func do_daemons(flag: int) -> void:
	# Loop through the devil list
	for dev in d_list:
		# Executing each one, giving it the proper arguments
		if dev.d_type == flag and dev.d_time == DAEMON:
			await _call(dev.d_func, dev.d_arg)


## fuse:
##	Start a fuse to go off in a certain number of turns
static func fuse(func_: StringName, arg: int, time: int, type_: int) -> void:
	var wire := d_slot()
	wire.d_type = type_
	wire.d_func = func_
	wire.d_arg = arg
	wire.d_time = time


## lengthen:
##	Increase the time until a fuse goes off
static func lengthen(func_: StringName, xtime: int) -> void:
	var wire := find_slot(func_)
	if wire == null:
		return
	wire.d_time += xtime


## extinguish:
##	Put out a fuse
static func extinguish(func_: StringName) -> void:
	var wire := find_slot(func_)
	if wire == null:
		return
	wire.d_type = EMPTY


## do_fuses:
##	Decrement counters and start needed fuses
static func do_fuses(flag: int) -> void:
	# Step though the list
	for wire in d_list:
		# Decrementing counters and starting things we want.  We also need
		# to remove the fuse from the list once it has gone off.
		if flag == wire.d_type and wire.d_time > 0:
			wire.d_time -= 1
			if wire.d_time == 0:
				wire.d_type = EMPTY
				await _call(wire.d_func, wire.d_arg)


## (*d_func)(d_arg): call a daemon/fuse function by id.
static func _call(func_: StringName, arg: int) -> void:
	match func_:
		D_RUNNERS: await Chase.runners(arg)
		D_DOCTOR: Daemons.doctor(arg)
		D_SWANDER: Daemons.swander(arg)
		D_STOMACH: await Daemons.stomach(arg)
		D_ROLLWAND: await Daemons.rollwand(arg)
		D_UNCONFUSE: await Daemons.unconfuse(arg)
		D_NOHASTE: await Daemons.nohaste(arg)
		D_UNSEE: Daemons.unsee(arg)
		D_SIGHT: await Daemons.sight(arg)
		D_LAND: await Daemons.land(arg)
		D_COME_DOWN: await Daemons.come_down(arg)
		D_VISUALS: Daemons.visuals(arg)
		D_TURN_SEE: Potions.turn_see(arg != 0)
		_: push_error("daemon: call through a NULL function pointer")
