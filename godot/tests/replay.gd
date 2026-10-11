## Replay runner: runs the game on a key script and writes the step log
## (harness/DUMP_FORMAT.md), the same one the C oracle writes.
##
## Single run:
##   godot --headless --path godot --script res://tests/replay.gd -- \
##       --keys K.txt --dump D.txt [--stdout O.bin] [--seed N] [--time T] [--name S]
##       [--home H] [--uid U] [--opts ROGUEOPTS | --no-opts] [--cwd DIR] [--full N]
##       [--master] [--arg A]...
## Batch: --batch FILE, one run per line, each line holding the options above
## (tab separated "key=value" pairs; see harness/difftest.py).
extends SceneTree

const FNV_INIT := 2166136261
const FNV_PRIME := 16777619

var _out: FileAccess
var _full_from := -1
var _step := 0
var _finished := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var batch := _arg(args, "--batch", "")
	if batch != "":
		var f := FileAccess.open(batch, FileAccess.READ)
		while not f.eof_reached():
			var line := f.get_line().strip_edges()
			if line == "" or line.begins_with("#"):
				continue
			var opts := {}
			for kv in line.split("\t"):
				var i := kv.find("=")
				if i > 0:
					opts[kv.substr(0, i)] = kv.substr(i + 1)
			_run(opts)
	else:
		var opts := {}
		var i := 0
		while i < args.size():
			var a := args[i]
			if a == "--master":
				opts["master"] = "1"
			elif a == "--no-opts":
				opts["no-opts"] = "1"
			elif a == "--arg":
				opts["arg"] = opts.get("arg", "") + ("\u001f" if opts.has("arg") else "") + args[i + 1]
				i += 1
			elif a.begins_with("--") and i + 1 < args.size():
				opts[a.substr(2)] = args[i + 1]
				i += 1
			i += 1
		_run(opts)
	quit(0)


func _arg(args: PackedStringArray, name: String, def: String) -> String:
	var i := args.find(name)
	return args[i + 1] if i >= 0 and i + 1 < args.size() else def


## One game: reset all state, run Main.main() until the key script is used
## up or the program exits, writing the step log as it goes.
func _run(o: Dictionary) -> void:
	RogueBase.reset()
	var cs := Curses.new()
	cs.replay = true
	cs.script_keys = _load_keys(o.get("keys", ""))
	RogueBase.cs = cs
	var seed_ := int(o.get("seed", "1"))
	var time_ := int(o.get("time", "1000000000"))
	RogueBase.env_time = time_
	RogueBase.env_pid = seed_ - time_
	RogueBase.env_name = o.get("name", "rodney")
	RogueBase.env_home = o.get("home", "/home/rodney/")
	RogueBase.env_uid = int(o.get("uid", "1000"))
	RogueBase.env_cwd = o.get("cwd", "")
	RogueBase.env_sandbox = true
	RogueBase.env_rogueopts = null if o.has("no-opts") or not o.has("opts") else o["opts"]
	RogueBase.MASTER = o.has("master")
	var argv := PackedStringArray(["rogue"])
	if o.has("arg"):
		argv.append_array(String(o["arg"]).split("\u001f"))
	RogueBase.argv = argv

	_out = FileAccess.open(o.get("dump", "user://replay_dump.txt"), FileAccess.WRITE)
	_full_from = int(o["full"]) if o.has("full") else -1
	_step = 0
	_finished = false
	cs.step_hook = _on_step
	cs.exit_hook = _on_exit
	cs.script_finished.connect(_on_script_end)
	cs.program_exited.connect(func(_st: int) -> void: _finished = true)

	var game := func() -> void:
		await Main.main()
		_finished = true
	game.call()
	var guard := cs.script_keys.size() + 2
	while not _finished and guard > 0:
		cs.feed()
		guard -= 1
	_out.close()
	if o.has("stdout"):
		var so := FileAccess.open(o["stdout"], FileAccess.WRITE)
		so.store_buffer(cs.stdout_bytes)
		so.close()
	cs.abandon()
	RogueBase.cs = null


func _load_keys(path: String) -> PackedInt32Array:
	var keys := PackedInt32Array()
	if path == "":
		return keys
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return keys
	for line in f.get_as_text().split("\n"):
		var t := line
		var c := t.find("#")
		if c >= 0:
			t = t.substr(0, c)
		for tok in t.split(" ", false):
			for tok2 in tok.split("\t", false):
				keys.append(int(tok2))
	return keys


func _on_script_end() -> void:
	_out.store_string("END %d\n" % _step)
	_finished = true


func _on_exit(status: int) -> void:
	_out.store_string("EXIT %d\n" % status)


