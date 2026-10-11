## Checks of the bug fixes (RogueBase.fixes, docs/FIXES.md) that the key scripts in
## harness/corpus/fixes cannot express with their "# expect-" lines:
##   - FIX 1: TerminalView maps keypad 5 to '.' (rest) with the fixes, and to KEY_B2
##     (which md_readchar() turns into 'u') without them;
##   - FIX 8: with the fixes, every level of the seeds whose ^D descents made conn()
##     hang is connected (and so is every level of some ordinary seeds);
##   - FIX N12: the wizard's map (^F) stands out exactly the hidden squares (classic:
##     many more).
##
## usage: godot --headless --path godot --script res://tests/fixes_test.gd
## Exit status 0 if every check passes.
extends SceneTree

## Seeds (MASTER, wizard mode) whose plain ^D descents reach a level where conn()
## hung in 5.4.4, within 40 levels (all of them below 3000).
const HANG_SEEDS: Array[int] = [1083, 1344, 1438, 1457, 1632, 1659, 1786]

var _failed := 0
var _checks := 0
var _finished := false
var _level_errors: Array[String] = []
var _levels_seen := 0
var _standout_bad := -1
var _standout_hidden := 0


func _initialize() -> void:
	_test_keypad()
	_test_connected()
	_test_show_map()
	print("fixes_test: %d checks, %s" % [_checks, "OK" if _failed == 0 else "%d FAILED" % _failed])
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		printerr("FAILED: ", what)


# ---- FIX 1 ------------------------------------------------------------------

func _test_keypad() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_KP_5
	e.pressed = true
	RogueBase.fixes = false
	_check(TerminalView.key_code(e) == Curses.KEY_B2, "keypad 5 without the fixes: KEY_B2")
	RogueBase.fixes = true
	_check(TerminalView.key_code(e) == ord("."), "keypad 5 with the fixes: '.'")
	# the other keypad keys are unchanged
	e.keycode = KEY_KP_9
	_check(TerminalView.key_code(e) == Curses.KEY_PPAGE, "keypad 9 with the fixes: KEY_PPAGE")
	RogueBase.fixes = false


# ---- FIX 8 ------------------------------------------------------------------

func _test_connected() -> void:
	var down := PackedInt32Array()
	for i in 40:
		down.append(RogueBase.CTRL_D)
	var seeds: Array[int] = HANG_SEEDS.duplicate()
	for s in range(1, 21):
		seeds.append(s)
	for s in seeds:
		_level_errors.clear()
		_levels_seen = 0
		_play(s, down, true, PackedStringArray([""]), true, _on_step_connected)
		_check(_level_errors.is_empty(), "seed %d: every level connected (%s)" % [s, ", ".join(_level_errors)])
		_check(_levels_seen == 41, "seed %d: 41 levels generated (got %d)" % [s, _levels_seen])


func _on_step_connected(_key: int) -> void:
	_levels_seen += 1
	var err := _connectivity()
	if err != "":
		_level_errors.append("level %d: %s" % [RogueBase.level, err])


## "" if the stairs and every room can be reached from the hero, walking through
## secret doors and hidden passages too.
static func _connectivity() -> String:
	var R := RogueBase
	var seen := {}
	var start := Vector2i(R.hero.x, R.hero.y)
	var todo: Array[Vector2i] = [start]
	seen[start] = true
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.x >= R.NUMCOLS or n.y < 1 or n.y >= R.NUMLINES - 1:
				continue
			if seen.has(n) or not _passable(n.y, n.x):
				continue
			seen[n] = true
			todo.append(n)
	if not seen.has(Vector2i(R.stairs.x, R.stairs.y)):
		return "the stairs at %d,%d" % [R.stairs.y, R.stairs.x]
	for i in R.MAXROOMS:
		var rp: Room = R.rooms[i]
		if (rp.r_flags & R.ISGONE) != 0:
			continue
		var found := false
		var any := false
		for y in range(rp.r_pos.y, rp.r_pos.y + rp.r_max.y + 1):
			for x in range(rp.r_pos.x, rp.r_pos.x + rp.r_max.x + 1):
				if y < 1 or y >= R.NUMLINES - 1 or x < 0 or x >= R.NUMCOLS:
					continue
				var inside: bool
				if (rp.r_flags & R.ISMAZE) != 0:
					inside = (R.flat(y, x) & R.F_PASS) != 0
				else:
					inside = y > rp.r_pos.y and y < rp.r_pos.y + rp.r_max.y - 1 \
						and x > rp.r_pos.x and x < rp.r_pos.x + rp.r_max.x - 1
				if inside:
					any = true
					if seen.has(Vector2i(x, y)):
						found = true
		if any and not found:
			return "room %d (%s at %d,%d)" % [i, "maze" if (rp.r_flags & R.ISMAZE) != 0 else "room",
				rp.r_pos.y, rp.r_pos.x]
	return ""


