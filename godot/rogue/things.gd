## things.c: Contains functions for dealing with things like potions, scrolls,
## and other items.
##
## @(#)things.c	4.53 (Berkeley) 02/05/99
##
## inv_name(), nameit() and nothing() write the global prbuf and return it.
## C's "pb = &prbuf[strlen(prbuf)]; sprintf(pb, ...)" appends to prbuf, and
## "strcat(pb, ...)" always appends.
##
## The file statics line_cnt, newpage, lastfmt and lastarg, and add_line()'s
## static maxlen, live in RogueBase (_things_line_cnt, _things_newpage,
## _things_lastfmt, _things_lastarg, _add_line_maxlen); print_disc()'s
## static THING is RogueBase._print_disc_obj.
##
## nameit()'s function pointer prfunc (nullstr, ring_num or charge_str) is
## one of the ids PRF_* below, called through _prfunc().
class_name Things
extends RogueBase

## char *(*prfunc)(THING *) ids for nameit()
const PRF_NULLSTR := &"nullstr"
const PRF_RING_NUM := &"ring_num"
const PRF_CHARGE_STR := &"charge_str"


## inv_name:
##	Return the name of something as it would appear in an
##	inventory.
static func inv_name(obj: Thing, drop: bool) -> String:
	var op: ObjInfo
	var sp: Variant	# char *: an oi_name
	var which: int

	# pb = prbuf;
	which = obj.o_which
	match obj.o_type:
		POTION:
			nameit(obj, "potion", p_colors[which], pot_info[which], PRF_NULLSTR)
		RING:
			nameit(obj, "ring", r_stones[which], ring_info[which], PRF_RING_NUM)
		STICK:
			nameit(obj, ws_type[which], ws_made[which], ws_info[which], PRF_CHARGE_STR)
		SCROLL:
			if obj.o_count == 1:
				prbuf = "A scroll "
				# pb = &prbuf[9];
			else:
				prbuf = sprintf("%d scrolls ", [obj.o_count])
				# pb = &prbuf[strlen(prbuf)];
			op = scr_info[which]
			if op.oi_know:
				prbuf += sprintf("of %s", [op.oi_name])
			elif op.oi_guess != null:
				prbuf += sprintf("called %s", [op.oi_guess])
			else:
				prbuf += sprintf("titled '%s'", [s_names[which]])
		FOOD:
			if which == 1:
				if obj.o_count == 1:
					prbuf = sprintf("A%s %s", [Misc.vowelstr(fruit), fruit])
				else:
					prbuf = sprintf("%d %ss", [obj.o_count, fruit])
			else:
				if obj.o_count == 1:
					prbuf = "Some food"
				else:
					prbuf = sprintf("%d rations of food", [obj.o_count])
		WEAPON:
			sp = weap_info[which].oi_name
			if obj.o_count > 1:
				prbuf = sprintf("%d ", [obj.o_count])
			else:
				prbuf = sprintf("A%s ", [Misc.vowelstr(sp)])
			# pb = &prbuf[strlen(prbuf)];
			if (obj.o_flags & ISKNOW) != 0:
				prbuf += sprintf("%s %s", [Weapons.num(obj.o_hplus, obj.o_dplus, WEAPON), sp])
			else:
				prbuf += sprintf("%s", [sp])
			if obj.o_count > 1:
				prbuf += "s"
			if obj.o_label != null:
				# pb = &prbuf[strlen(prbuf)];
				prbuf += sprintf(" called %s", [obj.o_label])
		ARMOR:
			sp = arm_info[which].oi_name
			if (obj.o_flags & ISKNOW) != 0:
				prbuf = sprintf("%s %s [",
					[Weapons.num(a_class[which] - obj.o_arm, 0, ARMOR), sp])
				if not terse:
					prbuf += "protection "
				# pb = &prbuf[strlen(prbuf)];
				prbuf += sprintf("%d]", [10 - obj.o_arm])
			else:
				prbuf = sprintf("%s", [sp])
			if obj.o_label != null:
				# pb = &prbuf[strlen(prbuf)];
				prbuf += sprintf(" called %s", [obj.o_label])
		AMULET:
			prbuf = "The Amulet of Yendor"
		GOLD:
			prbuf = sprintf("%d Gold pieces", [obj.o_goldval])
		_:
			if MASTER:
				# C: debug("Picked up something funny %s", ...), a msg();
				# push_error instead (blocking.json port_nonblocking).
				if wizard:
					push_error(sprintf("Picked up something funny %s", [unctrl(obj.o_type)]))
				prbuf = sprintf("Something bizarre %s", [unctrl(obj.o_type)])
			# else: no default case, prbuf keeps its old contents
	if inv_describe:
		if obj == cur_armor:
			prbuf += " (being worn)"
		if obj == cur_weapon:
			prbuf += " (weapon in hand)"
		if obj == cur_ring[LEFT]:
			prbuf += " (on left hand)"
		elif obj == cur_ring[RIGHT]:
			prbuf += " (on right hand)"
	if drop and isupper(cat(prbuf, 0)):
		prbuf = chr(tolower(cat(prbuf, 0))) + prbuf.substr(1)
	elif not drop and islower(cat(prbuf, 0)):
		prbuf = chr(toupper(cat(prbuf, 0))) + prbuf.substr(1)
	prbuf = prbuf.substr(0, MAXSTR - 1)	# prbuf[MAXSTR-1] = '\0';
	return prbuf


