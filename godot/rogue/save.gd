## save.c: save and restore routines
##
## @(#)save.c	4.33 (Berkeley) 06/01/83
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## The save file keeps C's header (the encrypted version string and screen
## size), followed by the port's own encoding of what state.c's rs_save_file
## writes. Exactly that state is saved, with state.c's lossy encodings: pack
## objects by index, t_dest as hero/monster/object/room gold (anything else
## becomes the hero), places' monsters by index, stdscr by cell. State that
## state.c does not save keeps its fresh-process value. The two C bugs
## (4 daemons missing from the format, passages saved as &rooms[-1]) are
## fixed here and in the oracle (docs/FIDELITY.md).
class_name Save
extends RogueBase

## vers.c: encstr[] and statlist[], the key streams of encwrite/encread
const ENCSTR: Array[int] = [192, 107, 124, 124, 96, 169, 89, 46, 39, 197, 209, 129, 43, 191,
	126, 114, 34, 93, 160, 95, 147, 61, 49, 225, 41, 146, 138, 161, 116, 59, 9, 36, 184, 204,
	47, 60, 35, 129, 172]
const STATLIST: Array[int] = [237, 107, 108, 123, 43, 132, 173, 203, 105, 100, 74, 241, 140,
	61, 52, 58, 201, 185, 225, 119, 75, 60, 202, 209, 139, 44, 44, 55, 185, 47, 82, 107, 37, 8,
	202, 12, 166]
## Marks the port's encoding after the C header (a C save file fails this check).
const BODY_MAGIC := "rogue-godot-state 1"


## save_game:
##	Implement the "save game" command
static func save_game() -> void:
	var savef: FileAccess = null
	var c := 0
	var buf := ""
	var gotfile := false

	# get file name
	mpos = 0
	while true:	# over:
		gotfile = false
		if file_name != "":
			while true:
				await Io.msg("save file (%s)? ", [file_name])
				c = await Io.readchar()
				mpos = 0
				if c == ESCAPE:
					await Io.msg("")
					return
				elif c == ord("n") or c == ord("N") or c == ord("y") or c == ord("Y"):
					break
				else:
					await Io.msg("please answer Y or N")
			if c == ord("y") or c == ord("Y"):
				addstr("Yes\n")
				refresh()
				buf = file_name
				gotfile = true

		var go_over := false
		while true:	# do { ... } while (savef == NULL)
			if not gotfile:
				mpos = 0
				await Io.msg("file name: ")
				buf = ""
				var r: Array = await Options.get_str(buf, stdscr)
				buf = r[1]
				if r[0] == QUIT:
					# quit_it:
					await Io.msg("")
					return
				mpos = 0
			gotfile = false
			# gotfile:
			# test to see if the file exists
			if _stat(buf):
				while true:
					await Io.msg("File exists.  Do you wish to overwrite it?")
					mpos = 0
					c = await Io.readchar()
					if c == ESCAPE:
						# goto quit_it
						await Io.msg("")
						return
					if c == ord("y") or c == ord("Y"):
						break
					elif c == ord("n") or c == ord("N"):
						go_over = true
						break
					else:
						await Io.msg("Please answer Y or N")
				if go_over:
					break
				await Io.msg("file name: %s", [buf])
				Mdport.md_unlink(file_name)
			file_name = buf
			var err := _open_error(file_name)
			if err == "":
				savef = FileAccess.open(cpath(file_name), FileAccess.WRITE)
				if savef == null:
					err = "Permission denied"
			if savef == null:
				await Io.msg(err)
			if savef != null:
				break
		if not go_over:
			break

	await save_file(savef)
	# NOTREACHED


