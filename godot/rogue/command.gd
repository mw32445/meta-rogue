## command.c: Read and execute the user commands
##
## @(#)command.c	4.73 (Berkeley) 08/06/83
##
## The persistent statics of command() (countch, direction, newcount) are
## RogueBase._command_countch, _command_direction and _command_newcount.
class_name Command
extends RogueBase

## CTRL('~') (the MASTER "charge a stick" command)
const CTRL_TILDE := 0x1E


## command:
##	Process the user commands
static func command() -> void:
	var ch := 0
	var ntimes := 1			# Number of player moves
	var fp: Place			# C: char *fp = &flat(y, x)
	var mp: Thing
	var obj: Thing
	var found: int
	var item: Thing

	if on(player, ISHASTE):
		ntimes += 1
	# Let the daemons start up
	await Daemon.do_daemons(BEFORE())
	await Daemon.do_fuses(BEFORE())
	while ntimes != 0:		# C: while (ntimes--)
		ntimes -= 1
		again = false
		if has_hit:
			await Io.endmsg()
			has_hit = false
		# these are illegal things for the player to be, so if any are
		# set, someone's been poking in memeory
		if on(player, ISSLOW | ISGREED | ISINVIS | ISREGEN | ISTARGET):
			await exit(1)
			return

		await Misc.look(true)
		if not running:
			door_stop = false
		await Io.status()
		lastscore = purse
		move(hero.y, hero.x)
		if not ((running or count != 0) and jump):
			refresh()			# Draw screen
		take = 0
		after = true
		# Read command or continue run
		if MASTER:
			if wizard:
				noscore = 1		# TRUE
		if no_command == 0:
			if running or to_death:
				ch = runch
			elif count != 0:
				ch = _command_countch
			else:
				ch = await Io.readchar()
				move_on = false
				if mpos != 0:		# Erase message if its there
					await Io.msg("")
		else:
			ch = ord(".")
		if no_command != 0:
			no_command -= 1
			if no_command == 0:
				player.t_flags |= ISRUN
				await Io.msg("you can move again")
		else:
			# check for prefixes
			_command_newcount = false
			if isdigit(ch):
				count = 0
				_command_newcount = true
				while isdigit(ch):
					count = count * 10 + (ch - ord("0"))
					if count > 255:
						count = 255
					ch = await Io.readchar()
				_command_countch = ch
				# turn off count for commands which don't make sense
				# to repeat
				match ch:
					CTRL_B, CTRL_H, CTRL_J, \
					CTRL_K, CTRL_L, CTRL_N, \
					CTRL_U, CTRL_Y, \
					ord("."), ord("a"), ord("b"), ord("h"), ord("j"), \
					ord("k"), ord("l"), ord("m"), ord("n"), ord("q"), \
					ord("r"), ord("s"), ord("t"), ord("u"), ord("y"), \
					ord("z"), ord("B"), ord("C"), ord("H"), ord("I"), \
					ord("J"), ord("K"), ord("L"), ord("N"), ord("U"), \
					ord("Y"):
						pass
					CTRL_D, CTRL_A:
						# C: these two cases exist only #ifdef MASTER;
						# otherwise they take the default
						if not MASTER:
							count = 0
					_:
						count = 0
			# execute a command
			if count != 0 and not running:
				count -= 1
			if ch != ord("a") and ch != ESCAPE and not (running or count != 0 or to_death):
				l_last_comm = last_comm
				l_last_dir = last_dir
				l_last_pick = last_pick
				last_comm = ch
				last_dir = 0
				last_pick = null
			# C: over: (`goto over` re-dispatches: continue; leaving the
			# switch: break)
			while true:
				match ch:
					ord(","):
						obj = null
						found = 0
						obj = lvl_obj
						while obj != null:
							if obj.o_pos.y == hero.y and obj.o_pos.x == hero.x:
								found = 1
								break
							obj = obj.l_next

						if found != 0:
							if await levit_check():
								pass
							else:
								await Pack.pick_up(to_schar(obj.o_type))
						else:
							if not terse:
								await Io.addmsg("there is ")
							await Io.addmsg("nothing here")
							if not terse:
								await Io.addmsg(" to pick up")
							await Io.endmsg()
					ord("!"):
						await Main.shell()
					ord("h"):
						await Move.do_move(0, -1)
					ord("j"):
						await Move.do_move(1, 0)
					ord("k"):
						await Move.do_move(-1, 0)
					ord("l"):
						await Move.do_move(0, 1)
					ord("y"):
						await Move.do_move(-1, -1)
					ord("u"):
						await Move.do_move(-1, 1)
					ord("b"):
						await Move.do_move(1, -1)
					ord("n"):
						await Move.do_move(1, 1)
					ord("H"):
						Move.do_run(ord("h"))
					ord("J"):
						Move.do_run(ord("j"))
					ord("K"):
						Move.do_run(ord("k"))
					ord("L"):
						Move.do_run(ord("l"))
					ord("Y"):
						Move.do_run(ord("y"))
					ord("U"):
						Move.do_run(ord("u"))
					ord("B"):
						Move.do_run(ord("b"))
					ord("N"):
						Move.do_run(ord("n"))
					CTRL_H, CTRL_J, CTRL_K, CTRL_L, \
					CTRL_Y, CTRL_U, CTRL_B, CTRL_N:
						if not on(player, ISBLIND):
							door_stop = true
							firstmove = true
						if count != 0 and not _command_newcount:
							ch = _command_direction
						else:
							ch += (ord("A") - CTRL_A)
							_command_direction = ch
						continue	# C: goto over
					ord("F"), ord("f"):
						if ch == ord("F"):
							kamikaze = true
							# FALLTHROUGH
						if not await Misc.get_dir():
							after = false
							break	# C: break (out of the switch)
						delta.y += hero.y
						delta.x += hero.x
						mp = moat(delta.y, delta.x)
						if mp == null or (not Chase.see_monst(mp) and not on(player, SEEMONST)):
							if not terse:
								await Io.addmsg("I see ")
							await Io.msg("no monster there")
							after = false
						elif Chase.diag_ok(hero, delta):
							to_death = true
							max_hit = 0
							mp.t_flags |= ISTARGET
							ch = dir_ch
							runch = ch
							continue	# C: goto over
					ord("t"):
						if not await Misc.get_dir():
							after = false
						else:
							await Weapons.missile(delta.y, delta.x)
					ord("a"):
						if last_comm == 0:
							await Io.msg("you haven't typed a command yet")
							after = false
						else:
							ch = last_comm
							again = true
							continue	# C: goto over
					ord("q"):
						await Potions.quaff()
					ord("Q"):
						after = false
						q_comm = true
						await Main.quit(0)
						q_comm = false
					ord("i"):
						after = false
						await Pack.inventory(pack, 0)
					ord("I"):
						after = false
						await Pack.picky_inven()
					ord("d"):
						await Things.drop()
					ord("r"):
						await Scrolls.read_scroll()
					ord("e"):
						await Misc.eat()
					ord("w"):
						await Weapons.wield()
					ord("W"):
						await Armor.wear()
					ord("T"):
						await Armor.take_off()
					ord("P"):
						await Rings.ring_on()
					ord("R"):
						await Rings.ring_off()
					ord("o"):
						await Options.option()
						after = false
					ord("c"):
						await call_()
						after = false
					ord(">"):
						after = false
						await d_level()
					ord("<"):
						after = false
						await u_level()
					ord("?"):
						after = false
						await help()
					ord("/"):
						after = false
						await identify()
					ord("s"):
						await search()
					ord("z"):
						if await Misc.get_dir():
							await Sticks.do_zap()
						else:
							after = false
					ord("D"):
						after = false
						await Things.discovered()
					CTRL_P:
						after = false
						await Io.msg(huh)
					CTRL_R:
						after = false
						clearok(curscr, true)
						wrefresh(curscr)
					ord("v"):
						after = false
						await Io.msg("version %s. (mctesq was here)", [release])
					ord("S"):
						after = false
						await Save.save_game()
					ord("."):
						pass			# Rest command
					ord(" "):
						after = false	# "Legal" illegal command
					ord("^"):
						after = false
						if await Misc.get_dir():
							delta.y += hero.y
							delta.x += hero.x
							fp = INDEX(delta.y, delta.x)
							if not terse:
								await Io.addmsg("You have found ")
							if chat(delta.y, delta.x) != TRAP:
								await Io.msg("no trap there")
							elif on(player, ISHALU):
								await Io.msg(tr_name[rnd(NTRAPS)])
							else:
								await Io.msg(tr_name[fp.p_flags & F_TMASK])
								fp.p_flags |= F_SEEN
					ord("+"):
						if MASTER:
							after = false
							if wizard:
								wizard = false
								Potions.turn_see(true)
								await Io.msg("not wizard any more")
							else:
								wizard = bool(await Wizard.passwd())
								if wizard:
									noscore = 1		# TRUE
									Potions.turn_see(false)
									await Io.msg("you are suddenly as smart as Ken Arnold in dungeon #%d", [dnum])
								else:
									await Io.msg("sorry")
						else:
							# C: without MASTER there is no '+' case: otherwise
							after = false
							await illcom(ch)
					ESCAPE:	# Escape
						door_stop = false
						count = 0
						after = false
						again = false
					ord("m"):
						move_on = true
						if not await Misc.get_dir():
							after = false
						else:
							ch = dir_ch
							_command_countch = dir_ch
							continue	# C: goto over
					ord(")"):
						await current(cur_weapon, "wielding", null)
					ord("]"):
						await current(cur_armor, "wearing", null)
					ord("="):
						await current(cur_ring[LEFT], "wearing",
							"(L)" if terse else "on left hand")
						await current(cur_ring[RIGHT], "wearing",
							"(R)" if terse else "on right hand")
					ord("@"):
						stat_msg = true
						await Io.status()
						stat_msg = false
						after = false
					_:
						after = false
						# C: #ifdef MASTER if (wizard) switch (ch) {...} else
						# #endif illcom(ch);
						if MASTER and wizard:
							match ch:
								ord("|"):
									await Io.msg("@ %d,%d", [hero.y, hero.x])
								ord("C"):
									await Wizard.create_obj()
								ord("$"):
									await Io.msg("inpack = %d", [inpack])
								CTRL_G:
									await Pack.inventory(lvl_obj, 0)
								CTRL_W:
									await Wizard.whatis(false, 0)
								CTRL_D:
									level += 1
									await NewLevel.new_level()
								CTRL_A:
									level -= 1
									await NewLevel.new_level()
								CTRL_F:
									await Wizard.show_map()
								CTRL_T:
									await Wizard.teleport()
								CTRL_E:
									await Io.msg("food left: %d", [food_left])
								CTRL_C:
									Passages.add_pass()
								CTRL_X:
									Potions.turn_see(on(player, SEEMONST))
								CTRL_TILDE:
									item = await Pack.get_item("charge", STICK)
									if item != null:
										item.o_charges = 10000
								CTRL_I:
									for i in range(9):
										await Potions.raise_level()
									# Give him a sword (+1,+1)
									obj = List.new_item()
									Weapons.init_weapon(obj, TWOSWORD)
									obj.o_hplus = 1
									obj.o_dplus = 1
									await Pack.add_pack(obj, true)
									cur_weapon = obj
									# And his suit of armor
									obj = List.new_item()
									obj.o_type = ARMOR
									obj.o_which = PLATE_MAIL
									obj.o_arm = -5
									obj.o_flags |= ISKNOW
									obj.o_count = 1
									obj.o_group = 0
									cur_armor = obj
									await Pack.add_pack(obj, true)
								ord("*"):
									await Things.pr_list()
								_:
									await illcom(ch)
						else:
							await illcom(ch)
				break
			# turn off flags if no longer needed
			if not running:
				door_stop = false
		# If he ran into something to take, let him pick it up.
		if take != 0:
			await Pack.pick_up(take)
		if not running:
			door_stop = false
		if not after:
			ntimes += 1
	await Daemon.do_daemons(AFTER())
	await Daemon.do_fuses(AFTER())
	if ISRING(LEFT, R_SEARCH):
		await search()
	elif ISRING(LEFT, R_TELEPORT) and rnd(50) == 0:
		await Wizard.teleport()
	if ISRING(RIGHT, R_SEARCH):
		await search()
	elif ISRING(RIGHT, R_TELEPORT) and rnd(50) == 0:
		await Wizard.teleport()