## drop:
##	Put something down
static func drop() -> void:
	var ch: int
	var obj: Thing

	ch = chat(hero.y, hero.x)
	if ch != FLOOR and ch != PASSAGE:
		after = false
		await Io.msg("there is something there already")
		return
	obj = await Pack.get_item("drop", 0)
	if obj == null:
		return
	if not await dropcheck(obj):
		return
	obj = Pack.leave_pack(obj, true, not ISMULT(obj.o_type))
	# Link it into the level object list
	lvl_obj = List._attach(lvl_obj, obj)
	INDEX(hero.y, hero.x).p_ch = obj.o_type
	INDEX(hero.y, hero.x).p_flags |= F_DROPPED
	obj.o_pos.copy_from(hero)
	if obj.o_type == AMULET:
		amulet = false
	await Io.msg("dropped %s", [inv_name(obj, true)])


## dropcheck:
##	Do special checks for dropping or unweilding|unwearing|unringing
static func dropcheck(obj: Thing) -> bool:
	if obj == null:
		return true
	if obj != cur_armor and obj != cur_weapon \
			and obj != cur_ring[LEFT] and obj != cur_ring[RIGHT]:
		return true
	if (obj.o_flags & ISCURSED) != 0:
		await Io.msg("you can't.  It appears to be cursed")
		return false
	if obj == cur_weapon:
		cur_weapon = null
	elif obj == cur_armor:
		await Armor.waste_time()
		cur_armor = null
	else:
		cur_ring[LEFT if obj == cur_ring[LEFT] else RIGHT] = null
		match obj.o_which:
			R_ADDSTR:
				Misc.chg_str(-obj.o_arm)
			R_SEEINVIS:
				Daemons.unsee()
				Daemon.extinguish(D_UNSEE)
	return true