func _on_step(key: int) -> void:
	var cs := RogueBase.cs
	_step += 1
	var d := digest()
	var dh := _fnv_str(d)
	var full := _full_from >= 0 and _step >= _full_from
	if cs.curses_gone:
		_out.store_string("S%d K%d R%d Z D%08x\n" % [_step, key, RogueBase.seed_, dh])
	else:
		var w := cs.curscr
		var h := FNV_INIT
		for y in RogueBase.NUMLINES:
			for x in RogueBase.NUMCOLS:
				var v: int = w.get_cell(y, x) & 0xFFFFFFFF
				for b in 4:
					h = ((h ^ ((v >> (8 * b)) & 0xFF)) * FNV_PRIME) & 0xFFFFFFFF
		var cur := "%d,%d" % [w._cury, w._curx] if cs.cursor_known else "?"
		_out.store_string("S%d K%d R%d C%s X%08x D%08x\n" % [_step, key, RogueBase.seed_, cur, h, dh])
		if full:
			var extra := "E"
			for y in RogueBase.NUMLINES:
				var row := "|"
				for x in RogueBase.NUMCOLS:
					var v: int = w.get_cell(y, x) & 0xFFFFFFFF
					var c := v & 0xFF
					row += char(c) if c >= 32 and c < 127 else "?"
					if (v & ~0xFF) != 0 or c < 32 or c >= 127:
						extra += " %d,%d=%x" % [y, x, v]
				_out.store_string(row + "|\n")
			_out.store_string(extra + "\n")
	if full:
		_out.store_string("G %s\n" % d)


static func _fnv_str(s: String) -> int:
	var h := FNV_INIT
	for i in s.length():
		h = ((h ^ (s.unicode_at(i) & 0xFF)) * FNV_PRIME) & 0xFFFFFFFF
	return h


# ---- the game-state digest (must match harness/oracle/hooks.c) -------------

static func _room_idx(rp: Room) -> int:
	if rp == null:
		return -1
	var i := RogueBase.rooms.find(rp)
	if i >= 0:
		return i
	i = RogueBase.passages.find(rp)
	if i >= 0:
		return 100 + i
	return -2


static func _list_idx(list: Thing, item: Thing) -> int:
	if item == null:
		return -1
	var i := 0
	while list != null:
		if list == item:
			return i
		list = list.l_next
		i += 1
	return -2


static func _dest_code(d: Coord) -> String:
	if d == null:
		return "-"
	if d == RogueBase.player.t_pos:
		return "h"
	var i := 0
	var op := RogueBase.lvl_obj
	while op != null:
		if d == op.o_pos:
			return "o%d" % i
		op = op.l_next
		i += 1
	for j in RogueBase.MAXROOMS:
		if d == RogueBase.rooms[j].r_gold:
			return "g%d" % j
	for j in RogueBase.MAXPASS:
		if d == RogueBase.passages[j].r_gold:
			return "G%d" % j
	i = 0
	var tp := RogueBase.mlist
	while tp != null:
		if d == tp.t_pos:
			return "m%d" % i
		tp = tp.l_next
		i += 1
	i = 0
	op = RogueBase.player.t_pack
	while op != null:
		if d == op.o_pos:
			return "k%d" % i
		op = op.l_next
		i += 1
	i = 0
	tp = RogueBase.mlist
	while tp != null:
		var j := 0
		op = tp.t_pack
		while op != null:
			if d == op.o_pos:
				return "p%d.%d" % [i, j]
			op = op.l_next
			j += 1
		tp = tp.l_next
		i += 1
	return "?"


static func digest() -> String:
	var R := RogueBase
	var p := R.player
	var s := "L%d M%d G%d F%d H%d N%d V%d C%d U%d T%d I%d A%d" % [R.level, R.max_level,
		R.purse, R.food_left, R.hungry_state, R.no_command, R.no_move, R.count,
		int(R.running), int(R.to_death), R.inpack, int(R.amulet)]
	s += " P%d,%d f%x s%d e%d l%d a%d h%d/%d d%s r%d" % [p.t_pos.y, p.t_pos.x,
		p.t_flags & 0xFFFF, p.t_stats.s_str & 0xFFFFFFFF, p.t_stats.s_exp, p.t_stats.s_lvl,
		p.t_stats.s_arm, p.t_stats.s_hpt, p.t_stats.s_maxhp, p.t_stats.s_dmg, _room_idx(p.t_room)]
	s += " W%d R%d Q%d,%d" % [_list_idx(p.t_pack, R.cur_weapon), _list_idx(p.t_pack, R.cur_armor),
		_list_idx(p.t_pack, R.cur_ring[0]), _list_idx(p.t_pack, R.cur_ring[1])]
	s += " m:"
	var tp := R.mlist
	while tp != null:
		s += "[%d %d,%d f%x h%d g%d o%d t%s r%d]" % [tp.t_type, tp.t_pos.y, tp.t_pos.x,
			tp.t_flags & 0xFFFF, tp.t_stats.s_hpt, tp.t_disguise, tp.t_oldch,
			_dest_code(tp.t_dest), _room_idx(tp.t_room)]
		tp = tp.l_next
	s += " o:"
	var op := R.lvl_obj
	while op != null:
		s += "[%d %d %d,%d c%d f%x a%d]" % [op.o_type, op.o_which, op.o_pos.y, op.o_pos.x,
			op.o_count, op.o_flags & 0xFFFFFFFF, op.o_arm]
		op = op.l_next
	s += " k:"
	op = p.t_pack
	while op != null:
		s += "[%d %d %d c%d f%x h%d d%d a%d g%d]" % [op.o_packch, op.o_type, op.o_which,
			op.o_count, op.o_flags & 0xFFFFFFFF, op.o_hplus, op.o_dplus, op.o_arm, op.o_group]
		op = op.l_next
	s += " d:"
	for i in R.MAXDAEMONS:
		var dev: DelayedAction = R.d_list[i]
		if dev.d_type != 0:
			var fname := "null" if dev.d_func == &"" else String(dev.d_func)
			s += "[%d t%d %s a%d n%d]" % [i, dev.d_type, fname, dev.d_arg, dev.d_time]
	return s
