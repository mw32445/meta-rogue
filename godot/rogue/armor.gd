## armor.c: This file contains misc functions for dealing with armor
## @(#)armor.c	4.14 (Berkeley) 02/05/99
class_name Armor
extends RogueBase


## wear:
##	The player wants to wear something, so let him/her put it on.
static func wear() -> void:
	var obj: Thing
	var sp: String

	obj = await Pack.get_item("wear", ARMOR)
	if obj == null:
		return
	if cur_armor != null:
		await Io.addmsg("you are already wearing some")
		if not terse:
			await Io.addmsg(".  You'll have to take it off first")
		await Io.endmsg()
		after = false
		return
	if obj.o_type != ARMOR:
		await Io.msg("you can't wear that")
		return
	await waste_time()
	obj.o_flags |= ISKNOW
	sp = Things.inv_name(obj, true)
	cur_armor = obj
	if not terse:
		await Io.addmsg("you are now ")
	await Io.msg("wearing %s", [sp])


## take_off:
##	Get the armor off of the players back
static func take_off() -> void:
	var obj: Thing

	obj = cur_armor
	if obj == null:
		after = false
		if terse:
			await Io.msg("not wearing armor")
		else:
			await Io.msg("you aren't wearing any armor")
		return
	if not await Things.dropcheck(cur_armor):
		return
	cur_armor = null
	if terse:
		await Io.addmsg("was")
	else:
		await Io.addmsg("you used to be")
	await Io.msg(" wearing %c) %s", [obj.o_packch, Things.inv_name(obj, true)])


## waste_time:
##	Do nothing but let other things happen
static func waste_time() -> void:
	await Daemon.do_daemons(BEFORE())
	await Daemon.do_fuses(BEFORE())
	await Daemon.do_daemons(AFTER())
	await Daemon.do_fuses(AFTER())
