## pack.c: Routines to deal with the pack
##
## @(#)pack.c	4.40 (Berkeley) 02/05/99
class_name Pack
extends RogueBase


## add_pack:
##	Pick up an object and add it to the pack.  If the argument is
##	non-null use it as the linked_list pointer instead of gettting
##	it off the ground.
static func add_pack(obj: Thing, silent: bool) -> void:
	var op: Thing
	var lp: Thing
	var from_floor: bool

	from_floor = false
	if obj == null:
		obj = await Misc.find_obj(hero.y, hero.x)
		if obj == null:
			return
		from_floor = true

	# Check for and deal with scare monster scrolls
	if obj.o_type == SCROLL and obj.o_which == S_SCARE:
		if (obj.o_flags & ISFOUND) != 0:
			lvl_obj = List._detach(lvl_obj, obj)
			mvaddch(hero.y, hero.x, floor_ch())
			INDEX(hero.y, hero.x).p_ch = PASSAGE if (proom.r_flags & ISGONE) != 0 else FLOOR
			List.discard(obj)
			await Io.msg("the scroll turns to dust as you pick it up")
			return

	if pack == null:
		if fixes:	# FIX 5: pack_room() takes it off the floor (and counts it)
			if not await pack_room(from_floor, obj):
				return
			pack = obj
			obj.o_packch = pack_char()
		else:
			# The original does not detach obj from lvl_obj here (kept on
			# purpose, docs/FIDELITY.md).
			pack = obj
			obj.o_packch = pack_char()
			inpack += 1
	else:
		lp = null
		op = pack
		while op != null:
			if op.o_type != obj.o_type:
				lp = op
			else:
				while op.o_type == obj.o_type and op.o_which != obj.o_which:
					lp = op
					if op.l_next == null:
						break
					else:
						op = op.l_next
				if op.o_type == obj.o_type and op.o_which == obj.o_which:
					if ISMULT(op.o_type):
						if not await pack_room(from_floor, obj):
							return
						op.o_count += 1
						# dump_it:
						if fixes:	# FIX N3: redirect its pursuers before obj is gone
							var mp := mlist
							while mp != null:
								if mp.t_dest == obj.o_pos:
									mp.t_dest = hero
								mp = mp.l_next
						List.discard(obj)
						obj = op
						lp = null
						# C: goto out
					elif obj.o_group != 0:
						lp = op
						while op.o_type == obj.o_type \
								and op.o_which == obj.o_which \
								and op.o_group != obj.o_group:
							lp = op
							if op.l_next == null:
								break
							else:
								op = op.l_next
						if op.o_type == obj.o_type \
								and op.o_which == obj.o_which \
								and op.o_group == obj.o_group:
							op.o_count += obj.o_count
							inpack -= 1
							if not await pack_room(from_floor, obj):
								return
							# C: goto dump_it
							if fixes:	# FIX N3 (dump_it)
								var mp := mlist
								while mp != null:
									if mp.t_dest == obj.o_pos:
										mp.t_dest = hero
									mp = mp.l_next
							List.discard(obj)
							obj = op
							lp = null
							# C: goto out
					else:
						lp = op
				# out:
				break
			op = op.l_next

		if lp != null:
			if not await pack_room(from_floor, obj):
				return
			else:
				obj.o_packch = pack_char()
				obj.l_next = lp.l_next
				obj.l_prev = lp
				if lp.l_next != null:
					lp.l_next.l_prev = obj
				lp.l_next = obj

	obj.o_flags |= ISFOUND

	# If this was the object of something's desire, that monster will
	# get mad and run at the hero.
	op = mlist
	while op != null:
		if op.t_dest == obj.o_pos:	# pointer identity: &obj->o_pos
			op.t_dest = hero
		op = op.l_next

	if obj.o_type == AMULET:
		amulet = true
	# Notify the user
	if not silent:
		if not terse:
			await Io.addmsg("you now have ")
		var nm: String = await Things.inv_name(obj, not terse)
		await Io.msg("%s (%c)", [nm, obj.o_packch])