## new_thing:
##	Return a new thing
static func new_thing() -> Thing:
	var cur: Thing
	var r: int

	cur = List.new_item()
	cur.o_hplus = 0
	cur.o_dplus = 0
	cur.o_damage = "0x0"
	cur.o_hurldmg = "0x0"
	cur.o_arm = 11
	cur.o_count = 1
	cur.o_group = 0
	cur.o_flags = 0
	# Decide what kind of object it will be
	# If we haven't had food for a while, let it be food.
	match (2 if no_food > 3 else pick_one(things, NUMTHINGS)):
		0:
			cur.o_type = POTION
			cur.o_which = pick_one(pot_info, MAXPOTIONS)
		1:
			cur.o_type = SCROLL
			cur.o_which = pick_one(scr_info, MAXSCROLLS)
		2:
			cur.o_type = FOOD
			no_food = 0
			if rnd(10) != 0:
				cur.o_which = 0
			else:
				cur.o_which = 1
		3:
			Weapons.init_weapon(cur, pick_one(weap_info, MAXWEAPONS))
			r = rnd(100)
			if r < 10:
				cur.o_flags |= ISCURSED
				cur.o_hplus -= rnd(3) + 1
			elif r < 15:
				cur.o_hplus += rnd(3) + 1
		4:
			cur.o_type = ARMOR
			cur.o_which = pick_one(arm_info, MAXARMORS)
			cur.o_arm = a_class[cur.o_which]
			r = rnd(100)
			if r < 20:
				cur.o_flags |= ISCURSED
				cur.o_arm += rnd(3) + 1
			elif r < 28:
				cur.o_arm -= rnd(3) + 1
		5:
			cur.o_type = RING
			cur.o_which = pick_one(ring_info, MAXRINGS)
			match cur.o_which:
				R_ADDSTR, R_PROTECT, R_ADDHIT, R_ADDDAM:
					cur.o_arm = rnd(3)
					if cur.o_arm == 0:
						cur.o_arm = -1
						cur.o_flags |= ISCURSED
				R_AGGR, R_TELEPORT:
					cur.o_flags |= ISCURSED
		6:
			cur.o_type = STICK
			cur.o_which = pick_one(ws_info, MAXSTICKS)
			Sticks.fix_stick(cur)
		_:
			if MASTER:
				# C: debug("Picked a bad kind of object"); wait_for(' ');
				# unreachable (pick_one() returns 0..NUMTHINGS-1), so
				# push_error instead (blocking.json port_nonblocking).
				if wizard:
					push_error("Picked a bad kind of object")
	return cur


## pick_one:
##	Pick an item out of a list of nitems possible objects
static func pick_one(info: Array[ObjInfo], nitems: int) -> int:
	var end: int	# &info[nitems], as an index
	var start: int	# info, as an index
	var i: int
	var ip: int	# the moving info pointer, as an index

	start = 0
	ip = start
	end = nitems
	i = rnd(100)
	while ip < end:
		if i < info[ip].oi_prob:
			break
		ip += 1
	if ip == end:
		if MASTER:
			if wizard:
				# C: msg(); unreachable with the fixed tables, so push_error
				# instead (blocking.json port_nonblocking).
				push_error(sprintf("bad pick_one: %d from %d items", [i, nitems]))
				ip = start
				while ip < end:
					push_error(sprintf("%s: %d%%", [info[ip].oi_name, info[ip].oi_prob]))
					ip += 1
		ip = start
	return ip - start


## discovered:
##	list what the player has discovered in this game of a certain type
static func discovered() -> void:
	var ch: int
	var disc_list: bool

	while true:
		disc_list = false
		if not terse:
			await Io.addmsg("for ")
		await Io.addmsg("what type")
		if not terse:
			await Io.addmsg(" of object do you want a list")
		await Io.msg("? (* for all)")
		ch = await Io.readchar()
		match ch:
			ESCAPE:
				await Io.msg("")
				return
			POTION, SCROLL, RING, STICK, ord("*"):
				disc_list = true
			_:
				if terse:
					await Io.msg("Not a type")
				else:
					await Io.msg("Please type one of %c%c%c%c (ESCAPE to quit)",
						[POTION, SCROLL, RING, STICK])
		if disc_list:	# } while (!disc_list);
			break
	if ch == ord("*"):
		await print_disc(POTION)
		await add_line("", null)
		await print_disc(SCROLL)
		await add_line("", null)
		await print_disc(RING)
		await add_line("", null)
		await print_disc(STICK)
		await end_line()
	else:
		await print_disc(ch)
		await end_line()


## print_disc:
##	Print what we've discovered of type 'type'
static func print_disc(type_: int) -> void:
	var info: Array[ObjInfo] = []	# NULL
	var maxnum := 0
	var num_found: int
	# static int order[MAX4(MAXSCROLLS, MAXPOTIONS, MAXRINGS, MAXSTICKS)];
	# set_order() writes every entry read below, so a local array will do.
	var order: Array[int] = []
	order.resize(maxi(maxi(MAXSCROLLS, MAXPOTIONS), maxi(MAXRINGS, MAXSTICKS)))

	match type_:
		SCROLL:
			maxnum = MAXSCROLLS
			info = scr_info
		POTION:
			maxnum = MAXPOTIONS
			info = pot_info
		RING:
			maxnum = MAXRINGS
			info = ring_info
		STICK:
			maxnum = MAXSTICKS
			info = ws_info
	set_order(order, maxnum)
	_print_disc_obj.o_count = 1
	_print_disc_obj.o_flags = 0
	num_found = 0
	for i in range(maxnum):
		if info[order[i]].oi_know or info[order[i]].oi_guess != null:
			_print_disc_obj.o_type = type_
			_print_disc_obj.o_which = order[i]
			await add_line("%s", inv_name(_print_disc_obj, false))
			num_found += 1
	if num_found == 0:
		await add_line(nothing(type_), null)