## auto_save:
##	Automatically save a file.  This is used if a HUP signal is
##	recieved (the port: the window is closed mid-game)
static func auto_save(_sig: int = 0) -> void:
	var savef: FileAccess = null

	Mdport.md_ignoreallsignals()
	if file_name != "":
		if _open_error(file_name) == "":
			savef = FileAccess.open(cpath(file_name), FileAccess.WRITE)
		if savef == null and Mdport.md_unlink_open_file(file_name) >= 0 \
				and _open_error(file_name) == "":
			savef = FileAccess.open(cpath(file_name), FileAccess.WRITE)
		if savef != null:
			await save_file(savef)
	await exit(0)


## save_file:
##	Write the saved game on the file
static func save_file(savef: FileAccess) -> void:
	mvcur(0, COLS - 1, LINES - 1, 0)
	putchar(ord("\n"))
	endwin()
	MachDep.resetltchars()
	Mdport.md_chmod(file_name, 256)	# 0400
	var out := PackedByteArray()
	out.append_array(encwrite(_cbytes(version, version.length() + 1), version.length() + 1))
	out.append_array(encwrite(_cbytes("%d x %d\n" % [LINES, COLS], 80), 80))
	var body := _cbytes(BODY_MAGIC, BODY_MAGIC.length() + 1)
	body.append_array(var_to_bytes(_save_state()))
	out.append_array(encwrite(body, body.size()))
	savef.store_buffer(out)
	savef.flush()
	savef.close()
	await exit(0)


## restore:
##	Restore a saved game from a file with elaborate checks for file
##	integrity from cheaters
static func restore(file: String, _envp: Variant = null) -> bool:
	var lines := 0
	var cols := 0

	if file == "-r":
		file = file_name

	Mdport.md_tstphold()

	var path := cpath(file)
	var is_dir := file != "" and DirAccess.dir_exists_absolute(path)
	var inf: FileAccess = null
	if file != "" and not is_dir:
		inf = FileAccess.open(path, FileAccess.READ)
	if inf == null and not is_dir:
		# perror(file)
		printerr("%s: %s" % [file, "No such file or directory" if not FileAccess.file_exists(path) \
			else "Permission denied"])
		return false
	var syml := MachDep.is_symlink(file)

	# fopen() of a directory succeeds and every read of it fails
	var buf := encread(PackedByteArray(), version.length() + 1, inf)
	if _cstr(buf) != version:
		printf("Sorry, saved game is out of date.\n")
		return false
	buf = encread(PackedByteArray(), 80, inf)
	var dims := _cstr(buf).split(" x ")
	if dims.size() == 2:
		lines = atoi(dims[0])
		cols = atoi(dims[1])

	initscr()	# Start up cursor package
	keypad(stdscr, true)

	if lines > LINES:
		endwin()
		printf("Sorry, original game was played on a screen with %d lines.\n", [lines])
		printf("Current screen only has %d lines. Unable to restore game\n", [LINES])
		return false
	if cols > COLS:
		endwin()
		printf("Sorry, original game was played on a screen with %d columns.\n", [cols])
		printf("Current screen only has %d columns. Unable to restore game\n", [COLS])
		return false

	hw = newwin(LINES, COLS, 0, 0)
	MachDep.setup()

	# rs_restore_file. C restores whatever it can read from a damaged file;
	# the port refuses it.
	var body := encread(PackedByteArray(), inf.get_length() - inf.get_position(), inf)
	var magic := _cstr(body)
	var state: Variant = null
	if magic == BODY_MAGIC:
		state = bytes_to_var(body.slice(magic.length() + 1))
	if not (state is Dictionary) or not _restore_state(state):
		endwin()
		printf("Sorry, saved game is out of date.\n")
		return false
	# we do not close the file so that we will have a hold of the
	# inode for as long as possible
	inf.close()

	if not (MASTER and wizard) and Mdport.md_unlink_open_file(file, inf) < 0:
		printf("Cannot unlink file\n")
		return false
	mpos = 0
	clearok(stdscr, true)
	# defeat multiple restarting from the same place
	# (st_nlink is always 1: the port never makes hard links)
	if not (MASTER and wizard):
		if syml:
			endwin()
			printf("\nCannot restore from a linked file\n")
			return false

	if pstats.s_hpt <= 0:
		endwin()
		printf("\n\"He's dead, Jim\"\n")
		return false

	Mdport.md_tstpresume()

	file_name = file
	clearok(curscr, true)
	await Io.msg("file name: %s", [file])
	await Main.playit()
	# NOTREACHED
	return false