## illcom:
##	What to do with an illegal command
static func illcom(ch: int) -> void:
	save_msg = false
	count = 0
	await Io.msg("illegal command '%s'", [unctrl(ch)])
	save_msg = true


## search:
##	player gropes about him to find hidden things.
static func search() -> void:
	var fp: Place			# C: char *fp = &flat(y, x)
	var ey: int
	var ex: int
	var probinc: int
	var found: bool
	var foundone: bool

	ey = hero.y + 1
	ex = hero.x + 1
	probinc = (3 if on(player, ISHALU) else 0)
	probinc += (2 if on(player, ISBLIND) else 0)
	found = false
	for y in range(hero.y - 1, ey + 1):
		for x in range(hero.x - 1, ex + 1):
			if y == hero.y and x == hero.x:
				continue
			fp = INDEX(y, x)
			if not ((fp.p_flags & F_REAL) != 0):
				# C: the cases end in `goto foundone` (the '|'/'-' case
				# falls into it); the label's code runs below
				foundone = false
				match chat(y, x):
					124, 45:	# '|' '-'
						if rnd(5 + probinc) == 0:
							INDEX(y, x).p_ch = DOOR
							await Io.msg("a secret door")
							foundone = true
					FLOOR:
						if rnd(2 + probinc) == 0:
							INDEX(y, x).p_ch = TRAP
							if not terse:
								await Io.addmsg("you found ")
							if on(player, ISHALU):
								await Io.msg(tr_name[rnd(NTRAPS)])
							else:
								await Io.msg(tr_name[fp.p_flags & F_TMASK])
								fp.p_flags |= F_SEEN
							foundone = true	# C: goto foundone
					32:	# ' '
						if rnd(3 + probinc) == 0:
							INDEX(y, x).p_ch = PASSAGE
							foundone = true	# C: goto foundone
				if foundone:
					# C: foundone:
					found = true
					fp.p_flags |= F_REAL
					count = 0		# C: count = FALSE
					running = false
	if found:
		await Misc.look(false)


