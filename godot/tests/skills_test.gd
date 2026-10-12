## Tests of the Fighters' Guild's skills in the game (RogueBase.skills, Skills;
## docs/GUILD.md, "Skills"), which the C oracle cannot judge. Each check plays a
## game in guild mode with the fixes on, as the playable game does, one key at a
## time: every key runs the game to its next wait for a key (a --More-- is
## answered with a space). Between keys the test sets the scene (a monster beside
## the hero, an item in the pack) and reads the state and the screen. Every skill
## is tried with it and without it.
##   godot --headless --path godot --script res://tests/skills_test.gd
## Prints one line per failed check and a summary; exit status 1 on any failure.
## Works in (and removes) the folder "skills_test" of the project's user data.
extends SceneTree

const R := preload("res://rogue/rogue_base.gd")
## The seed: the hero starts at row 10, column 44 of a lit room whose floor is
## rows 9 to 13, columns 30 to 49 (nothing near the hero).
const SEED := 8

var _passed := 0
var _failed := 0
var _cs: Curses = null
var _done := false
var _dir := ""
## The screens at every wait since it was last emptied, and stdout.
var _seen := ""


func _initialize() -> void:
	_dir = OS.get_user_data_dir().path_join("skills_test")
	_clean()
	DirAccess.make_dir_recursive_absolute(_dir)
	_test_frost()
	_test_sure_sight()
	_test_high_intellect()
	_test_low_light()
	_test_throw_menu()
	_test_throw_items()
	_test_throw_rings()
	_test_throw_wands()
	_test_throw_worn()
	_test_coin()
	_test_pockets()
	_test_cult_asleep()
	_test_cult_bites()
	_test_cult_confirm()
	_test_cult_banished()
	_test_recovery()
	_test_save()
	_clean()
	print("skills_test: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _check(what: String, ok: bool, detail: Variant = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
		print("FAIL %s %s" % [what, str(detail)])


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(_dir):
		return
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


# ---- the game, a key at a time ---------------------------------------------------

## A new game with these skills, up to its first key; with restore, the saved
## game instead. No monster is left on the level and none wanders in: the checks
## make the ones they want.
func _start(skills: Dictionary, restore := false) -> void:
	R.reset()
	_cs = Curses.new()
	R.cs = _cs
	R.env_time = 1000000000
	R.env_pid = SEED - 1000000000
	R.env_name = "rodney"
	R.env_home = "./"
	R.env_uid = 1000
	R.env_cwd = _dir
	R.env_sandbox = true
	R.env_rogueopts = null
	R.fixes = true
	R.guild = true
	R.loadout = null if restore else {"skills": skills}
	R.argv = PackedStringArray(["rogue", "-r"] if restore else ["rogue"])
	_done = false
	_seen = ""
	_cs.program_exited.connect(func(_st: int) -> void: _done = true)
	var game := func() -> void:
		await Main.main()
		_done = true
	game.call()
	_look()
	if not restore:
		Daemon.extinguish(R.D_SWANDER)
		Daemon.kill_daemon(R.D_ROLLWAND)
		while R.mlist != null:
			_remove(R.mlist)


func _end() -> void:
	if _cs != null:
		_cs.abandon()
	_cs = null
	R.cs = null
	R.fixes = false
	R.guild = false
	R.loadout = null
	R.menus = false


## One key; then the game runs to its next wait, and a --More-- gets a space.
func _key(k: Variant) -> void:
	if _done:
		return
	_cs.push_key(k if k is int else String(k).unicode_at(0))
	_look()
	var guard := 40
	while not _done and _row(0).contains("--More--") and guard > 0:
		_cs.push_key(32)
		_look()
		guard -= 1


func _keys(s: String) -> void:
	for c in s:
		_key(c)


## Rest n turns (fewer if the game ends).
func _rest(n: int) -> void:
	for i in n:
		_key(".")


## Answer the end of a game (the tombstone, the scores) until it is over.
func _finish() -> void:
	var guard := 12
	while not _done and guard > 0:
		_key("\n")
		guard -= 1


func _look() -> void:
	for y in R.NUMLINES:
		_seen += _row(y) + "\n"
	if _cs != null:
		_seen += _cs.stdout_bytes.get_string_from_ascii()
		_cs.stdout_bytes.clear()


## Whether the screens since _seen was emptied, or stdout, showed a text (any case:
## messages start with a capital).
func _saw(text: String) -> bool:
	return _seen.to_lower().contains(text.to_lower())


## A row of the screen (as the player sees it).
func _row(y: int) -> String:
	if _cs == null or _cs.curses_gone:
		return ""
	var t := ""
	for x in R.NUMCOLS:
		var c: int = _cs.curscr.get_cell(y, x) & 0xFF
		t += char(c) if c >= 32 and c < 127 else "?"
	return t


## The character on the screen at y, x.
func _at(y: int, x: int) -> String:
	return _row(y).substr(x, 1)


# ---- the scene -------------------------------------------------------------------

func _remove(tp: Thing) -> void:
	R.INDEX(tp.t_pos.y, tp.t_pos.x).p_monst = null
	R.mvaddch(tp.t_pos.y, tp.t_pos.x, tp.t_oldch)
	R.mlist = List._detach(R.mlist, tp)


## A new monster (as new_monster() makes one) at the hero + (dy, dx), an empty
## floor square: asleep, or running after the hero.
func _monster(kind: String, dy: int, dx: int, run := false) -> Thing:
	var cp := Coord.new()
	cp.y = R.hero.y + dy
	cp.x = R.hero.x + dx
	_check("the scene: %s at %d,%d on an empty floor" % [kind, cp.y, cp.x],
		R.chat(cp.y, cp.x) == R.FLOOR and R.moat(cp.y, cp.x) == null, char(R.chat(cp.y, cp.x)))
	var tp := List.new_item()
	Monsters.new_monster(tp, kind.unicode_at(0), cp)
	if run:
		tp.t_flags |= R.ISRUN
		tp.t_dest = R.hero
	return tp


## A monster 2 to the hero's left for things to be thrown at (the only one): a
## thousand hit points; thrown things always hit it, or never (hit false).
func _target(kind := "Z", hit := true) -> Thing:
	while R.mlist != null:
		_remove(R.mlist)
	var tp := _monster(kind, 0, -2)
	tp.t_stats.s_arm = 20 if hit else -100
	tp.t_stats.s_hpt = 1000
	tp.t_stats.s_maxhp = 1000
	return tp


## A new object in the pack, made as Loadout makes them; returns its letter.
## arm: a ring's bonus; charges: a stick's.
func _give(type_: int, which: int, arm := 1, charges := 3) -> String:
	var obj := Loadout._new_obj()
	obj.o_type = type_
	obj.o_which = which
	obj.o_flags |= R.ISKNOW
	match type_:
		R.STICK:
			Sticks.fix_stick(obj)
			obj.o_charges = charges
			obj.o_damage = "0x0"	# a wand's or a staff's blow alike: the hero's strength's 1
		R.RING:
			obj.o_arm = arm
		R.ARMOR:
			obj.o_arm = R.a_class[which]
		R.WEAPON:
			Weapons.init_weapon(obj, which)
	# add_pack waits for nothing when it is silent and the pack has room
	Callable(Pack, "add_pack").call(obj, true)
	return char(obj.o_packch)


## The pack's object of a kind, or null.
func _in_pack(type_: int, which: int) -> Thing:
	var op := R.pack
	while op != null:
		if op.o_type == type_ and op.o_which == which:
			return op
		op = op.l_next
	return null


## How many objects of a type lie on the level.
func _on_floor(type_: int) -> int:
	var n := 0
	var op := R.lvl_obj
	while op != null:
		if op.o_type == type_:
			n += 1
		op = op.l_next
	return n


## A hero hard to kill: for the checks that let monsters hit the hero.
func _tough() -> void:
	R.pstats.s_hpt = 5000
	R.max_hp = 5000


# ---- Frost Resistance, Frost Immunity --------------------------------------------

func _test_frost() -> void:
	# An ice monster beside the hero that always hits; the hero starves 60 turns on.
	for has in [false, true]:
		_start({"frost resistance": 1} if has else {})
		_tough()
		var ice := _monster("I", 0, -1, true)
		ice.t_stats.s_lvl = 20
		R.food_left = -R.STARVETIME + 60
		_rest(3)
		var frozen := R.no_command
		_finish()
		if has:
			_check("frost resistance: frozen past the hypothermia limit, alive", frozen > 0
				and not _saw("hypothermia"), _seen.right(600))
			_check("frost resistance: frozen until the hero starves (%d turns to go)" % R.no_command,
				_saw("starvation") and R.no_command > R.BORE_LEVEL, R.no_command)
		else:
			_check("no frost resistance: death by hypothermia", _saw("hypothermia"), _seen.right(600))
		_end()
	_start({"frost resistance": 1, "frost immunity": 1})
	var ice := _monster("I", 0, -1, true)
	ice.t_stats.s_lvl = 20
	var frozen := false
	for i in 20:
		_key(".")
		frozen = frozen or R.no_command > 0
	_check("frost immunity: never frozen", not frozen and not _done)
	_check("frost immunity: a brief chill", _saw("you feel a brief chill"))
	_end()


# ---- Sure Sight, High Intellect ---------------------------------------------------

func _test_sure_sight() -> void:
	for has in [false, true]:
		_start({"sure sight": 1} if has else {})
		var l := _give(R.POTION, R.P_BLIND)
		_keys("q" + l)
		var blind := R.on(R.player, R.ISBLIND)
		if has:
			_check("sure sight: the potion of blindness does not blind", not blind)
			_check("sure sight: the message", _saw("a cloak of darkness falls around you, and fades away"))
			_check("sure sight: the potion is known", R.pot_info[R.P_BLIND].oi_know)
			_check("sure sight: the potion is gone", _in_pack(R.POTION, R.P_BLIND) == null)
		else:
			_check("no sure sight: blind", blind)
		_end()


func _test_high_intellect() -> void:
	for has in [false, true]:
		_start({"high intellect": 1} if has else {})
		_tough()
		var l := _give(R.POTION, R.P_CONFUSE)
		_keys("q" + l)
		var huh := R.on(R.player, R.ISHUH)
		if has:
			_check("high intellect: the potion of confusion does not confuse", not huh)
			_check("high intellect: the message",
				_saw("you feel confused for a moment, then your mind clears"))
			_check("high intellect: the potion is known", R.pot_info[R.P_CONFUSE].oi_know)
		else:
			_check("no high intellect: confused by the potion", huh)
		R.player.t_flags &= ~R.ISHUH
		Daemon.extinguish(R.D_UNCONFUSE)
		# The medusa's gaze, beside the hero, who never saves (save_throw needs 37).
		_seen = ""
		var lvl := R.pstats.s_lvl
		R.pstats.s_lvl = -40
		_monster("M", 0, -1, true)
		_key(".")
		R.pstats.s_lvl = lvl
		huh = R.on(R.player, R.ISHUH)
		if has:
			_check("high intellect: the medusa's gaze does not confuse", not huh)
			_check("high intellect: the gaze's message", _saw("the medusa's gaze has no effect on you"),
				_seen.left(400))
		else:
			_check("no high intellect: the gaze confuses", huh and _saw("the medusa's gaze has confused you"),
				_seen.left(400))
		_end()


# ---- Low-Light Vision ---------------------------------------------------------------

func _test_low_light() -> void:
	for has in [false, true]:
		_start({"low-light vision": 1} if has else {})
		var rp: Room = R.proom
		var hy: int = R.hero.y
		var hx: int = R.hero.x
		var floor_ok := true
		for c in [Vector2i(0, -2), Vector2i(2, 0), Vector2i(2, -2), Vector2i(0, 3), Vector2i(2, 2), Vector2i(2, 3)]:
			floor_ok = floor_ok and R.chat(hy + c.x, hx + c.y) == R.FLOOR
		_check("the scene: floor around the hero", floor_ok)
		# the room dark, and on the screen as if it had never been lit
		rp.r_flags |= R.ISDARK
		for y in range(rp.r_pos.y + 1, rp.r_pos.y + rp.r_max.y - 1):
			for x in range(rp.r_pos.x + 1, rp.r_pos.x + rp.r_max.x - 1):
				if y != hy or x != hx:
					R.mvaddch(y, x, 32)
		var z := _monster("Z", 0, -2)
		_key(".")
		var n := "low-light vision: " if has else "no low-light vision: "
		var two := "." if has else " "
		_check(n + "the floor 2 away", _at(hy + 2, hx) == two and _at(hy + 2, hx + 2) == two,
			[_at(hy + 2, hx), _at(hy + 2, hx + 2)])
		_check(n + "a monster 2 away", _at(hy, hx - 2) == ("Z" if has else " "), _at(hy, hx - 2))
		_check(n + "3 away: nothing", _at(hy, hx + 3) == " ", _at(hy, hx + 3))
		_check(n + "the floor 1 away", _at(hy + 1, hx) == ".", _at(hy + 1, hx))
		_check(n + "cansee 2 away", Chase.cansee(hy, hx - 2) == has)
		_check(n + "see_monst 2 away", Chase.see_monst(z) == has)
		_check(n + "cansee 3 away: no", not Chase.cansee(hy, hx + 3))
		_check(n + "a monster 2 away is not woken", not R.on(z, R.ISRUN))
		if has:
			# a step right: what was 2 away and now is 3 away goes dark again
			_check(n + "before the step", _at(hy + 2, hx - 2) == ".", _at(hy + 2, hx - 2))
			_key("l")
			_check(n + "after the step, 3 away is dark", _at(hy + 2, hx - 2) == " " and R.hero.x == hx + 1,
				_at(hy + 2, hx - 2))
			_check(n + "after the step, 2 away shows", _at(hy + 2, hx + 3) == ".", _at(hy + 2, hx + 3))
			_check(n + "the monster, now 3 away, is still drawn (as monsters in the dark stay)",
				_at(hy, hx - 2) == "Z")
		_end()


# ---- Throw Anything -------------------------------------------------------------------

func _test_throw_menu() -> void:
	for has in [false, true]:
		_start({"throw anything": 1} if has else {})
		R.menus = true
		_keys("th")
		var s := _row(1) + _row(2) + _row(3) + _row(4) + _row(5)
		if has:
			_check("throw anything: the menu lists every item", s.contains("a) Some food")
				and s.contains("b) ") and s.contains("c) A +1,+1 mace"), s)
		else:
			_check("no throw anything: the menu lists the weapons", not s.contains("a) Some food")
				and s.contains("c) A +1,+1 mace"), s)
		_key(27)
		_end()
	# the amulet
	_start({"throw anything": 1})
	var l := _give(R.AMULET, 0)
	_target()
	_keys("th" + l)
	_check("throw anything: the amulet is refused", _saw("Not even this can be thrown."))
	_check("throw anything: the amulet stays", _in_pack(R.AMULET, 0) != null)
	_end()


func _test_throw_items() -> void:
	for has in [false, true]:
		_start({"throw anything": 1} if has else {})
		_tough()
		var n := "throw anything: " if has else "no throw anything: "
		# armour: 1x4 (+1 for the hero's strength); without the skill 0x0 (+1)
		var l := _give(R.ARMOR, R.LEATHER)
		var tp := _target()
		var armours := _on_floor(R.ARMOR)
		_keys("th" + l)
		var lost := 1000 - tp.t_stats.s_hpt
		if has:
			_check(n + "armour hits for 1x4 + 1", lost >= 2 and lost <= 5, lost)
		else:
			_check(n + "armour hits for 0x0 + 1", lost == 1, lost)
		_check(n + "the armour is used up", _in_pack(R.ARMOR, R.LEATHER) == null and _on_floor(R.ARMOR) == armours)
		# a potion of confusion
		l = _give(R.POTION, R.P_CONFUSE)
		tp = _target()
		_keys("th" + l)
		_check(n + "a potion of confusion", R.on(tp, R.ISHUH) == has, tp.t_flags)
		if has:
			_check(n + "the monster appears confused", _saw("the zombie appears confused"))
		_end()
	_start({"throw anything": 1})
	_tough()
	var n := "throw anything: "
	# healing: its level (2) in d4 back, after the hit's 1
	var l := _give(R.POTION, R.P_HEALING)
	var tp := _target()
	tp.t_stats.s_hpt = 500
	_keys("th" + l)
	_check(n + "a potion of healing", tp.t_stats.s_hpt >= 501 and tp.t_stats.s_hpt <= 507, tp.t_stats.s_hpt)
	l = _give(R.POTION, R.P_HASTE)
	tp = _target()
	_keys("th" + l)
	_check(n + "a potion of haste self", R.on(tp, R.ISHASTE))
	l = _give(R.POTION, R.P_STRENGTH)
	tp = _target()
	var st := tp.t_stats.s_str
	_keys("th" + l)
	_check(n + "a potion of gain strength", tp.t_stats.s_str == st + 1, tp.t_stats.s_str)
	l = _give(R.POTION, R.P_SEEINVIS)
	tp = _target()
	var potions := _on_floor(R.POTION)
	_keys("th" + l)
	_check(n + "a potion of see invisible: nothing, and used up", _in_pack(R.POTION, R.P_SEEINVIS) == null
		and _on_floor(R.POTION) == potions and (tp.t_flags & (R.ISHUH | R.ISHASTE | R.ISSLOW)) == 0)
	# scrolls
	l = _give(R.SCROLL, R.S_SLEEP)
	tp = _target()
	_keys("th" + l)
	_check(n + "a scroll of sleep", not R.on(tp, R.ISRUN) and _saw("the zombie falls asleep"))
	l = _give(R.SCROLL, R.S_ARMOR)
	tp = _target()
	_keys("th" + l)
	_check(n + "a scroll of enchant armor", tp.t_stats.s_arm == 19, tp.t_stats.s_arm)
	l = _give(R.SCROLL, R.S_ENCH)
	tp = _target()
	_keys("th" + l)
	_check(n + "a scroll of enchant weapon: +1 damage", Skills.mon_enchants(tp) == 1)
	l = _give(R.SCROLL, R.S_TELEP)
	tp = _target()
	var was := Vector2i(tp.t_pos.x, tp.t_pos.y)
	_keys("th" + l)
	_check(n + "a scroll of teleportation", Chase._on_mlist(tp) and Vector2i(tp.t_pos.x, tp.t_pos.y) != was
		and _saw("the zombie vanishes"))
	# a venus flytrap holding the hero, teleported away, lets go
	l = _give(R.SCROLL, R.S_TELEP)
	while R.mlist != null:
		_remove(R.mlist)
	var fly := _monster("F", 0, -1, true)
	fly.t_stats.s_arm = 20
	fly.t_stats.s_hpt = 1000
	R.player.t_flags |= R.ISHELD
	_keys("th" + l)
	_check(n + "a venus flytrap teleported away lets go", Chase._on_mlist(fly) and not R.on(R.player, R.ISHELD))
	_remove(fly)
	# a miss lands
	l = _give(R.POTION, R.P_RESTORE)
	tp = _target("Z", false)
	potions = _on_floor(R.POTION)
	_keys("th" + l)
	_check(n + "a miss lands on the floor", _on_floor(R.POTION) == potions + 1
		and _in_pack(R.POTION, R.P_RESTORE) == null)
	_end()


func _test_throw_rings() -> void:
	_start({"throw anything": 1})
	_tough()
	var n := "throw anything: "
	# increase damage: it keeps it; dying, it does not drop it
	var l := _give(R.RING, R.R_ADDDAM, 2)
	var tp := _target()
	var rings := _on_floor(R.RING)
	_keys("th" + l)
	_check(n + "a ring of increase damage stays on the monster", Skills.mon_bonus(tp, R.R_ADDDAM) == 2
		and _in_pack(R.RING, R.R_ADDDAM) == null)
	tp.t_stats.s_hpt = 1
	l = _give(R.ARMOR, R.LEATHER)
	_keys("th" + l)
	_check(n + "the monster dies", not Chase._on_mlist(tp) and _saw("defeated"))
	_check(n + "the ring goes with it", _on_floor(R.RING) == rings)
	# aggravate monster: another monster, asleep 5 to the right, goes to it
	l = _give(R.RING, R.R_AGGR)
	tp = _target()
	var far := _monster("K", 0, 5)
	_keys("th" + l)
	_check(n + "a ring of aggravate monster", R.on(far, R.ISRUN) and far.t_dest == tp.t_pos
		and _saw("you hear a high pitched humming noise"))
	# regeneration: a hit point a turn
	l = _give(R.RING, R.R_REGEN)
	tp = _target()
	_keys("th" + l)
	tp.t_stats.s_hpt = 900
	tp.t_flags |= R.ISHELD
	tp.t_flags &= ~R.ISRUN
	_rest(5)
	_check(n + "a ring of regeneration", tp.t_stats.s_hpt == 905, tp.t_stats.s_hpt)
	# teleportation: now and then somewhere else (held, it would not move)
	l = _give(R.RING, R.R_TELEPORT)
	tp = _target()
	_keys("th" + l)
	tp.t_flags |= R.ISHELD
	tp.t_flags &= ~R.ISRUN
	var was := Vector2i(tp.t_pos.x, tp.t_pos.y)
	var moved := false
	for i in 300:
		_key(".")
		if Vector2i(tp.t_pos.x, tp.t_pos.y) != was:
			moved = true
			break
	_check(n + "a ring of teleportation moves the monster", moved and Skills.mon_wears(tp, R.R_TELEPORT))
	_end()


func _test_throw_wands() -> void:
	_start({"throw anything": 1})
	_tough()
	var n := "throw anything: "
	var l := _give(R.STICK, R.WS_SLOW_M, 1, 3)
	var tp := _target()
	var sticks := _on_floor(R.STICK)
	_keys("th" + l)
	_check(n + "a wand of slow monster", R.on(tp, R.ISSLOW))
	_check(n + "the wand is gone", _in_pack(R.STICK, R.WS_SLOW_M) == null and _on_floor(R.STICK) == sticks)
	# an empty wand: one last effect
	l = _give(R.STICK, R.WS_HASTE_M, 1, 0)
	tp = _target()
	_keys("th" + l)
	_check(n + "an empty wand of haste monster still works once", R.on(tp, R.ISHASTE)
		and _in_pack(R.STICK, R.WS_HASTE_M) == null and _on_floor(R.STICK) == sticks)
	# magic missile: 1x4 + 1 (it never saves)
	l = _give(R.STICK, R.WS_MISSILE, 1, 3)
	tp = _target()
	tp.t_stats.s_lvl = -40
	_keys("th" + l)
	var lost := 1000 - tp.t_stats.s_hpt
	_check(n + "a wand of magic missile: the hit's 1, then 2 to 5", lost >= 3 and lost <= 6, lost)
	# cold: 6x6 (it never saves)
	l = _give(R.STICK, R.WS_COLD, 1, 3)
	tp = _target()
	tp.t_stats.s_lvl = -40
	_keys("th" + l)
	lost = 1000 - tp.t_stats.s_hpt
	_check(n + "a wand of cold: the hit's 1, then 6x6", lost >= 7 and lost <= 37 and _saw("the ice hits"),
		lost)
	# polymorph: a new monster, awake
	l = _give(R.STICK, R.WS_POLYMORPH, 1, 3)
	tp = _target()
	_keys("th" + l)
	_check(n + "a wand of polymorph: a new monster, awake", Chase._on_mlist(tp) and R.on(tp, R.ISRUN))
	# teleport away (a venus flytrap: it does not move on its own)
	l = _give(R.STICK, R.WS_TELAWAY, 1, 3)
	tp = _target("F")
	var was := Vector2i(tp.t_pos.x, tp.t_pos.y)
	_keys("th" + l)
	_check(n + "a wand of teleport away", Chase._on_mlist(tp) and Vector2i(tp.t_pos.x, tp.t_pos.y) != was,
		[was, tp.t_pos.y, tp.t_pos.x])
	_end()


func _test_throw_worn() -> void:
	_start({"throw anything": 1})
	_tough()
	var n := "throw anything: "
	# the worn armour (b) comes off first
	var tp := _target()
	_keys("thb")
	var lost := 1000 - tp.t_stats.s_hpt
	_check(n + "the worn armour comes off and hits", R.cur_armor == null and lost >= 2 and lost <= 5, lost)
	# a ring put on comes off first, and the monster wears it
	var l := _give(R.RING, R.R_PROTECT, 2)
	_keys("P" + l + "l")
	_check("the scene: the ring is on", R.cur_ring[R.LEFT] != null)
	tp = _target()
	_keys("th" + l)
	_check(n + "the worn ring comes off and the monster wears it", R.cur_ring[R.LEFT] == null
		and Skills.mon_bonus(tp, R.R_PROTECT) == 2)
	_end()


# ---- Coin Scrounger -----------------------------------------------------------------

func _test_coin() -> void:
	for lvl in [0, 1, 3]:
		_start({"coin scrounger": lvl} if lvl > 0 else {})
		var gold := List.new_item()
		gold.o_type = R.GOLD
		gold.o_goldval = 50
		gold.o_flags = R.ISMANY
		gold.o_pos.y = R.hero.y
		gold.o_pos.x = R.hero.x + 1
		R.lvl_obj = List._attach(R.lvl_obj, gold)
		R.INDEX(gold.o_pos.y, gold.o_pos.x).p_ch = R.GOLD
		var purse := R.purse
		_key("l")
		var got: int = 50 * (lvl + 1)
		_check("coin scrounger %d: 50 gold picked up is %d" % [lvl, got], R.purse - purse == got
			and _saw("you found %d gold pieces" % got), R.purse - purse)
		_end()


# ---- Safe Pockets ---------------------------------------------------------------------

func _test_pockets() -> void:
	for has in [false, true]:
		_start({"safe pockets": 1} if has else {})
		_tough()
		R.purse = 1000
		var lep := _monster("L", 0, -1, true)
		lep.t_stats.s_lvl = 20
		var losses := []
		for i in 12:
			var hp: int = R.pstats.s_hpt
			_key(".")
			losses.append(hp - R.pstats.s_hpt)
		if has:
			_check("safe pockets: the leprechaun steals nothing", R.purse == 1000 and Chase._on_mlist(lep), R.purse)
			_check("safe pockets: the leprechaun hits for 1x8", losses.min() >= 1 and losses.max() <= 8
				and losses.max() > 1, losses)
		else:
			_check("no safe pockets: the leprechaun steals", R.purse < 1000 and not Chase._on_mlist(lep)
				and _saw("your purse feels lighter"), R.purse)
		_end()
	for has in [false, true]:
		_start({"safe pockets": 1} if has else {})
		_tough()
		_give(R.POTION, R.P_HEALING)
		var nym := _monster("N", 0, -1, true)
		nym.t_stats.s_lvl = 20
		_rest(12)
		if has:
			_check("safe pockets: the nymph steals nothing", _in_pack(R.POTION, R.P_HEALING) != null
				and Chase._on_mlist(nym))
		else:
			_check("no safe pockets: the nymph steals", _in_pack(R.POTION, R.P_HEALING) == null
				and _saw("she stole"))
		_end()


# ---- the Serpentine Cult -------------------------------------------------------------

func _test_cult_asleep() -> void:
	for has in [false, true]:
		_start({"serpentine cult": 1} if has else {})
		_tough()
		var sn := _monster("R", 0, -1)
		var woke := false
		for i in 15:
			_key(".")
			woke = woke or R.on(sn, R.ISRUN)
		if has:
			_check("serpentine cult: a snake beside the hero sleeps on", not woke)
		else:
			_check("no serpentine cult: the snake wakes", woke)
		_end()


func _test_cult_bites() -> void:
	for has in [false, true]:
		_start({"serpentine cult": 1} if has else {})
		_tough()
		var str0: int = R.pstats.s_str
		var sn := _monster("R", 0, -1, true)
		sn.t_stats.s_lvl = 20
		var low := str0
		for i in 40:
			_key(".")
			low = mini(low, R.pstats.s_str)
		if has:
			_check("serpentine cult: bites never weaken the hero", low == str0, low)
			_check("serpentine cult: a snake's bites make the hero stronger once (40 bites: +1)",
				R.pstats.s_str == str0 + 1 and R.on(sn, R.GAVESTR) and _saw("the snake's bite makes you stronger"),
				R.pstats.s_str)
			# another snake: one more
			_remove(sn)
			sn = _monster("R", 0, -1, true)
			sn.t_stats.s_lvl = 20
			for i in 40:
				_key(".")
			_check("serpentine cult: another snake, once more (+2)", R.pstats.s_str == str0 + 2, R.pstats.s_str)
		else:
			_check("no serpentine cult: bites weaken the hero", R.pstats.s_str < str0, R.pstats.s_str)
		_end()


func _test_cult_confirm() -> void:
	# melee: the first attack is stopped (no time passes), the second goes through
	_start({"serpentine cult": 1})
	_tough()
	var sn := _monster("R", 0, -1)
	sn.t_stats.s_hpt = 1000
	sn.t_stats.s_arm = 20
	var food := R.food_left
	_key("h")
	_check("serpentine cult: the first attack is stopped", sn.t_stats.s_hpt == 1000
		and _saw("snakes are sacred to the cult: do it again to attack"))
	_check("serpentine cult: no time passes", R.food_left == food and not R.on(sn, R.ISRUN), [R.food_left, food])
	_key("h")
	_check("serpentine cult: the second goes through", sn.t_stats.s_hpt < 1000, sn.t_stats.s_hpt)
	_seen = ""
	_key("h")
	_check("serpentine cult: that snake needs no more asking", not _saw("sacred"))
	_end()
	# the fight command stops too
	_start({"serpentine cult": 1})
	_tough()
	sn = _monster("R", 0, -1)
	sn.t_stats.s_hpt = 1000
	sn.t_stats.s_arm = 20
	_keys("Fh")
	_check("serpentine cult: the fight command is stopped", sn.t_stats.s_hpt == 1000 and not R.to_death
		and _saw("sacred"))
	_end()
	# a throw at a snake
	_start({"serpentine cult": 1})
	_tough()
	var l := _give(R.WEAPON, R.DART)
	var darts: int = _in_pack(R.WEAPON, R.DART).o_count
	sn = _monster("R", 0, -2)
	sn.t_stats.s_hpt = 1000
	_keys("th" + l)
	_check("serpentine cult: a throw at a snake is stopped", _in_pack(R.WEAPON, R.DART).o_count == darts
		and _saw("sacred"))
	_keys("th" + l)
	_check("serpentine cult: thrown again, it goes", _in_pack(R.WEAPON, R.DART).o_count == darts - 1)
	_end()
	# a zap at a snake
	_start({"serpentine cult": 1})
	_tough()
	var w := _give(R.STICK, R.WS_SLOW_M, 1, 3)
	sn = _monster("R", 0, -2)
	_keys("zh" + w)
	var wand := _in_pack(R.STICK, R.WS_SLOW_M)
	_check("serpentine cult: a zap at a snake is stopped", wand.o_charges == 3 and not R.on(sn, R.ISSLOW)
		and _saw("sacred"))
	_keys("zh" + w)
	_check("serpentine cult: zapped again, it goes", wand.o_charges == 2 and R.on(sn, R.ISSLOW))
	_end()
	# the warning holds only until time passes
	_start({"serpentine cult": 1})
	_tough()
	sn = _monster("R", 0, -1)
	sn.t_stats.s_hpt = 1000
	sn.t_stats.s_arm = 20
	_keys("h.")
	_seen = ""
	_key("h")
	_check("serpentine cult: after a turn, asked again", sn.t_stats.s_hpt == 1000 and _saw("sacred"))
	_end()
	# without the cult: no asking
	_start({})
	_tough()
	sn = _monster("R", 0, -1)
	sn.t_stats.s_hpt = 1000
	sn.t_stats.s_arm = 20
	_key("h")
	_check("no serpentine cult: the attack goes at once", sn.t_stats.s_hpt < 1000 and not _saw("sacred"))
	_end()


func _test_cult_banished() -> void:
	_start({"serpentine cult": 1})
	_tough()
	var sn := _monster("R", 0, -1)
	sn.t_stats.s_hpt = 1
	sn.t_stats.s_arm = 20
	_keys("hh")
	_check("serpentine cult: killing a snake banishes the hero", R.cult_banished and not Chase._on_mlist(sn)
		and _saw("you are banished from the Serpentine Cult!"))
	# now rattlesnakes weaken the hero again, and hit 50% harder: 1x6 makes 1 3 4 6 7 9
	var str0: int = R.pstats.s_str
	sn = _monster("R", 0, -1, true)
	sn.t_stats.s_lvl = 20
	var losses := []
	for i in 40:
		var hp: int = R.pstats.s_hpt
		_key(".")
		losses.append(hp - R.pstats.s_hpt)
	var ok := true
	for d in losses:
		ok = ok and d in [1, 3, 4, 6, 7, 9]
	_check("banished: snakes hit 50% harder", ok and losses.max() > 6, losses)
	_check("banished: bites weaken the hero again", R.pstats.s_str < str0, R.pstats.s_str)
	# the next snake sleeps no more
	_seen = ""
	var sn2 := _monster("S", -1, -1)
	sn2.t_stats.s_hpt = 1000
	sn2.t_stats.s_arm = 20
	_key("y")
	_check("banished: no more asking", sn2.t_stats.s_hpt < 1000 and not _saw("sacred"))
	_end()


# ---- Advanced Recovery -------------------------------------------------------------

func _test_recovery() -> void:
	var waits := []
	for has in [false, true]:
		_start({"advanced recovery": 1} if has else {})
		R.pstats.s_hpt = 1
		R.quiet = 0
		var n := 0
		while R.pstats.s_hpt == 1 and n < 40:
			_key(".")
			n += 1
		waits.append(n)
		_end()
	# level 1 heals when quiet passes 18 (20 - 2 * 1); as level 2, past 16
	_check("advanced recovery: heals as at level 2", waits == [19, 17], waits)


# ---- the save -------------------------------------------------------------------------

func _test_save() -> void:
	_start({"coin scrounger": 2, "serpentine cult": 1, "low-light vision": 1})
	R.cult_banished = true
	var sn := _monster("R", 0, -2)
	sn.t_flags |= R.GAVESTR
	_keys("Syy")
	_check("the scene: the game is saved", _done, _seen.right(300))
	_end()
	_start({}, true)
	_check("the save keeps the skills", R.skills == {"coin scrounger": 2, "serpentine cult": 1,
		"low-light vision": 1} and R.skill(R.SK_COIN) == 2, R.skills)
	_check("the save keeps the banishment", R.cult_banished)
	var gave := false
	var mp: Thing = R.mlist
	while mp != null:
		gave = gave or (mp.t_type == ord("R") and R.on(mp, R.GAVESTR))
		mp = mp.l_next
	_check("the save keeps which snakes have made the hero stronger", gave)
	_end()