## encwrite:
##	Perform an encrypted write: returns the encrypted bytes (the port's
##	callers write them to the file).
static func encwrite(start: PackedByteArray, size: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(size)
	var e1 := 0
	var e2 := 0
	var fb := 0
	for i in size:
		var c: int = start[i] if i < start.size() else 0
		out[i] = (c ^ ENCSTR[e1] ^ STATLIST[e2] ^ fb) & 0xFF
		var temp: int = ENCSTR[e1]
		e1 += 1
		fb = (fb + temp * STATLIST[e2]) & 0xFF
		e2 += 1
		if e1 == ENCSTR.size():
			e1 = 0
		if e2 == STATLIST.size():
			e2 = 0
	return out


## encread:
##	Perform an encrypted read of size bytes into a copy of start (C reads
##	into the buffer in place). As in C, nothing changes when nothing could
##	be read; after a short read the whole buffer is still decrypted.
static func encread(start: PackedByteArray, size: int, inf: FileAccess) -> PackedByteArray:
	var buf := start.duplicate()
	if buf.size() < size:
		buf.resize(size)
	if inf == null or size <= 0:
		return buf
	var got := inf.get_buffer(size)
	if got.is_empty():
		return buf
	for i in got.size():
		buf[i] = got[i]
	var e1 := 0
	var e2 := 0
	var fb := 0
	for i in size:
		buf[i] = (buf[i] ^ ENCSTR[e1] ^ STATLIST[e2] ^ fb) & 0xFF
		var temp: int = ENCSTR[e1]
		e1 += 1
		fb = (fb + temp * STATLIST[e2]) & 0xFF
		e2 += 1
		if e1 == ENCSTR.size():
			e1 = 0
		if e2 == STATLIST.size():
			e2 = 0
	return buf


## read_scrore
##	Read in the score file
static func rd_score(top_ten: Array) -> void:
	if scoreboard == null:
		return

	scoreboard.seek(0)

	for i in numscores:
		var sc = top_ten[i]
		var name := encread(_cbytes(sc.sc_name, MAXSTR), MAXSTR, scoreboard)
		sc.sc_name = _cstr(name)
		_save_scoreline = encread(_save_scoreline, 100, scoreboard)
		_scan_scoreline(_cstr(_save_scoreline), sc)

	scoreboard.seek(0)


## write_scrore
##	Read in the score file
static func wr_score(top_ten: Array) -> void:
	if scoreboard == null:
		return

	scoreboard.seek(0)

	for i in numscores:
		var sc = top_ten[i]
		_save_scoreline = PackedByteArray()
		_save_scoreline.resize(100)
		scoreboard.store_buffer(encwrite(_cbytes(sc.sc_name, MAXSTR), MAXSTR))
		var line := " %d %d %d %d %d %x \n" % [sc.sc_uid & 0xFFFFFFFF, _to_int32(sc.sc_score),
			sc.sc_flags & 0xFFFFFFFF, sc.sc_monster & 0xFFFF, _to_int32(sc.sc_level),
			sc.sc_time & 0xFFFFFFFF]
		for k in mini(line.length(), 99):
			_save_scoreline[k] = line.unicode_at(k) & 0xFF
		scoreboard.store_buffer(encwrite(_save_scoreline, 100))

	scoreboard.flush()
	scoreboard.seek(0)


# ---- helpers ----------------------------------------------------------------

## A C string in a buffer of size bytes (NUL padded; Latin-1, like the
## port's other byte I/O).
static func _cbytes(s: String, size: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size)
	for i in mini(s.length(), size):
		b[i] = s.unicode_at(i) & 0xFF
	return b


## The C string at the start of a buffer.
static func _cstr(b: PackedByteArray) -> String:
	var s := ""
	for i in b.size():
		if b[i] == 0:
			break
		s += char(b[i])
	return s


## stat(name) >= 0
static func _stat(name: String) -> bool:
	if name == "":
		return false
	var path := cpath(name)
	return FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path)