## help:
##	Give single character help, or the whole mess if he wants it
static func help() -> void:
	var helpch: int
	var numprint: int
	var cnt: int

	await Io.msg("character you want help for (* for all): ")
	helpch = await Io.readchar()
	mpos = 0
	# If its not a *, print the right help string
	# or an error if he typed a funny character.
	if helpch != ord("*"):
		move(0, 0)
		for strp: HList in helpstr:
			if strp.h_desc == null:
				break
			if strp.h_ch == helpch:
				lower_msg = true
				await Io.msg("%s%s", [unctrl(strp.h_ch), strp.h_desc])
				lower_msg = false
				return
		await Io.msg("unknown character '%s'", [unctrl(helpch)])
		return
	# Here we print help for everything.
	# Then wait before we return to command mode
	numprint = 0
	for strp: HList in helpstr:
		if strp.h_desc == null:
			break
		if strp.h_print:
			numprint += 1
	if (numprint & 1) != 0:		# round odd numbers up
		numprint += 1
	numprint /= 2
	if numprint > LINES - 1:
		numprint = LINES - 1

	wclear(hw)
	cnt = 0
	for strp: HList in helpstr:
		if strp.h_desc == null:
			break
		if strp.h_print:
			wmove(hw, cnt % numprint, COLS / 2 if cnt >= numprint else 0)
			if strp.h_ch != 0:
				waddstr(hw, unctrl(strp.h_ch))
			waddstr(hw, strp.h_desc)
			cnt += 1
			if cnt >= numprint * 2:
				break
	wmove(hw, LINES - 1, 0)
	waddstr(hw, "--Press space to continue--")
	wrefresh(hw)
	await Io.wait_for(ord(" "))
	clearok(stdscr, true)
	# refresh();
	await Io.msg("")
	touchwin(stdscr)
	wrefresh(stdscr)