## pack_room:
##	See if there's room in the pack.  If not, print out an
##	appropriate message
static func pack_room(from_floor: bool, obj: Thing) -> bool:
	inpack += 1
	if inpack > (maxpack if guild else MAXPACK):	# guild mode: the Guild sells bigger packs
		if not terse:
			await Io.addmsg("there's ")
		await Io.addmsg("no room")
		if not terse:
			await Io.addmsg(" in your pack")
		await Io.endmsg()
		if from_floor:
			await move_msg(obj)
		inpack = maxpack if guild else MAXPACK
		return false

	if from_floor:
		lvl_obj = List._detach(lvl_obj, obj)
		mvaddch(hero.y, hero.x, floor_ch())
		INDEX(hero.y, hero.x).p_ch = PASSAGE if (proom.r_flags & ISGONE) != 0 else FLOOR

	return true


## leave_pack:
##	take an item out of the pack
static func leave_pack(obj: Thing, newobj: bool, all: bool) -> Thing:
	var nobj: Thing

	inpack -= 1
	nobj = obj
	if obj.o_count > 1 and not all:
		last_pick = obj
		obj.o_count -= 1
		if obj.o_group != 0:
			inpack += 1
		if newobj:
			nobj = List.new_item()
			nobj.copy_from(obj)	# *nobj = *obj (links included, as in C)
			nobj.l_next = null
			nobj.l_prev = null
			nobj.o_count = 1
	else:
		last_pick = null
		# UB: an o_packch outside 'a'..'z' (0 for an object that never got a
		# pack letter, reachable through the add_pack() empty-pack quirk)
		# writes outside pack_used[] in C; the write is dropped here.
		var used := _pack_index(obj.o_packch)
		if used >= 0 and used < pack_used.size():
			pack_used[used] = false
		pack = List._detach(pack, obj)
		if fixes and obj.o_type == AMULET:	# FIX N2: thrown or stolen, it is gone
			amulet = false
	return nobj


## pack_char:
##	Return the next unused pack character.
static func pack_char() -> int:
	var bp: int	# bool *bp, as an index into pack_used

	bp = 0
	# UB: with all 26 letters in use C reads and writes past pack_used[];
	# here the slot past the end reads as unused and the write is dropped.
	while bp < pack_used.size() and pack_used[bp]:
		bp += 1
	if bp < pack_used.size():
		pack_used[bp] = true
	return to_schar(_pack_letter(bp))


## inventory:
##	List what is in the pack.  Return TRUE if there is something of
##	the given type.
static func inventory(list: Thing, type_: int) -> bool:
	var inv_temp: String	# static char inv_temp[MAXSTR]: rewritten before every use

	n_objs = 0
	while list != null:
		if type_ != 0 and type_ != list.o_type and not (type_ == CALLABLE and \
				list.o_type != FOOD and list.o_type != AMULET) and \
				not (type_ == R_OR_S and (list.o_type == RING or list.o_type == STICK)):
			list = list.l_next
			continue
		n_objs += 1
		if MASTER and list.o_packch == 0:
			inv_temp = "%s"
		else:
			inv_temp = sprintf("%c) %%s", [list.o_packch])
		msg_esc = true
		var nm: String = await Things.inv_name(list, false)
		if await Things.add_line(inv_temp, nm) == ESCAPE:
			msg_esc = false
			await Io.msg("")
			return true
		msg_esc = false
		list = list.l_next
	if n_objs == 0:
		if terse:
			await Io.msg("empty handed" if type_ == 0 else
					"nothing appropriate")
		else:
			await Io.msg("you are empty handed" if type_ == 0 else
					"you don't have anything appropriate")
		return false
	await Things.end_line()
	return true


## pick_up:
##	Add something to characters pack.
static func pick_up(ch: int) -> void:
	var obj: Thing

	if on(player, ISLEVIT):
		return

	obj = await Misc.find_obj(hero.y, hero.x)
	if move_on:
		await move_msg(obj)
	else:
		match ch:
			GOLD:
				if obj == null:
					return
				await money(obj.o_goldval)
				lvl_obj = List._detach(lvl_obj, obj)
				List.discard(obj)
				proom.r_goldval = 0
			ARMOR, POTION, FOOD, WEAPON, SCROLL, AMULET, RING, STICK:
				await add_pack(null, false)
			_:
				if MASTER:
					await debug("Where did you pick a '%s' up???", [unctrl(ch)])
				# C falls through into the ARMOR... case
				await add_pack(null, false)