## strerror(errno) of fopen(name, "w"), or "" when it would succeed.
static func _open_error(name: String) -> String:
	if name == "":
		return "No such file or directory"
	var path := cpath(name)
	if DirAccess.dir_exists_absolute(path) or name.ends_with("/"):
		return "Is a directory"
	var dir := path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		return "No such file or directory"
	return ""


## sscanf(scoreline, " %u %d %u %hu %d %x \n", ...): assigns the fields up
## to the first one that does not match.
static func _scan_scoreline(line: String, sc) -> void:
	var pos := [0]
	var v: Variant = _scan_num(line, pos, 10)
	if v == null:
		return
	sc.sc_uid = int(v) & 0xFFFFFFFF
	v = _scan_num(line, pos, 10)
	if v == null:
		return
	sc.sc_score = _to_int32(v)
	v = _scan_num(line, pos, 10)
	if v == null:
		return
	sc.sc_flags = int(v) & 0xFFFFFFFF
	v = _scan_num(line, pos, 10)
	if v == null:
		return
	sc.sc_monster = int(v) & 0xFFFF
	v = _scan_num(line, pos, 10)
	if v == null:
		return
	sc.sc_level = _to_int32(v)
	v = _scan_num(line, pos, 16)
	if v == null:
		return
	sc.sc_time = int(v) & 0xFFFFFFFF


## One scanf number conversion: leading white space, an optional sign, an
## optional 0x for base 16, then digits. null when there are no digits.
static func _scan_num(s: String, pos: Array, base: int) -> Variant:
	var i: int = pos[0]
	while i < s.length() and isspace(s.unicode_at(i)):
		i += 1
	var neg := false
	if i < s.length() and (s[i] == "-" or s[i] == "+"):
		neg = s[i] == "-"
		i += 1
	if base == 16 and i + 1 < s.length() and s[i] == "0" and (s[i + 1] == "x" or s[i + 1] == "X") \
			and i + 2 < s.length() and _digit(s.unicode_at(i + 2), 16) >= 0:
		i += 2
	var v := 0
	var start := i
	while i < s.length() and _digit(s.unicode_at(i), base) >= 0:
		v = (v * base + _digit(s.unicode_at(i), base)) & 0xFFFFFFFFFFFF
		i += 1
	if i == start:
		return null
	pos[0] = i
	return -v if neg else v


static func _digit(c: int, base: int) -> int:
	var d := -1
	if c >= ord("0") and c <= ord("9"):
		d = c - ord("0")
	elif c >= ord("a") and c <= ord("f"):
		d = c - ord("a") + 10
	elif c >= ord("A") and c <= ord("F"):
		d = c - ord("A") + 10
	return d if d >= 0 and d < base else -1


# ---- the state (state.c: rs_save_file / rs_restore_file) ---------------------

static func _coord(c: Coord) -> Array:
	return [c.x, c.y]


static func _set_coord(c: Coord, r: Array) -> void:
	c.x = r[0]
	c.y = r[1]


static func _stats(s: Stats) -> Array:
	return [s.s_str, s.s_exp, s.s_lvl, s.s_arm, s.s_hpt, s.s_dmg, s.s_maxhp]


static func _set_stats(s: Stats, r: Array) -> void:
	s.s_str = r[0]
	s.s_exp = r[1]
	s.s_lvl = r[2]
	s.s_arm = r[3]
	s.s_hpt = r[4]
	s.s_dmg = r[5]
	s.s_maxhp = r[6]