## static struct h_list ident_list[] (identify): the characters, ending with
## the '\0' terminator, and their descriptions (h_print is always FALSE).
const IDENT_LIST_CH: Array[int] = [
	124, 45, GOLD, STAIRS, DOOR, FLOOR, PLAYER, PASSAGE, TRAP, POTION, SCROLL,
	FOOD, WEAPON, 32, ARMOR, AMULET, RING, STICK, 0,
]
const IDENT_LIST_DESC: Array[String] = [
	"wall of a room", "wall of a room", "gold", "a staircase", "door",
	"room floor", "you", "passage", "trap", "potion", "scroll", "food",
	"weapon", "solid rock", "armor", "the Amulet of Yendor", "ring",
	"wand or staff", "",
]


## identify:
##	Tell the player what a certain thing is.
static func identify() -> void:
	var ch: int
	var hp: int			# C: struct h_list *hp, an index into ident_list
	var str_: String

	await Io.msg("what do you want identified? ")
	ch = await Io.readchar()
	mpos = 0
	if ch == ESCAPE:
		await Io.msg("")
		return
	if isupper(ch):
		str_ = monsters[ch - ord("A")].m_name
	else:
		str_ = "unknown character"
		hp = 0
		while IDENT_LIST_CH[hp] != 0:
			if IDENT_LIST_CH[hp] == ch:
				str_ = IDENT_LIST_DESC[hp]
				break
			hp += 1
	await Io.msg("'%s': %s", [unctrl(ch), str_])