## set_order:
##	Set up order for list
static func set_order(order: Array[int], numthings: int) -> void:
	var i: int
	var r: int
	var t: int

	i = 0
	while i < numthings:
		order[i] = i
		i += 1

	i = numthings
	while i > 0:
		r = rnd(i)
		t = order[i - 1]
		order[i - 1] = order[r]
		order[r] = t
		i -= 1


## add_line:
##	Add a line to the list of discoveries
##	fmt and arg are char *: a String or null.
static func add_line(fmt: Variant, arg: Variant) -> int:
	var tw: Curses.CWindow
	var sw: Curses.CWindow
	var x: int
	var y: int
	var prompt := "--Press space to continue--"

	if _things_line_cnt == 0:
		wclear(hw)
		if inv_type == INV_SLOW:
			mpos = 0
	if inv_type == INV_SLOW:
		if cat(fmt, 0) != 0:
			if await Io.msg(fmt, [arg]) == ESCAPE:
				return ESCAPE
		_things_line_cnt += 1
	else:
		if _add_line_maxlen < 0:
			_add_line_maxlen = prompt.length()
		if _things_line_cnt >= LINES - 1 or fmt == null:
			if inv_type == INV_OVER and fmt == null and not _things_newpage:
				await Io.msg("")
				refresh()
				tw = newwin(_things_line_cnt + 1, _add_line_maxlen + 2, 0, COLS - _add_line_maxlen - 3)
				sw = subwin(tw, _things_line_cnt + 1, _add_line_maxlen + 1, 0, COLS - _add_line_maxlen - 2)
				y = 0
				while y <= _things_line_cnt:
					wmove(sw, y, 0)
					x = 0
					while x <= _add_line_maxlen:
						waddch(sw, mvwinch(hw, y, x))
						x += 1
					y += 1
				wmove(tw, _things_line_cnt, 1)
				waddstr(tw, prompt)
				# if there are lines below, use 'em
				if LINES > NUMLINES:
					if NUMLINES + _things_line_cnt > LINES:
						mvwin(tw, LINES - (_things_line_cnt + 1), COLS - _add_line_maxlen - 3)
					else:
						mvwin(tw, NUMLINES, 0)
				touchwin(tw)
				wrefresh(tw)
				await Io.wait_for(ord(" "))
				if Mdport.md_hasclreol():
					werase(tw)
					leaveok(tw, true)
					wrefresh(tw)
				delwin(tw)	# fails (tw still has the subwindow sw), as in ncurses
				touchwin(stdscr)
			else:
				wmove(hw, LINES - 1, 0)
				waddstr(hw, prompt)
				wrefresh(hw)
				await Io.wait_for(ord(" "))
				clearok(curscr, true)
				wclear(hw)
				touchwin(stdscr)
			_things_newpage = true
			_things_line_cnt = 0
			_add_line_maxlen = prompt.length()
		if fmt != null and not (_things_line_cnt == 0 and cat(fmt, 0) == 0):
			mvwprintw(hw, _things_line_cnt, 0, fmt, [arg])
			_things_line_cnt += 1
			y = getcury(hw)
			x = getcurx(hw)
			if _add_line_maxlen < x:
				_add_line_maxlen = x
			_things_lastfmt = fmt
			# C keeps the pointers. end_line() only reads them right after
			# the single add_line() of a list, before prbuf / inv_temp can
			# change, so the strings' values are equivalent. A NULL arg only
			# ever comes with a format that has no conversion.
			_things_lastarg = arg if arg != null else ""	# REQUEST: Variant (C.md)
	return ~ESCAPE