## rs_write_room_reference: rooms[i] -> i, passages[i] -> MAXROOMS + i
## (the oracle's fix), anything else -> -1.
static func _room_ref(rp: Room) -> int:
	var i := rooms.find(rp)
	if i >= 0:
		return i
	i = passages.find(rp)
	if i >= 0:
		return MAXROOMS + i
	return -1


static func _room_at(i: int) -> Room:
	if i >= 0 and i < MAXROOMS:
		return rooms[i]
	if i >= MAXROOMS and i < MAXROOMS + MAXPASS:
		return passages[i - MAXROOMS]
	return null


static func _room(r: Room) -> Array:
	var ex := []
	for e in r.r_exit:
		ex.append(_coord(e))
	return [_coord(r.r_pos), _coord(r.r_max), _coord(r.r_gold), r.r_goldval, r.r_flags,
		r.r_nexits, ex]


static func _set_room(r: Room, a: Array) -> void:
	_set_coord(r.r_pos, a[0])
	_set_coord(r.r_max, a[1])
	_set_coord(r.r_gold, a[2])
	r.r_goldval = a[3]
	r.r_flags = a[4]
	r.r_nexits = a[5]
	for k in r.r_exit.size():
		_set_coord(r.r_exit[k], a[6][k])


## find_list_ptr: the index of item in the list, -1 if it is not there
static func _list_index(list: Thing, item: Thing) -> int:
	var i := 0
	while list != null:
		if list == item:
			return i
		list = list.l_next
		i += 1
	return -1


## get_list_item: the i-th item of the list, null if there is none
static func _list_item(list: Thing, i: int) -> Thing:
	var n := 0
	while list != null:
		if n == i:
			return list
		list = list.l_next
		n += 1
	return null


static func _object(o: Thing) -> Array:
	return [o.o_type, _coord(o.o_pos), o.o_launch, o.o_packch, o.o_damage, o.o_hurldmg,
		o.o_count, o.o_which, o.o_hplus, o.o_dplus, o.o_arm, o.o_flags, o.o_group, o.o_label]


static func _object_list(l: Thing) -> Array:
	var out := []
	while l != null:
		out.append(_object(l))
		l = l.l_next
	return out


## rs_read_object_list: new zeroed objects, linked in order
static func _read_object_list(a: Array) -> Thing:
	var head: Thing = null
	var previous: Thing = null
	for r in a:
		var o := List.new_item()
		o.l_prev = previous
		if previous != null:
			previous.l_next = o
		o.o_type = r[0]
		_set_coord(o.o_pos, r[1])
		o.o_launch = r[2]
		o.o_packch = r[3]
		o.o_damage = r[4]
		o.o_hurldmg = r[5]
		o.o_count = r[6]
		o.o_which = r[7]
		o.o_hplus = r[8]
		o.o_dplus = r[9]
		o.o_arm = r[10]
		o.o_flags = r[11]
		o.o_group = r[12]
		o.o_label = r[13]
		if previous == null:
			head = o
		previous = o
	return head


## rs_write_thing's t_dest: [0,0] NULL, [0,1] the hero, [1,i] monster i,
## [2,i] object i on the level, [3,i] rooms[i]'s gold; anything else is
## saved as the hero ("chase the hero anyway").
static func _dest(d: Coord) -> Array:
	if d == hero:
		return [0, 1]
	if d == null:
		return [0, 0]
	var i := 0
	var tp := mlist
	while tp != null:
		if d == tp.t_pos:
			return [1, i]
		tp = tp.l_next
		i += 1
	i = 0
	var op := lvl_obj
	while op != null:
		if d == op.o_pos:
			return [2, i]
		op = op.l_next
		i += 1
	for j in MAXROOMS:
		if d == rooms[j].r_gold:
			return [3, j]
	return [0, 1]