## d_level:
##	He wants to go down a level
static func d_level() -> void:
	if await levit_check():
		return
	if chat(hero.y, hero.x) != STAIRS:
		await Io.msg("I see no way down")
	else:
		level += 1
		seenstairs = false
		await NewLevel.new_level()


## u_level:
##	He wants to go up a level
static func u_level() -> void:
	if await levit_check():
		return
	if chat(hero.y, hero.x) == STAIRS:
		if amulet:
			level -= 1
			if level == 0:
				await Rip.total_winner()
			await NewLevel.new_level()
			await Io.msg("you feel a wrenching sensation in your gut")
		else:
			await Io.msg("your way is magically blocked")
	else:
		await Io.msg("I see no way up")


## levit_check:
##	Check to see if she's levitating, and if she is, print an
##	appropriate message.
static func levit_check() -> bool:
	if not on(player, ISLEVIT):
		return false
	await Io.msg("You can't.  You're floating off the ground!")
	return true


## call:
##	Allow a user to call a potion, scroll, or ring something
##
##	char **guess points at op->oi_guess (guess_op != null) or at
##	obj->o_label (guess_op == null); bool *know is &op->oi_know (know_op)
##	or NULL. `elsewise == *guess` compares pointers: it is true exactly
##	when elsewise was loaded from *guess (elsewise_is_guess).
static func call_() -> void:
	var obj: Thing
	var op: ObjInfo = null
	var guess_op: ObjInfo = null
	var elsewise: Variant = null
	var elsewise_is_guess := false
	var know_op: ObjInfo = null
	var norm := false

	obj = await Pack.get_item("call", CALLABLE)
	# Make certain that it is somethings that we want to wear
	if obj == null:
		return
	match obj.o_type:
		RING:
			op = ring_info[obj.o_which]
			elsewise = r_stones[obj.o_which]
			norm = true	# C: goto norm
		POTION:
			op = pot_info[obj.o_which]
			elsewise = p_colors[obj.o_which]
			norm = true	# C: goto norm
		SCROLL:
			op = scr_info[obj.o_which]
			elsewise = s_names[obj.o_which]
			norm = true	# C: goto norm
		STICK:
			op = ws_info[obj.o_which]
			elsewise = ws_made[obj.o_which]
			norm = true	# C: norm: (below)
		FOOD:
			await Io.msg("you can't call that anything")
			return
		_:
			guess_op = null		# guess = &obj->o_label
			know_op = null
			elsewise = obj.o_label
			elsewise_is_guess = true
	if norm:
		# C: norm:
		know_op = op		# know = &op->oi_know
		guess_op = op		# guess = &op->oi_guess
		if guess_op.oi_guess != null:
			elsewise = guess_op.oi_guess
			elsewise_is_guess = true
	if know_op != null and know_op.oi_know:
		await Io.msg("that has already been identified")
		return
	if elsewise != null and elsewise_is_guess:
		if not terse:
			await Io.addmsg("Was ")
		await Io.msg("called \"%s\"", [elsewise])
	if terse:
		await Io.msg("call it: ")
	else:
		await Io.msg("what do you want to call it? ")

	if elsewise == null:
		prbuf = ""
	else:
		prbuf = elsewise
	var r: Array = await Options.get_str(prbuf, stdscr)
	prbuf = r[1]
	if r[0] == NORM:
		# free(*guess); *guess = malloc(strlen(prbuf) + 1); strcpy(*guess, prbuf)
		if guess_op != null:
			guess_op.oi_guess = prbuf
		else:
			obj.o_label = prbuf


## current:
##	Print the current weapon/armor
static func current(cur: Thing, how: String, where: Variant) -> void:
	after = false
	if cur != null:
		if not terse:
			await Io.addmsg("you are %s (", [how])
		inv_describe = false
		var nm: String = await Things.inv_name(cur, true)
		await Io.addmsg("%c) %s", [cur.o_packch, nm])
		inv_describe = true
		if where != null:
			await Io.addmsg(" %s", [where])
		await Io.endmsg()
	else:
		if not terse:
			await Io.addmsg("you are ")
		await Io.addmsg("%s nothing", [how])
		if where != null:
			await Io.addmsg(" %s", [where])
		await Io.endmsg()