## end_line:
##	End the list of lines
static func end_line() -> void:
	if inv_type != INV_SLOW:
		if _things_line_cnt == 1 and not _things_newpage:
			mpos = 0
			await Io.msg(_things_lastfmt, [_things_lastarg])
		else:
			await add_line(null, null)
	_things_line_cnt = 0
	_things_newpage = false


## nothing:
##	Set up prbuf so that message for "nothing found" is there
static func nothing(type_: int) -> String:
	var tystr: Variant = null	# char *

	if terse:
		prbuf = "Nothing"
	else:
		prbuf = "Haven't discovered anything"
	if type_ != ord("*"):
		# sp = &prbuf[strlen(prbuf)];
		match type_:
			POTION:
				tystr = "potion"
			SCROLL:
				tystr = "scroll"
			RING:
				tystr = "ring"
			STICK:
				tystr = "stick"
		prbuf += sprintf(" about any %ss", [tystr])
	return prbuf


## nameit:
##	Give the proper name to a potion, stick, or ring
##	prfunc is a PRF_* id (C: char *(*prfunc)(THING *)).
static func nameit(obj: Thing, type_: String, which: String, op: ObjInfo,
		prfunc: StringName) -> void:
	if op.oi_know or op.oi_guess != null:
		if obj.o_count == 1:
			prbuf = sprintf("A %s ", [type_])
		else:
			prbuf = sprintf("%d %ss ", [obj.o_count, type_])
		# pb = &prbuf[strlen(prbuf)];
		if op.oi_know:
			prbuf += sprintf("of %s%s(%s)", [op.oi_name, _prfunc(prfunc, obj), which])
		elif op.oi_guess != null:
			prbuf += sprintf("called %s%s(%s)", [op.oi_guess, _prfunc(prfunc, obj), which])
	elif obj.o_count == 1:
		prbuf = sprintf("A%s %s %s", [Misc.vowelstr(which), which, type_])
	else:
		prbuf = sprintf("%d %s %ss", [obj.o_count, which, type_])


## nullstr:
##	Return a pointer to a null-length string
static func nullstr(ignored: Thing) -> String:
	# NOOP(ignored);
	return ""


## (*prfunc)(obj): call nameit()'s function pointer by id.
static func _prfunc(prfunc: StringName, obj: Thing) -> String:
	match prfunc:
		PRF_NULLSTR:
			return nullstr(obj)
		PRF_RING_NUM:
			return Rings.ring_num(obj)
		PRF_CHARGE_STR:
			return Sticks.charge_str(obj)
	push_error("nameit: call through a bad function pointer")
	return ""


## pr_list:
##	List possible potions, scrolls, etc. for wizard.
##	(#ifdef MASTER: only the wizard commands call it)
static func pr_list() -> void:
	var ch: int

	if not terse:
		await Io.addmsg("for ")
	await Io.addmsg("what type")
	if not terse:
		await Io.addmsg(" of object do you want a list")
	await Io.msg("? ")
	ch = await Io.readchar()
	match ch:
		POTION:
			await pr_spec(pot_info, MAXPOTIONS)
		SCROLL:
			await pr_spec(scr_info, MAXSCROLLS)
		RING:
			await pr_spec(ring_info, MAXRINGS)
		STICK:
			await pr_spec(ws_info, MAXSTICKS)
		ARMOR:
			await pr_spec(arm_info, MAXARMORS)
		WEAPON:
			await pr_spec(weap_info, MAXWEAPONS)
		_:
			return


## pr_spec:
##	Print specific list of possible items to choose from
##	(#ifdef MASTER)
static func pr_spec(info: Array[ObjInfo], nitems: int) -> void:
	var endp: int	# &info[nitems], as an index
	var ip: int	# the moving info pointer, as an index
	var i: int
	var lastprob: int

	ip = 0
	endp = nitems
	lastprob = 0
	i = ord("0")
	while ip < endp:
		if i == ord("9") + 1:
			i = ord("a")
		prbuf = sprintf("%c: %%s (%d%%%%)", [i, info[ip].oi_prob - lastprob])
		lastprob = info[ip].oi_prob
		await add_line(prbuf, info[ip].oi_name)
		ip += 1
		i += 1
	await end_line()