static func _thing(t: Thing) -> Array:
	return [_coord(t.t_pos), t.t_turn, t.t_type, t.t_disguise, t.t_oldch, _dest(t.t_dest),
		t.t_flags, _stats(t.t_stats), _room_ref(t.t_room), _object_list(t.t_pack)]


## rs_read_thing: into an existing Thing (the player is read in place)
static func _read_thing(t: Thing, a: Array) -> void:
	_set_coord(t.t_pos, a[0])
	t.t_turn = a[1]
	t.t_type = a[2]
	t.t_disguise = a[3]
	t.t_oldch = a[4]
	var listid: int = a[5][0]
	var index: int = a[5][1]
	t.t_reserved = -1
	if listid == 0:	# hero or NULL
		t.t_dest = hero if index == 1 else null
	elif listid == 1:	# monster/thing (resolved by _fix_thing)
		t.t_dest = null
		t.t_reserved = index
	elif listid == 2:	# object
		var item := _list_item(lvl_obj, index)
		if item != null:
			t.t_dest = item.o_pos
	elif listid == 3:	# gold
		t.t_dest = rooms[index].r_gold
	else:
		t.t_dest = null
	t.t_flags = a[6]
	_set_stats(t.t_stats, a[7])
	t.t_room = _room_at(a[8])
	t.t_pack = _read_object_list(a[9])


## rs_fix_thing: a monster chasing another monster
static func _fix_thing(t: Thing) -> void:
	if t.t_reserved < 0:
		return
	var item := _list_item(mlist, t.t_reserved)
	if item != null:
		t.t_dest = item.t_pos


static func _obj_info(table: Array[ObjInfo]) -> Array:
	var out := []
	for oi in table:
		out.append([oi.oi_prob, oi.oi_worth, oi.oi_guess, oi.oi_know])
	return out


static func _set_obj_info(table: Array[ObjInfo], a: Array) -> void:
	for n in mini(a.size(), table.size()):
		table[n].oi_prob = a[n][0]
		table[n].oi_worth = a[n][1]
		table[n].oi_guess = a[n][2]
		table[n].oi_know = a[n][3]


