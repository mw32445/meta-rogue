## Tests of the PC Rogue-style item menus (RogueBase.menus, Pack.get_item). The C
## oracle cannot judge them, so these play short games and check the screens.
##   godot --headless --path godot --script res://tests/menus_test.gd
## Prints one line per failed check and a summary; exit status 1 on any failure.
extends SceneTree

const R := preload("res://rogue/rogue_base.gd")

var _passed := 0
var _failed := 0
var _screens: Array[String] = []
var _done := false
var _dir := ""


func _initialize() -> void:
	_dir = OS.get_user_data_dir().path_join("menus_test")
	DirAccess.make_dir_recursive_absolute(_dir)
	_test_wield()
	_test_nothing_appropriate()
	_test_escape()
	_test_whole_pack_and_invalid()
	_test_pages()
	_test_identify_nothing()
	_test_classic_unchanged()
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)
	print("menus_test: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(what: String, ok: bool, detail: Variant = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL %s %s" % [what, str(detail)])


## Play keys in a new game (seed 1) with the menus on; returns stdout. _screens
## gets the screen at every key read.
func _play(keys: Array, menus := true, lo: Variant = null) -> String:
	R.reset()
	var cs := Curses.new()
	cs.replay = true
	var k := PackedInt32Array()
	for c in keys:
		k.append(c if c is int else String(c).unicode_at(0))
	cs.script_keys = k
	R.cs = cs
	R.env_time = 1000000000
	R.env_pid = 1 - 1000000000
	R.env_name = "rodney"
	R.env_home = "./"
	R.env_uid = 1000
	R.env_cwd = _dir
	R.env_sandbox = true
	R.env_rogueopts = null
	R.MASTER = false
	R.fixes = false
	R.guild = lo != null
	R.loadout = lo
	R.menus = menus
	R.argv = PackedStringArray(["rogue"])
	_screens = []
	_done = false
	cs.step_hook = func(_key: int) -> void:
		if not cs.curses_gone:
			var t := ""
			for y in R.NUMLINES:
				for x in R.NUMCOLS:
					var c: int = cs.curscr.get_cell(y, x) & 0xFF
					t += char(c) if c >= 32 and c < 127 else "?"
				t += "\n"
			_screens.append(t)
	cs.script_finished.connect(func() -> void: _done = true)
	cs.program_exited.connect(func(_st: int) -> void: _done = true)
	var game := func() -> void:
		await Main.main()
		_done = true
	game.call()
	var guard := k.size() + 2
	while not _done and guard > 0:
		cs.feed()
		guard -= 1
	var out := cs.stdout_bytes.get_string_from_ascii()
	cs.abandon()
	R.cs = null
	R.menus = false
	R.guild = false
	R.loadout = null
	return out


## The screen when key number n (1-based) was read, i.e. after the keys before it.
func _screen(n: int) -> String:
	return _screens[n - 1] if n >= 1 and n <= _screens.size() else ""


func _test_wield() -> void:
	_play(["w", "d", " "])
	var s := _screen(2)
	_check("wield: the question at once", s.contains("Which object do you want to wield?"), s)
	_check("wield: the weapons listed", s.contains("c) A +1,+1 mace") and s.contains("d) A +1,+0 short bow")
		and s.contains(" +0,+0 arrows"), s)
	_check("wield: no food or armour in the list", not s.contains("a) Some food")
		and not s.contains("ring mail"), s)
	_check("wield: a letter picks it", _screen(3).contains("wielding a +1,+0 short bow (d)"), _screen(3))


func _test_nothing_appropriate() -> void:
	_play(["r", " "])
	var s := _screen(2)
	_check("read with no scrolls: nothing appropriate, no question",
		s.contains("You don't have anything appropriate") and not s.contains("Which object"), s)


func _test_escape() -> void:
	_play(["e", "\u001b", "i", " "])
	_check("eat: the food listed", _screen(2).contains("a) Some food"), _screen(2))
	_check("eat: Escape cancels and the map is back", not _screen(3).contains("a) Some food")
		and not _screen(3).contains("Which object"), _screen(3))


func _test_whole_pack_and_invalid() -> void:
	_play(["w", "*", "x", " ", "\u001b"])
	var s := _screen(3)
	_check("*: the whole pack", s.contains("a) Some food") and s.contains("b) ") and s.contains("c) A +1,+1 mace"), s)
	_check("an invalid letter is refused", _screen(4).contains("'x' is not a valid item"), _screen(4))


func _test_pages() -> void:
	# 5 issued + 14 potions + 18 scrolls = 37 items: two pages of 21
	var potions := []
	for p in 14:
		potions.append({"which": p, "count": 1})
	var scrolls := []
	for p in 18:
		scrolls.append({"which": p, "count": 1})
	_play(["d", " ", "\u001b"], true, {"maxpack": 40, "potions": potions, "scrolls": scrolls})
	var p1 := _screen(2)
	var p2 := _screen(3)
	_check("pages: page 1 has a --More--", p1.contains("--More--") and p1.contains("a) Some food")
		and not p1.contains("K) "), p1)
	_check("pages: space shows page 2", p2.contains("K) ") and not p2.contains("a) Some food"), p2)


func _test_identify_nothing() -> void:
	# a scroll of identify potion (S_ID_POTION = 5) with no potion: read it, and the
	# "you must identify something" loop must end (n_objs = 0)
	_play(["r", "f", " ", " ", "i", " "], true, {"scrolls": [{"which": 5, "count": 1}]})
	var seen := ""
	for s in _screens:
		seen += s
	_check("identify with nothing to identify ends", seen.contains("You don't have anything appropriate")
		and _done and _screens.size() >= 5, _screens.size())


func _test_classic_unchanged() -> void:
	_play(["w", " "], false)
	_check("menus off: the original question", _screen(2).contains("Which object do you want to wield? (* for list)")
		and not _screen(2).contains("c) A +1,+1 mace"), _screen(2))