static func _passable(y: int, x: int) -> bool:
	var pp: Place = RogueBase.INDEX(y, x)
	if (pp.p_flags & RogueBase.F_PASS) != 0:
		return true
	if pp.p_ch == 32 or pp.p_ch == 0:
		return false
	if pp.p_ch == ord("|") or pp.p_ch == ord("-"):
		return (pp.p_flags & RogueBase.F_REAL) == 0	# a secret door
	return true	# floor, door, stairs, trap, object


# ---- FIX N12 ----------------------------------------------------------------

func _test_show_map() -> void:
	# seed 1203, wizard: three levels down, then the map (^F) and its --More--
	var keys := PackedInt32Array([RogueBase.CTRL_D, RogueBase.CTRL_D, RogueBase.CTRL_D,
		RogueBase.CTRL_F, 32])
	for fx in [false, true]:
		_standout_bad = -1
		_standout_hidden = 0
		_play(1203, keys, true, PackedStringArray([""]), fx, _on_step_map)
		_check(_standout_hidden > 0, "N12 (fixes %s): the level has hidden squares" % fx)
		if fx:
			_check(_standout_bad == 0, "N12: with the fixes only hidden squares stand out (%d others)"
				% _standout_bad)
		else:
			_check(_standout_bad > 100, "N12: without the fixes most of the map stands out (%d squares)"
				% _standout_bad)


func _on_step_map(_key: int) -> void:
	var cs := RogueBase.cs
	var top := ""
	for x in 22:
		top += char(cs.curscr.get_cell(0, x) & 0xFF)
	if top != "---More (level map)---":
		return
	_standout_bad = 0
	for y in range(1, RogueBase.NUMLINES - 1):
		for x in RogueBase.NUMCOLS:
			var hidden := (RogueBase.flat(y, x) & RogueBase.F_REAL) == 0
			var standout := (cs.curscr.get_cell(y, x) & Curses.A_STANDOUT) != 0
			if hidden:
				_standout_hidden += 1
			if hidden != standout:
				_standout_bad += 1


# ---- running a game ---------------------------------------------------------

## One game on a key script, as tests/replay.gd runs it (without the step log);
## hook.call(key) runs at every keyboard read, before the key is used.
func _play(seed_: int, keys: PackedInt32Array, master: bool, args: PackedStringArray,
		fixes: bool, hook: Callable) -> void:
	var dir := ProjectSettings.globalize_path("user://fixes_test")
	DirAccess.make_dir_recursive_absolute(dir)
	RogueBase.reset()
	var cs := Curses.new()
	cs.replay = true
	cs.script_keys = keys
	RogueBase.cs = cs
	RogueBase.env_time = 1000000000
	RogueBase.env_pid = seed_ - 1000000000
	RogueBase.env_name = "rodney"
	RogueBase.env_home = "./"
	RogueBase.env_uid = 1000
	RogueBase.env_cwd = dir
	RogueBase.env_sandbox = true
	RogueBase.env_rogueopts = null
	RogueBase.MASTER = master
	RogueBase.fixes = fixes
	var argv := PackedStringArray(["rogue"])
	argv.append_array(args)
	RogueBase.argv = argv
	_finished = false
	cs.step_hook = hook
	cs.script_finished.connect(_on_finished)
	cs.program_exited.connect(_on_exited)
	_run_main()
	var guard := keys.size() + 2
	while not _finished and guard > 0:
		cs.feed()
		guard -= 1
	cs.abandon()
	RogueBase.cs = null
	RogueBase.MASTER = false
	RogueBase.fixes = false


func _run_main() -> void:
	await Main.main()
	_finished = true


func _on_finished() -> void:
	_finished = true


func _on_exited(_status: int) -> void:
	_finished = true