## rs_save_file
static func _save_state() -> Dictionary:
	var st := {}
	st["flags"] = [after, again, noscore, seenstairs, amulet, door_stop, fight_flush, firstmove,
		got_ltc, has_hit, in_shell, inv_describe, jump, kamikaze, lower_msg, move_on, msg_esc,
		passgo, playing, q_comm, running, save_msg, see_floor, stat_msg, terse, to_death,
		tombstone, int(wizard) if MASTER else 0]
	st["pack_used"] = pack_used.duplicate()
	st["chars"] = [dir_ch, runch, take, l_last_comm, l_last_dir, last_comm, last_dir]
	st["strings"] = [file_name, huh, prbuf, whoami, fruit, home]
	st["p_colors"] = p_colors.duplicate()
	st["r_stones"] = r_stones.duplicate()
	st["s_names"] = s_names.duplicate()
	st["ws_made"] = ws_made.duplicate()
	st["ws_type"] = ws_type.duplicate()
	st["ints"] = [orig_dsusp, n_objs, ntraps, hungry_state, inpack, inv_type, level, max_level,
		mpos, no_food, count, food_left, lastscore, no_command, no_move, purse, quiet, vf_hit,
		dnum, seed]
	st["coords"] = [_coord(delta), _coord(oldpos), _coord(stairs)]

	st["player"] = _thing(player)
	st["refs"] = [_list_index(player.t_pack, cur_armor), _list_index(player.t_pack, cur_ring[0]),
		_list_index(player.t_pack, cur_ring[1]), _list_index(player.t_pack, cur_weapon),
		_list_index(player.t_pack, l_last_pick), _list_index(player.t_pack, last_pick)]

	st["lvl_obj"] = _object_list(lvl_obj)
	var ml := []
	var tp := mlist
	while tp != null:
		ml.append(_thing(tp))
		tp = tp.l_next
	st["mlist"] = ml

	var pl := PackedInt32Array()
	pl.resize(places.size() * 3)
	for i in places.size():
		var pp: Place = places[i]
		pl[3 * i] = pp.p_ch
		pl[3 * i + 1] = pp.p_flags
		pl[3 * i + 2] = -1 if pp.p_monst == null else _list_index(mlist, pp.p_monst)
	st["places"] = pl

	st["max_stats"] = _stats(max_stats)
	var rl := []
	for r in rooms:
		rl.append(_room(r))
	st["rooms"] = rl
	st["oldrp"] = _room_ref(oldrp)
	var pa := []
	for r in passages:
		pa.append(_room(r))
	st["passages"] = pa

	var ms := []
	for m in monsters:
		ms.append(_stats(m.m_stats))
	st["monsters"] = ms
	st["things"] = _obj_info(things)
	st["arm_info"] = _obj_info(arm_info)
	st["pot_info"] = _obj_info(pot_info)
	st["ring_info"] = _obj_info(ring_info)
	st["scr_info"] = _obj_info(scr_info)
	st["weap_info"] = _obj_info(weap_info)
	st["ws_info"] = _obj_info(ws_info)

	var dl := []
	for d: DelayedAction in d_list:
		dl.append([d.d_type, String(d.d_func), d.d_arg, d.d_time])
	st["d_list"] = dl
	st["between"] = between
	st["nh"] = _coord(nh)
	st["group"] = group

	var height := getmaxy(stdscr)
	var width := getmaxx(stdscr)
	var win := PackedInt64Array()
	for row in height:
		for col in width:
			win.append(mvwinch(stdscr, row, col))
	st["window"] = [height, width, win]
	return st