## move_msg:
##	Print out the message if you are just moving onto an object
static func move_msg(obj: Thing) -> void:
	if not terse:
		await Io.addmsg("you ")
	var nm: String = await Things.inv_name(obj, true)
	await Io.msg("moved onto %s", [nm])


## picky_inven:
##	Allow player to inventory a single item
static func picky_inven() -> void:
	var obj: Thing
	var mch: int

	if pack == null:
		await Io.msg("you aren't carrying anything")
	elif pack.l_next == null:
		var nm: String = await Things.inv_name(pack, false)
		await Io.msg("a) %s", [nm])
	else:
		await Io.msg("item: " if terse else "which item do you wish to inventory: ")
		mpos = 0
		mch = await Io.readchar()
		if mch == ESCAPE:
			await Io.msg("")
			return
		obj = pack
		while obj != null:
			if mch == obj.o_packch:
				var nm: String = await Things.inv_name(obj, false)
				await Io.msg("%c) %s", [mch, nm])
				return
			obj = obj.l_next
		await Io.msg("'%s' not in pack", [unctrl(mch)])


## get_item:
##	Pick something out of a pack for a purpose
static func get_item(purpose: String, type_: int) -> Thing:
	var obj: Thing
	var ch: int

	if pack == null:
		await Io.msg("you aren't carrying anything")
	elif again:
		if last_pick != null:
			return last_pick
		else:
			await Io.msg("you ran out")
	else:
		while true:
			if not terse:
				await Io.addmsg("which object do you want to ")
			await Io.addmsg(purpose)
			if terse:
				await Io.addmsg(" what")
			await Io.msg("? (* for list): ")
			ch = await Io.readchar()
			mpos = 0
			# Give the poor player a chance to abort the command
			if ch == ESCAPE:
				reset_last()
				after = false
				await Io.msg("")
				return null
			n_objs = 1		# normal case: person types one char
			if ch == ord("*"):
				mpos = 0
				if not await inventory(pack, type_):
					after = false
					return null
				continue
			obj = pack
			while obj != null:
				if obj.o_packch == ch:
					break
				obj = obj.l_next
			if obj == null:
				await Io.msg("'%s' is not a valid item", [unctrl(ch)])
				continue
			else:
				return obj
	return null


## money:
##	Add or subtract gold from the pack
static func money(value: int) -> void:
	purse += value
	mvaddch(hero.y, hero.x, floor_ch())
	INDEX(hero.y, hero.x).p_ch = PASSAGE if (proom.r_flags & ISGONE) != 0 else FLOOR
	if value > 0:
		if not terse:
			await Io.addmsg("you found ")
		await Io.msg("%d gold pieces", [value])


## floor_ch:
##	Return the appropriate floor character for her room
static func floor_ch() -> int:
	if (proom.r_flags & ISGONE) != 0:
		return PASSAGE
	return FLOOR if Misc.show_floor() else ord(" ")


## floor_at:
##	Return the character at hero's position, taking see_floor
##	into account
static func floor_at() -> int:
	var ch: int

	ch = chat(hero.y, hero.x)
	if ch == FLOOR:
		ch = floor_ch()
	return ch


## reset_last:
##	Reset the last command when the current one is aborted
static func reset_last() -> void:
	last_comm = l_last_comm
	last_dir = l_last_dir
	last_pick = l_last_pick


## Guild mode (docs/GUILD.md): past 'z' the pack letters go on with 'A'-'Z', and
## pack_used has 52 entries (Main.main()). These map a letter to its pack_used
## index and back; in classic mode they are C's ch - 'a' and 'a' + bp, out-of-range
## values included.
static func _pack_index(ch: int) -> int:
	if guild and ch >= ord("A") and ch <= ord("Z"):
		return ch - ord("A") + 26
	return ch - ord("a")


static func _pack_letter(bp: int) -> int:
	if guild and bp >= 26:
		return bp - 26 + ord("A")
	return bp + ord("a")