## rs_restore_file (false: the data is not a saved game)
static func _restore_state(st: Dictionary) -> bool:
	for k in ["flags", "pack_used", "chars", "strings", "p_colors", "r_stones", "s_names",
			"ws_made", "ws_type", "ints", "coords", "player", "refs", "lvl_obj", "mlist",
			"places", "max_stats", "rooms", "oldrp", "passages", "monsters", "things",
			"arm_info", "pot_info", "ring_info", "scr_info", "weap_info", "ws_info", "d_list",
			"between", "nh", "group", "window"]:
		if not st.has(k):
			return false

	var f: Array = st["flags"]
	after = f[0]
	again = f[1]
	noscore = f[2]
	seenstairs = f[3]
	amulet = f[4]
	door_stop = f[5]
	fight_flush = f[6]
	firstmove = f[7]
	got_ltc = f[8]
	has_hit = f[9]
	in_shell = f[10]
	inv_describe = f[11]
	jump = f[12]
	kamikaze = f[13]
	lower_msg = f[14]
	move_on = f[15]
	msg_esc = f[16]
	passgo = f[17]
	playing = f[18]
	q_comm = f[19]
	running = f[20]
	save_msg = f[21]
	see_floor = f[22]
	stat_msg = f[23]
	terse = f[24]
	to_death = f[25]
	tombstone = f[26]
	if MASTER:
		wizard = f[27] != 0
	for i in 26:
		pack_used[i] = st["pack_used"][i]
	var ch: Array = st["chars"]
	dir_ch = ch[0]
	runch = ch[1]
	take = ch[2]
	l_last_comm = ch[3]
	l_last_dir = ch[4]
	last_comm = ch[5]
	last_dir = ch[6]
	var s: Array = st["strings"]
	file_name = s[0]
	huh = s[1]
	prbuf = s[2]
	whoami = s[3]
	fruit = s[4]
	home = s[5]
	for i in MAXPOTIONS:
		p_colors[i] = st["p_colors"][i]
	for i in MAXRINGS:
		r_stones[i] = st["r_stones"][i]
	for i in MAXSCROLLS:
		s_names[i] = st["s_names"][i]
	for i in MAXSTICKS:
		ws_made[i] = st["ws_made"][i]
		ws_type[i] = st["ws_type"][i]
	var n: Array = st["ints"]
	orig_dsusp = n[0]
	n_objs = n[1]
	ntraps = n[2]
	hungry_state = n[3]
	inpack = n[4]
	inv_type = n[5]
	level = n[6]
	max_level = n[7]
	mpos = n[8]
	no_food = n[9]
	count = n[10]
	food_left = n[11]
	lastscore = n[12]
	no_command = n[13]
	no_move = n[14]
	purse = n[15]
	quiet = n[16]
	vf_hit = n[17]
	dnum = n[18]
	seed = n[19]
	_set_coord(delta, st["coords"][0])
	_set_coord(oldpos, st["coords"][1])
	_set_coord(stairs, st["coords"][2])

	# the player is read before the level's objects: an object t_dest of the
	# player's resolves against the old (empty) lvl_obj, as in C
	_read_thing(player, st["player"])
	var refs: Array = st["refs"]
	cur_armor = _list_item(player.t_pack, refs[0])
	cur_ring[0] = _list_item(player.t_pack, refs[1])
	cur_ring[1] = _list_item(player.t_pack, refs[2])
	cur_weapon = _list_item(player.t_pack, refs[3])
	l_last_pick = _list_item(player.t_pack, refs[4])
	last_pick = _list_item(player.t_pack, refs[5])

	lvl_obj = _read_object_list(st["lvl_obj"])
	var head: Thing = null
	var previous: Thing = null
	for a in st["mlist"]:
		var tp := List.new_item()
		tp.l_prev = previous
		if previous != null:
			previous.l_next = tp
		_read_thing(tp, a)
		if previous == null:
			head = tp
		previous = tp
	mlist = head
	_fix_thing(player)
	var t := mlist
	while t != null:
		_fix_thing(t)
		t = t.l_next

	var pl: PackedInt32Array = st["places"]
	for i in places.size():
		var pp: Place = places[i]
		pp.p_ch = pl[3 * i]
		pp.p_flags = pl[3 * i + 1]
		var mi := pl[3 * i + 2]
		pp.p_monst = null if mi == -1 else _list_item(mlist, mi)

	_set_stats(max_stats, st["max_stats"])
	for i in MAXROOMS:
		_set_room(rooms[i], st["rooms"][i])
	oldrp = _room_at(st["oldrp"])
	for i in MAXPASS:
		_set_room(passages[i], st["passages"][i])

	for i in monsters.size():
		_set_stats(monsters[i].m_stats, st["monsters"][i])
	_set_obj_info(things, st["things"])
	_set_obj_info(arm_info, st["arm_info"])
	_set_obj_info(pot_info, st["pot_info"])
	_set_obj_info(ring_info, st["ring_info"])
	_set_obj_info(scr_info, st["scr_info"])
	_set_obj_info(weap_info, st["weap_info"])
	_set_obj_info(ws_info, st["ws_info"])

	var dl: Array = st["d_list"]
	for i in MAXDAEMONS:
		var d: DelayedAction = d_list[i]
		d.d_type = dl[i][0]
		d.d_func = StringName(dl[i][1])
		d.d_arg = dl[i][2]
		d.d_time = dl[i][3]
	between = st["between"]
	_set_coord(nh, st["nh"])
	group = st["group"]

	# rs_read_window: every saved cell is put back with mvwaddch
	var w: Array = st["window"]
	var height := getmaxy(stdscr)
	var width := getmaxx(stdscr)
	var cells: PackedInt64Array = w[2]
	var k := 0
	for row in int(w[0]):
		for col in int(w[1]):
			if row < height and col < width:
				mvwaddch(stdscr, row, col, cells[k])
			k += 1
	return true
