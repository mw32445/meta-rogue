## Unit tests of the Fighters' Guild (godot/guild, docs/GUILD.md): the coffers,
## the prices, the shop's rules, the random identifications, the 20-entry Hall of
## Fame, the catalog against the game's tables, loadouts applied to new games, a
## shop with an edited price list, and the skills (the shop's rules, the loadout, the
## Skills tab). The shops use the built-in price list (GuildPrices.defaults()), never
## the player's guild_prices.txt; the price list itself is tested by
## godot/tests/prices_test.gd, the skills in the game by godot/tests/skills_test.gd.
##   godot --headless --path godot --script res://tests/guild_test.gd
## Prints PASS or FAIL for each check; exit status 1 if any check fails. Works in
## (and removes) the folder "guild_test" of the project's user data folder.
extends SceneTree

const C := preload("res://guild/catalog.gd")

var _fails := 0
var _passes := 0
var _dir := ""


func _initialize() -> void:
	_dir = OS.get_user_data_dir().path_join("guild_test")
	_clean()
	DirAccess.make_dir_recursive_absolute(_dir)
	_test_coffers()
	_test_prices()
	_test_limits()
	_test_refunds()
	_test_draws()
	_test_migration()
	_test_catalog()
	await _test_loadout()
	_test_shop_loadout()
	_test_letters()
	_test_polish_win()
	_test_big_pack()
	_test_screen()
	_test_edited_prices()
	_test_skills()
	_test_skills_loadout()
	_test_skills_screen()
	_clean()
	print("guild_test: %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail: Variant = "") -> void:
	if ok:
		_passes += 1
		print("PASS ", name)
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(_dir):
		return
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(f))
	DirAccess.remove_absolute(_dir)


# ---- Hall of Fame files -------------------------------------------------------

## Write a score file the way the game does (Save.wr_score with numscores n): the
## given scores, then empty (score 0) entries.
func _write_hall(path: String, scores: Array, n: int) -> void:
	RogueBase.reset()
	RogueBase.numscores = n
	var f := FileAccess.open(path, FileAccess.WRITE_READ)
	RogueBase.scoreboard = f
	var top: Array = []
	for i in n:
		var sc := Rip.Score.new()
		if i < scores.size():
			sc.sc_score = scores[i]
			sc.sc_name = "hero %d" % i
			sc.sc_flags = i % 3	# killed, quit, a total winner
			sc.sc_level = 3 + i
			sc.sc_monster = ord("K")
			sc.sc_uid = 1000
		else:
			sc.sc_name = "garbage %d" % i
			sc.sc_flags = 77
			sc.sc_level = 99
		top.append(sc)
	Save.wr_score(top)
	f.close()
	RogueBase.scoreboard = null
	RogueBase.reset()


## The user's formula: best/2 + (sum/20) * lerp(0.5, 1.5, n/20), in floating point.
static func _float_coffers(best: int, sum: int, n: int) -> float:
	return best / 2.0 + (sum / 20.0) * lerpf(0.5, 1.5, n / 20.0)


func _test_coffers() -> void:
	var h := HallOfFame.read_file(_dir.path_join("none.scr"))
	_check("coffers: no Hall of Fame file gives 0", h.coffers() == 0 and h.heroes == 0, h.coffers())
	var cases := [
		["one entry", [1000], 527],
		["ten entries", [1000, 900, 800, 700, 600, 500, 400, 300, 200, 100], 775],
		["twenty entries", [500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500, 500,
			500, 500, 500, 500, 500, 500], 1000],
		["worked example (17 heroes, best 2400, sum 9400)", [2400, 1500, 1000, 800, 700, 600, 500,
			400, 350, 300, 250, 200, 150, 100, 80, 50, 20], 1834],
	]
	for c in cases:
		var scores: Array = c[1]
		var path := _dir.path_join("hall.scr")
		_write_hall(path, scores, 20)
		h = HallOfFame.read_file(path)
		var sum := 0
		for s in scores:
			sum += s
		var exact := _float_coffers(scores[0], sum, scores.size())
		_check("coffers: %s = %d" % [c[0], c[2]], h.coffers() == c[2] and h.heroes == scores.size()
			and h.total == sum and h.best == scores[0], "got %d (%d heroes, sum %d, best %d)" % [
			h.coffers(), h.heroes, h.total, h.best])
		_check("coffers: %s matches best/2 + sum/20 * lerp(0.5, 1.5, n/20) = %.2f" % [c[0], exact],
			h.coffers() == int(floor(exact)), h.coffers())
	# odd scores: the old integer formula, best / 2 + sum * (10 + n) / 400, floored each
	# term; the price list's floors the sum, so it may be 1 more
	var odd := GuildPrices.defaults().coffers(2401, 9401, 17)
	_check("coffers: odd scores, 1 more than the old integer formula (1835, was %d)" % (2401 / 2
		+ 9401 * 27 / 400), odd == 1835 and odd == int(floor(_float_coffers(2401, 9401, 17))), odd)
	# the shop starts with the coffers
	_write_hall(_dir.path_join("hall.scr"), [2400, 1500, 1000, 800, 700, 600, 500, 400, 350, 300,
		250, 200, 150, 100, 80, 50, 20], 20)
	var shop := GuildShop.new(HallOfFame.read_file(_dir.path_join("hall.scr")))
	_check("coffers: a shop opens with them, nothing spent", shop.coffers == 1834
		and shop.spent() == 0 and shop.left() == 1834 and shop.pack_load() == 5
		and shop.pack_size() == 23)


# ---- prices -------------------------------------------------------------------

func _test_prices() -> void:
	var s := GuildShop.new()
	s.coffers = 1 << 40
	var seq := []
	for i in 4:
		var before := s.spent()
		s.buy("str")
		seq.append(s.spent() - before)
	_check("prices: strength 100 * 2^k", seq == [100, 200, 400, 800], seq)
	seq = []
	for i in 3:
		var before := s.spent()
		s.buy("hp")
		seq.append(s.spent() - before)
	_check("prices: hit points 60 * 2^k, +2 each", seq == [60, 120, 240] and s.hp_now() == 18, seq)
	var p := GuildPrices.defaults()
	var food := []
	var rations := 0
	for i in 13:
		food.append(p.price("stores", "food", i))
		rations += food[i]
	_check("prices: food 30 * 1.3^k", food.slice(0, 6) == [30, 39, 50, 65, 85, 111], food)
	var rings: int = p.price("rings", C.RINGS[10][0], 0) + p.price("rings", C.RINGS[10][0], 1)
	_check("prices: 13 rations (%d) cost less than two rings of slow digestion (%d)" % [rations, rings],
		rations < rings and rings == 3125 and rations > 2500)
	var pk := []
	for i in 5:
		pk.append(p.price("stores", "pack slot", i))
	_check("prices: pack slots 50 * 1.5^k", pk == [50, 75, 112, 168, 253], pk)
	seq = []
	for i in 3:
		var before := s.spent()
		s.buy("rg:0")
		seq.append(s.spent() - before)
	_check("prices: a second ring of a kind costs 4 times as much", seq == [450, 1800, 7200], seq)
	seq = []
	for i in 2:
		var before := s.spent()
		s.buy("wd:11")
		seq.append(s.spent() - before)
	_check("prices: a second wand of a kind twice as much (teleport away 300)", seq == [300, 600], seq)
	var polish := []
	s.buy("rg:5")
	var adorn := s.rings.size() - 1
	_check("prices: adornment is free", s.rings[adorn].which == 5 and _price_of(s, 3, "rg:5") == 0)
	for i in 8:
		var before := s.spent()
		var why := s.buy("pr:%d" % adorn)
		polish.append(s.spent() - before if why == GuildShop.DONE else why)
	_check("prices: polishing 5 * 2^k, at most 7 times", polish == [5, 10, 20, 40, 80, 160, 320,
		GuildShop.AT_MAX], polish)
	var before_id := s.spent()
	s.buy("ip")
	s.buy("ip")
	s.buy("is")
	_check("prices: an identification is always 40", s.spent() - before_id == 120)
	var k := s.last_named
	before_id = s.spent()
	s.buy("bs:%d" % k)
	s.buy("bs:%d" % k)
	_check("prices: a known scroll costs base * 2^k", s.spent() - before_id
		== 3 * p.price("scrolls", C.SCROLLS[k][0]))
	var w := GuildShop.new()
	w.coffers = 10000
	w.buy("sw:1")
	var sword := w.spent()
	w.buy("sw:5")
	var two := w.spent()
	w.buy("sw:4")
	_check("prices: your weapon costs its difference over the mace (190, 540), a dagger is free",
		sword == 190 and two == 540 and w.spent() == 0 and w.weapon == 4)
	w.buy("sa:7")
	var plate := w.spent()
	w.buy("sa:0")
	_check("prices: your armour likewise (plate 1040, leather free)", plate == 1040 and w.spent() == 0)
	seq = []
	for i in 3:
		var before := w.spent()
		w.buy("ew:you")
		seq.append(w.spent() - before)
	_check("prices: smithing 75 * 2^k", seq == [75, 150, 300], seq)
	var o: Dictionary = _offer(w, 1, "ew:you")
	_check("prices: smithing raises the lower bonus, damage first (+1,+1 -> +2,+3)",
		o.info == "+1,+1 -> +2,+3", o.info)
	_check("prices: missiles are flat", _price_of(w, 7, "ms:0") == 10 and _price_of(w, 7, "ms:1") == 8
		and _price_of(w, 7, "ms:2") == 25 and _price_of(w, 7, "ms:3") == 30)


func _offer(s: GuildShop, section: int, id: String) -> Dictionary:
	for l in s.offers(section):
		if l.has("id") and l.id == id:
			return l
	return {}


func _price_of(s: GuildShop, section: int, id: String) -> int:
	var o := _offer(s, section, id)
	return o.price if o.has("price") else -1


# ---- limits -------------------------------------------------------------------

func _test_limits() -> void:
	var s := GuildShop.new()
	s.coffers = 150
	_check("limits: within the coffers", s.buy("str") == GuildShop.DONE and s.left() == 50)
	_check("limits: not beyond them", s.buy("hp") == GuildShop.NO_GOLD and s.left() == 50)
	_check("limits: a free swap is always possible", s.buy("sw:4") == GuildShop.DONE)
	s = GuildShop.new()
	s.coffers = 100000
	for i in 18:
		s.buy("xa:0")	# leather armour, 20 each
	_check("limits: the pack holds 23 (5 issued + 18)", s.pack_load() == 23
		and s.buy("xa:0") == GuildShop.NO_ROOM)
	_check("limits: extra arrows take no slot", s.buy("ms:0") == GuildShop.DONE)
	_check("limits: other missiles do", s.buy("ms:1") == GuildShop.NO_ROOM)
	_check("limits: a bought slot makes room", s.buy("pk") == GuildShop.DONE
		and s.pack_size() == 24 and s.buy("ms:1") == GuildShop.DONE and s.pack_load() == 24)
	_check("limits: a second stack of darts joins the first", s.buy("ms:1") == GuildShop.DONE
		and s.pack_load() == 24)
	_check("limits: a slot in use cannot be returned", s.refund("pk") == GuildShop.IN_USE)
	s.refund("xa:0")
	_check("limits: a free slot can", s.refund("pk") == GuildShop.DONE and s.pack_size() == 23)
	var big := GuildShop.new()
	big.coffers = 1 << 50
	var n := 0
	while big.buy("pk") == GuildShop.DONE:
		n += 1
	_check("limits: at most 52 slots", n == 29 and big.pack_size() == 52
		and big.buy("pk") == GuildShop.AT_MAX)
	n = 0
	while big.buy("str") == GuildShop.DONE:
		n += 1
	_check("limits: strength up to 31", n == 15 and big.strength_now() == 31
		and big.buy("str") == GuildShop.AT_MAX)


# ---- returns ------------------------------------------------------------------

func _test_refunds() -> void:
	var s := GuildShop.new()
	s.coffers = 1 << 40
	s.buy("ip")
	var named := s.last_named
	_check("returns: an identification gives no item", s.spent() == 40 and s.pack_load() == 5
		and s.pot_known[named] and s.pot_count[named] == 0)
	_check("returns: an identification is final", s.refund("ip") == GuildShop.FINAL and s.spent() == 40
		and s.pot_known[named])
	_check("returns: the named kind is for sale", s.buy("bp:%d" % named) == GuildShop.DONE
		and s.pack_load() == 6)
	_check("returns: and returned in full", s.refund("bp:%d" % named) == GuildShop.DONE
		and s.spent() == 40 and s.pack_load() == 5)
	var ids := ["str", "str", "hp", "sw:5", "xw:1", "ew:you", "ew:bow", "ew:0", "sa:7", "xa:4",
		"ea:you", "ea:0", "rg:0", "rg:0", "er:0", "rg:5", "pr:2", "wd:3", "ec:0", "bp:%d" % named,
		"fd", "fd", "ms:0", "ms:1", "ms:3", "pk", "pk"]
	var ok := true
	for id in ids:
		ok = ok and s.buy(id) == GuildShop.DONE
	_check("returns: every kind of purchase", ok and s.spent() > 40)
	var undo := ["pk", "pk", "ms:3", "ms:1", "ms:0", "fd", "fd", "bp:%d" % named, "ec:0", "wd:3",
		"pr:2", "rg:5", "er:0", "rg:0", "rg:0", "ea:0", "ea:you", "xa:4", "sa:7", "ew:0", "ew:bow",
		"ew:you", "xw:1", "sw:5", "hp", "str", "str"]
	ok = true
	for id in undo:
		var why := s.refund(id)
		if why != GuildShop.DONE:
			ok = false
			print("  refund ", id, ": ", why)
	_check("returns: every one of them in full", ok and s.spent() == 40 and s.pack_load() == 5
		and s.pack_size() == 23, s.spent())
	_check("returns: nothing more to return", s.refund("str") == GuildShop.NONE
		and s.refund("xw:1") == GuildShop.NONE and s.refund("sw:0") == GuildShop.ISSUED)
	var lo := s.loadout()
	_check("returns: the loadout holds only the identification", lo.know_potions == [named]
		and lo.potions.is_empty() and lo.rings.is_empty() and lo.str == 0 and lo.maxpack == 23
		and not lo.has("weapon"))
	# returning a ring returns its enchantments with it
	s.buy("rg:1")
	s.buy("er:0")
	s.buy("er:0")
	var with_enh := s.spent()
	s.refund("rg:1")
	_check("returns: a ring goes back with its enchantments", s.spent() == 40 and with_enh == 40 + 450
		+ 150 + 300)


# ---- the random identifications -------------------------------------------------

func _names(path: String, potions_first_scroll := false) -> Array:
	var s := GuildShop.new(HallOfFame.read_file(path))
	s.coffers = 100000
	if potions_first_scroll:
		s.buy("is")
	var out := []
	for i in 6:
		s.buy("ip")
		out.append(s.last_named)
	return out


func _test_draws() -> void:
	var a := _dir.path_join("a.scr")
	var b := _dir.path_join("b.scr")
	_write_hall(a, [900, 400, 120], 20)
	var first := _names(a)
	_check("draws: the same Hall of Fame names the same kinds", _names(a) == first, first)
	_check("draws: scrolls don't change the potions' order", _names(a, true) == first)
	_write_hall(b, [900, 400, 120, 15], 20)
	var other := _names(b)
	_check("draws: a changed Hall of Fame names others", other != first, [first, other])
	var e1 := _names(_dir.path_join("missing.scr"))
	_check("draws: no Hall of Fame: a fixed order", _names(_dir.path_join("missing2.scr")) == e1, e1)
	var s := GuildShop.new()
	s.coffers = 100000
	var seen := {}
	for i in 14:
		s.buy("ip")
		seen[s.last_named] = true
	_check("draws: each identification names a new kind, until all are known",
		seen.size() == 14 and s.buy("ip") == GuildShop.ALL_KNOWN and s.spent() == 14 * 40)
	# weighted by dungeon frequency: over many Halls of Fame the first name follows
	# the frequencies (raise level, 2%, comes up far less often than healing, 13%)
	var count := {}
	for i in 400:
		var h := HallOfFame.new()
		h.digest = i * 7919 + 13
		var t := GuildShop.new(h)
		t.coffers = 100
		t.buy("ip")
		count[t.last_named] = count.get(t.last_named, 0) + 1
	_check("draws: weighted by frequency (healing %d, raise level %d of 400)" % [count.get(5, 0),
		count.get(8, 0)], count.get(5, 0) > 2 * count.get(8, 0) and count.get(5, 0) > 25)


# ---- the 20-entry Hall of Fame ------------------------------------------------

func _test_migration() -> void:
	var path := _dir.path_join("old.scr")
	_write_hall(path, [1000, 900, 800, 700, 600, 500, 400, 300, 200, 100], 10)
	_check("migration: a 10-entry file", FileAccess.get_file_as_bytes(path).size() == 10 * 1124)
	var h := HallOfFame.read_file(path)
	_check("migration: the Guild reads its 10 entries", h.entries.size() == 10 and h.heroes == 10
		and h.total == 5500)
	for guild in [false, true]:
		RogueBase.reset()
		RogueBase.guild = guild
		RogueBase.numscores = 20
		RogueBase.env_scorefile = path
		RogueBase.env_cwd = ""
		MachDep.open_score()
		var top: Array = []
		for i in 20:
			var sc := Rip.Score.new()
			sc.sc_score = 0	# as score() starts every entry
			sc.sc_name = "unused"
			top.append(sc)
		Save.rd_score(top)
		var zeros := 0
		for i in range(10, 20):
			if top[i].sc_score == 0:
				zeros += 1
		if guild:
			_check("migration: rd_score reads 10 entries, the other 10 stay empty",
				top[0].sc_score == 1000 and top[9].sc_score == 100 and top[9].sc_name == "hero 9"
				and zeros == 10, zeros)
			Save.wr_score(top)
			RogueBase.scoreboard.close()
			h = HallOfFame.read_file(path)
			_check("migration: written back as 20 entries, still 10 heroes",
				FileAccess.get_file_as_bytes(path).size() == 20 * 1124 and h.entries.size() == 20
				and h.heroes == 10 and h.total == 5500)
		else:
			_check("migration: (classic rd_score would make phantoms of entry 10)",
				zeros == 0 and top[15].sc_score == 100)
			RogueBase.scoreboard.close()
		RogueBase.scoreboard = null
	RogueBase.guild = false
	RogueBase.reset()


# ---- the catalog against the game's tables -------------------------------------

func _test_catalog() -> void:
	RogueBase.reset()
	var R := RogueBase
	var tables := [["potions", C.POTIONS, R.pot_info], ["scrolls", C.SCROLLS, R.scr_info],
		["rings", C.RINGS, R.ring_info], ["sticks", C.STICKS, R.ws_info],
		["weapons", C.WEAPONS, R.weap_info], ["armour", C.ARMORS, R.arm_info]]
	for t in tables:
		var mine: Array = t[1]
		var game: Array = t[2]
		var bad := []
		for i in mine.size():
			if mine[i][0] != game[i].oi_name or mine[i][1] != game[i].oi_prob:
				bad.append(i)
		var size_ok: bool = mine.size() == game.size() or (t[0] == "weapons" and mine.size() == R.MAXWEAPONS)
		_check("catalog: %s names and frequencies match the game" % t[0], bad.is_empty() and size_ok, bad)
	_check("catalog: armour classes", C.A_CLASS == R.a_class)
	var dmg_ok := true
	for i in C.WEAPONS.size():
		dmg_ok = dmg_ok and C.WEAPONS[i][2] == Weapons.init_dam[i].iw_dam
	_check("catalog: weapon damage", dmg_ok)
	_check("catalog: the issued strength, hit points and pack", C.STR_START == R.max_stats.s_str
		and C.HP_START == R.max_stats.s_maxhp and C.PACK_START == R.MAXPACK
		and C.WEAPON_ISSUED == R.MACE and C.ARMOR_ISSUED == R.RING_MAIL and C.BOW == R.BOW
		and C.ARROW == R.ARROW and C.RING_ADORNMENT == R.R_NOP and C.STICK_LIGHT == R.WS_LIGHT)
	_check("catalog: bonus and cursed rings", C.RING_BONUS == [R.R_PROTECT, R.R_ADDSTR, R.R_ADDHIT,
		R.R_ADDDAM] and C.RING_CURSED == [R.R_AGGR, R.R_TELEPORT])
	var m_ok := true
	for m in C.MISSILES:
		m_ok = m_ok and m[0] in [R.ARROW, R.DART, R.SHIRAKEN, R.DAGGER]
	_check("catalog: missiles", m_ok)


# ---- loadouts in a game -------------------------------------------------------

var _done := false


## Run a new game in guild mode with a loadout until its first command (the
## issued kit and the purchases are in the pack then). Returns the Curses.
func _start_game(lo: Variant, seed_ := 42) -> Curses:
	RogueBase.reset()
	var cs := Curses.new()
	cs.replay = true
	cs.script_keys = PackedInt32Array([27])
	RogueBase.cs = cs
	RogueBase.env_time = 1000000000
	RogueBase.env_pid = seed_ - 1000000000
	RogueBase.env_name = "rodney"
	RogueBase.env_home = "./"
	RogueBase.env_uid = 1000
	RogueBase.env_cwd = _dir
	RogueBase.env_sandbox = true
	RogueBase.env_rogueopts = null
	RogueBase.MASTER = false
	RogueBase.guild = true
	RogueBase.loadout = lo
	RogueBase.argv = PackedStringArray(["rogue"])
	_done = false
	cs.script_finished.connect(func() -> void: _done = true)
	cs.program_exited.connect(func(_st: int) -> void: _done = true)
	var game := func() -> void:
		await Main.main()
		_done = true
	game.call()
	var guard := 4
	while not _done and guard > 0:
		cs.feed()
		guard -= 1
	return cs


func _stop_game(cs: Curses) -> void:
	cs.abandon()
	RogueBase.cs = null
	RogueBase.guild = false
	RogueBase.loadout = null


## The pack as [letter, type, which, count, hplus, dplus, arm, flags] rows.
func _pack() -> Array:
	var out := []
	var op := RogueBase.pack
	while op != null:
		out.append([char(op.o_packch), op.o_type, op.o_which, op.o_count, op.o_hplus, op.o_dplus,
			op.o_arm, op.o_flags])
		op = op.l_next
	return out


func _find(type_: int, which: int) -> Thing:
	var op := RogueBase.pack
	while op != null:
		if op.o_type == type_ and op.o_which == which:
			return op
		op = op.l_next
	return null


func _test_loadout() -> void:
	var R := RogueBase
	var cs := _start_game(null)
	var plain := _pack()
	var arrows: int = _find(R.WEAPON, R.ARROW).o_count
	_stop_game(cs)
	_check("loadout: none gives the issued kit", plain.size() == 5 and R.inpack == 5)
	var lo := {
		"maxpack": 30.0, "str": 2.0, "hp": 4.0,
		"weapon": {"which": 1.0, "enh": 1.0},
		"armor": {"which": 7.0, "enh": 1.0},
		"bow": {"enh": 2.0},
		"arrows": 20.0,
		"weapons": [{"which": 8.0, "enh": 0.0}],
		"armors": [{"which": 0.0, "enh": 0.0}],
		"missiles": [{"which": 6.0, "count": 10.0}, {"which": 4.0, "count": 2.0}],
		"rings": [{"which": 0.0, "enh": 1.0}, {"which": 5.0, "enh": 3.0}, {"which": 11.0, "enh": 0.0}],
		"sticks": [{"which": 3.0, "enh": 1.0}, {"which": 0.0, "enh": 0.0}],
		"potions": [{"which": 5.0, "count": 2.0}],
		"scrolls": [{"which": 13.0, "count": 1.0}],
		"food": 2.0,
		"know_potions": [5.0, 9.0],
		"know_scrolls": [13.0, 1.0],
	}
	cs = _start_game(lo)
	var p := R.pstats
	_check("loadout: strength, hit points, pack size", p.s_str == 18 and R.max_stats.s_str == 18
		and p.s_hpt == 16 and p.s_maxhp == 16 and R.maxpack == 30, [p.s_str, p.s_hpt, R.maxpack])
	var w := R.cur_weapon
	_check("loadout: your weapon, a long sword +1,+2", w.o_which == R.SWORD and w.o_hplus == 1
		and w.o_dplus == 2 and (w.o_flags & R.ISKNOW) != 0 and w.o_damage == "3x4"
		and w.o_packch == ord("c"))
	var a := R.cur_armor
	_check("loadout: your armour, plate mail +2", a.o_which == R.PLATE_MAIL and a.o_arm == 1
		and a.o_packch == ord("b"))
	var bow := _find(R.WEAPON, R.BOW)
	_check("loadout: the bow +1,+2", bow.o_hplus == 1 and bow.o_dplus == 2)
	var arr := _find(R.WEAPON, R.ARROW)
	_check("loadout: 20 more arrows on the issued stack", arr.o_count >= 45 and arr.o_count <= 59)
	var ring := _find(R.RING, R.R_NOP)
	_check("loadout: adornment polished 3 times", ring != null and ring.o_arm == 14
		and (ring.o_flags & R.ISKNOW) != 0)
	var prot := _find(R.RING, R.R_PROTECT)
	var tele := _find(R.RING, R.R_TELEPORT)
	_check("loadout: protection +2, teleportation cursed", prot.o_arm == 2
		and (tele.o_flags & R.ISCURSED) != 0)
	var fire := _find(R.STICK, R.WS_FIRE)
	var light := _find(R.STICK, R.WS_LIGHT)
	_check("loadout: fire 7 charges, light 15", fire.o_charges == 7 and light.o_charges == 15
		and R.ws_info[R.WS_FIRE].oi_know)
	var heal := _find(R.POTION, R.P_HEALING)
	var food := _find(R.FOOD, 0)
	_check("loadout: 2 potions of healing, 3 rations", heal.o_count == 2 and food.o_count == 3)
	var darts := _find(R.WEAPON, R.DART)
	var daggers := _find(R.WEAPON, R.DAGGER)
	_check("loadout: a stack of 10 darts, 2 daggers", darts.o_count == 10 and daggers.o_count == 2
		and darts.o_group != 0 and daggers.o_group != darts.o_group)
	_check("loadout: known kinds", R.pot_info[R.P_HEALING].oi_know and R.pot_info[R.P_XHEAL].oi_know
		and not R.pot_info[R.P_RAISE].oi_know and R.scr_info[R.S_ENCH].oi_know
		and R.scr_info[R.S_MAP].oi_know and R.ring_info[R.R_TELEPORT].oi_know)
	_check("loadout: pack count", R.inpack == 19, R.inpack)
	var nm: String = await Things.inv_name(ring, false)
	_check("loadout: a polished ring shows its worth (10 + its stone's, x8)",
		nm.ends_with("[worth %d]" % (R.ring_info[R.R_NOP].oi_worth << 3)), nm)
	_stop_game(cs)
	# a dagger as your weapon is one dagger
	cs = _start_game({"weapon": {"which": 4, "enh": 0}})
	_check("loadout: your weapon, a single +1,+1 dagger", R.cur_weapon.o_which == R.DAGGER
		and R.cur_weapon.o_count == 1 and R.cur_weapon.o_hplus == 1 and R.inpack == 5)
	_stop_game(cs)
	# what does not fit is left out (and add_pack never stops for its message)
	var many := []
	for i in 19:	# one too many (an error is reported)
		many.append({"which": 0, "enh": 0})
	cs = _start_game({"armors": many})
	_check("loadout: a loadout that does not fit stops at the pack's size", R.inpack == 23
		and R.maxpack == 23)
	_stop_game(cs)


## A loadout from the shop: the game's pack count equals the shop's.
func _test_shop_loadout() -> void:
	var R := RogueBase
	var s := GuildShop.new()
	s.coffers = 1 << 40
	for id in ["pk", "pk", "pk", "str", "hp", "sw:5", "ew:you", "ew:bow", "xw:8", "sa:4", "ea:you",
			"xa:0", "rg:0", "er:0", "rg:5", "pr:1", "pr:1", "rg:6", "wd:11", "ec:0", "wd:0", "ip",
			"ip", "is", "fd", "fd", "ms:0", "ms:1", "ms:1", "ms:2", "ms:3"]:
		s.buy(id)
	s.buy("bp:%d" % GuildShop._known(s.pot_known)[0])
	s.buy("bp:%d" % GuildShop._known(s.pot_known)[0])
	s.buy("bs:%d" % GuildShop._known(s.scr_known)[0])
	var lo: Variant = JSON.parse_string(JSON.stringify(s.loadout()))	# as a file would give it
	var cs := _start_game(lo)
	_check("shop loadout: the game's pack holds what the shop counted (%d of %d)" % [s.pack_load(),
		s.pack_size()], R.inpack == s.pack_load() and R.maxpack == s.pack_size(), [R.inpack,
		R.maxpack])
	_check("shop loadout: strength and hit points", R.pstats.s_str == s.strength_now()
		and R.pstats.s_maxhp == s.hp_now())
	_check("shop loadout: two-handed sword +1,+2, chain mail +2", R.cur_weapon.o_which == R.TWOSWORD
		and R.cur_weapon.o_dplus == 2 and R.cur_armor.o_which == R.CHAIN_MAIL
		and R.cur_armor.o_arm == 3)
	_check("shop loadout: 20 darts in one stack", _find(R.WEAPON, R.DART).o_count == 20)
	_stop_game(cs)


## Past 26 items the pack letters go on with A, B, ...
func _test_letters() -> void:
	var R := RogueBase
	var lo := {"maxpack": 40, "armors": [], "potions": []}
	for i in 8:
		lo.armors.append({"which": i, "enh": 0})
	for i in 14:
		lo.potions.append({"which": i, "count": 1})
	for i in 4:
		lo.armors.append({"which": i, "enh": 0})
	var cs := _start_game(lo)
	var letters := ""
	var op := R.pack
	while op != null:
		letters += char(op.o_packch)
		op = op.l_next
	var sorted_ok := letters.length() == 31
	var used := 0
	for b in R.pack_used:
		used += int(b)
	_check("letters: 31 items use a-z and A-E", sorted_ok and letters.contains("A")
		and letters.contains("E") and not letters.contains("F") and used == 31
		and R.pack_used.size() == 52, letters)
	# leave_pack frees an upper-case letter, pack_char gives it out again
	var item: Thing = null
	op = R.pack
	while op != null:
		if op.o_packch == ord("C"):
			item = op
		op = op.l_next
	Pack.leave_pack(item, false, true)
	_check("letters: leave_pack frees C", not R.pack_used[28] and R.pack_used[27])
	_check("letters: pack_char gives C again", Pack.pack_char() == ord("C"))
	_stop_game(cs)
	# classic mode keeps C's arithmetic
	R.guild = false
	_check("letters: classic mode is untouched", Pack._pack_index(ord("C")) == ord("C") - ord("a")
		and Pack._pack_letter(26) == ord("{"))


# ---- whole games from key scripts --------------------------------------------

var _screens: Array[String] = []


## Play a key script in guild mode (as godot/tests/replay.gd does) and keep the
## text of every screen at a key read; returns the stdout text. args: Rogue's
## arguments (wizard mode: MASTER and [""]).
func _play(lo: Variant, keys: PackedInt32Array, seed_: int, args: Array, cwd: String) -> String:
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
	RogueBase.env_cwd = cwd
	RogueBase.env_sandbox = true
	RogueBase.env_rogueopts = null
	RogueBase.MASTER = not args.is_empty()
	RogueBase.guild = true
	RogueBase.loadout = lo
	RogueBase.argv = PackedStringArray(["rogue"] + args)
	_screens = []
	_done = false
	cs.step_hook = func(_key: int) -> void:
		if not cs.curses_gone:
			var t := ""
			for y in RogueBase.NUMLINES:
				for x in RogueBase.NUMCOLS:
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
	var guard := keys.size() + 2
	while not _done and guard > 0:
		cs.feed()
		guard -= 1
	var out := cs.stdout_bytes.get_string_from_ascii()
	_stop_game(cs)
	RogueBase.MASTER = false
	return out


func _seen(text: String) -> bool:
	for s in _screens:
		if s.contains(text):
			return true
	return false


static func _keys_of(path: String) -> PackedInt32Array:
	var keys := PackedInt32Array()
	for line in FileAccess.get_file_as_string(path).split("\n"):
		for tok in line.get_slice("#", 0).split(" ", false):
			keys.append(int(tok))
	return keys


## A ring of adornment polished 3 times sells for 8 times its worth when the hero
## wins: in this game it is set in granite (5), so 15 x 8 = 120 (the corpus'
## wizard-mode win, which uses no pack letters, with the rings added).
func _test_polish_win() -> void:
	var keys := _keys_of(ProjectSettings.globalize_path("res://").path_join(
		"../harness/corpus/scenarios/win-100.keys"))
	var lo := {"rings": [{"which": 5, "enh": 3}, {"which": 5, "enh": 0}]}
	var out := _play(lo, keys, 100, [""], _dir)
	_check("polish: a total winner sells the polished ring for 8 x (10 + its stone)",
		_seen("   Worth  Item") and _seen(")   120  A ring of adornment(granite)")
		and _seen(") [worth 120]"), out.right(200))
	_check("polish: an unpolished one as before (10 + its stone)",
		_seen(")    15  A ring of adornment(granite)\n") or _seen(")    15  A ring of adornment(granite) "))
	_check("polish: the Hall of Fame has twenty places", out.contains("Top Twenty Scores:"))


## 30 slots in a wizard game: letters past z, both inventory pages, drop and pick
## up, save and restore.
func _test_big_pack() -> void:
	var o := func(s: String) -> int: return s.unicode_at(0)
	var k := PackedInt32Array()
	for w in "0123456789abcd":	# 14 potions
		k.append_array([o.call("C"), o.call("!"), o.call(w), 32])
	for w in "0123456789a":		# 11 scrolls: 30 items
		k.append_array([o.call("C"), o.call("?"), o.call(w), 32])
	k.append_array([o.call("C"), o.call("?"), o.call("b"), 32])	# no room
	k.append_array([o.call("i"), 32, 32])
	k.append_array([o.call("d"), o.call("C"), 32, o.call(","), 32, o.call("d"), o.call("D"), 32])
	k.append_array([32, 27, 32, 27, 27, o.call("S"), o.call("y"), o.call("y")])
	var dir := _dir.path_join("big")
	DirAccess.make_dir_recursive_absolute(dir)
	_play({"maxpack": 30}, k, 11, [""], dir)
	_check("big pack: letters past z", _seen("A) A scroll titled") and _seen("D) A scroll titled"))
	_check("big pack: the 31st does not fit", _seen("There's no room in your pack"))
	var page2 := false
	for s in _screens:
		page2 = page2 or (s.begins_with("x) ") and s.contains("--Press space to continue--"))
	_check("big pack: the inventory's second page is shown", page2)
	var as_c := 0	# "You now have ... (C)": when it was made, and when picked up again
	for s in _screens:
		if s.get_slice("\n", 0).strip_edges().ends_with("' (C)"):
			as_c += 1
	_check("big pack: a dropped C comes back as C", _seen("Dropped a scroll titled") and as_c == 2,
		as_c)
	_check("big pack: saved", FileAccess.file_exists(dir.path_join("rogue.save")))
	k = PackedInt32Array([o.call("i"), 32, 32, o.call("C"), o.call("!"), o.call("0"), 32,
		o.call("C"), o.call("!"), o.call("1"), 32, 27])
	_play(null, k, 11, ["-r"], dir)
	var c_kept := false
	for s in _screens:
		c_kept = c_kept or (s.begins_with("x) ") and s.contains("\nC) A scroll") and not s.contains("\nD) "))
	_check("big pack: restored with its letters", c_kept)
	_check("big pack: restored with its 30 slots (the 30th fits, then no room)",
		_seen("You now have 2 ") and _seen("There's no room in your pack"))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


# ---- the Guild screen ---------------------------------------------------------

## The screen's text row y.
static func _row(g: GuildScreen, y: int) -> String:
	var s := ""
	for x in 80:
		var c: int = g.cs.curscr.get_cell(y, x) & 0xFF
		s += char(c) if c >= 32 and c < 127 else "?"
	return s


func _test_screen() -> void:
	var path := _dir.path_join("screen.scr")
	_write_hall(path, [2400, 1500, 1000, 800, 700, 600, 500, 400, 350, 300, 250, 200, 150, 100,
		80, 50, 20], 20)
	var g := GuildScreen.new(path, GuildPrices.defaults())
	var got: Array = []
	g.descended.connect(func(lo: Dictionary) -> void: got.append(lo))
	_check("screen: the title and the coffers", _row(g, 0).contains("THE FIGHTERS' GUILD")
		and _row(g, 1).contains("Coffers 1834 gold: 17 of 20 heroes") and _row(g, 2).contains("Pack 5/23"))
	for c in [27, ord("q"), ord("Q"), 3, 4, 26]:
		g.key(c)
	_check("screen: no way out but down (Escape and the like do nothing)", got.is_empty()
		and _row(g, 0).contains("QUARTERMASTER'S STORES") and _row(g, 23).strip_edges() == "")
	g.key(ord("1"))
	g.key(13)
	_check("screen: Enter buys strength", g.shop.strength == 1 and _row(g, 2).contains("Spent 100")
		and _row(g, 5).contains("16 -> 17"))
	g.key(ord("2"))
	g.key(ord("j"))
	g.key(13)
	_check("screen: the cursor starts on your weapon; j and Enter take the long sword",
		g.shop.weapon == 1 and _row(g, 2).contains("Spent 290"))
	g.key(ord("6"))
	g.key(13)
	g.key(8)
	_check("screen: an identification is final (Backspace can't return it)", g.shop.pot_ids == 1
		and _row(g, 23).contains("an identification can't be returned"))
	g.key(ord("?"))
	_check("screen: ? shows the formula, with the numbers", _row(g, 2).contains(
		"coffers = best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20)") and _row(g, 3).contains(
		"= 2400 / 2 + (9400 / 20) * lerp(0.5, 1.5, 17 / 20)") and _row(g, 4).contains("= 1834 gold"))
	var ver := "Meta-Rogue " + str(ProjectSettings.get_setting("application/config/version"))
	_check("screen: ? shows the game's name and version", ver.length() > 11
		and _row(g, 23).begins_with(" " + ver + " ") and GuildScreen.version_name() == ver, _row(g, 23))
	g.key(ord(" "))
	g.key(ord("1"))
	g.key(8)
	_check("screen: Backspace returns strength", g.shop.strength == 0 and _row(g, 5).contains("16 "))
	g.key(13)
	g.key(ord("e"))
	_check("screen: e asks first", got.is_empty() and _row(g, 23).contains("Enter the Dungeons of Doom?"))
	g.key(ord("n"))
	g.key(ord("e"))
	g.key(ord("y"))
	_check("screen: y descends with the loadout", got.size() == 1 and got[0].str == 1
		and got[0].weapon.which == 1 and got[0].know_potions.size() == 1)


# ---- an edited price list -----------------------------------------------------

## A shop with an edited price list charges its prices, and the built-in ones for
## the lines it does not set; its loadout carries its counts.
func _test_edited_prices() -> void:
	var p := GuildPrices.from_text("\n".join([
		"[coffers]", "coffers = 1000 + n * 10",
		"[training]", "strength = 50 + 10 * k", "hit points per purchase = 5",
		"[your weapon]", "mace = 100   # the issued one dearer: a lighter one gives gold back",
		"[spare weapons]", "spear = 40 * 2^k",
		"[enhancing]", "polish max = 2", "charges per purchase = 3",
		"[rings]", "price = base * 2^k", "protection = 300",
		"[wands]", "light charges = 20",
		"[potions]", "identify = 10 + 5 * k",
		"[stores]", "food = 25", "darts = 6", "darts per purchase = 4",
	]))
	_check("edited prices: the list reads without an error", p.errors.is_empty(), p.errors)
	_write_hall(_dir.path_join("edited.scr"), [900, 400, 120], 20)
	var s := GuildShop.new(HallOfFame.read_file(_dir.path_join("edited.scr")), p)
	_check("edited prices: the coffers by its formula (1000 + 3 * 10)", s.coffers == 1030, s.coffers)
	s.coffers = 1 << 40
	var seq := []
	for id in ["str", "str", "str", "hp", "xw:8", "xw:8", "xw:8", "rg:0", "rg:0", "rg:9", "rg:9",
			"fd", "fd", "ip", "ip", "ms:1"]:
		var before := s.spent()
		s.buy(id)
		seq.append(s.spent() - before)
	_check("edited prices: its prices (strength 50 + 10k, spears 40 * 2^k, rings base * 2^k, food 25, "
		+ "identifications 10 + 5k, darts 6), the built-in ones elsewhere (hit points 60, "
		+ "regeneration 800)", seq == [50, 60, 70, 60, 40, 80, 160, 300, 600, 800, 1600, 25, 25, 10,
		15, 6], seq)
	_check("edited prices: its amounts (+5 hit points, 4 darts a purchase)", s.hp_now() == 17
		and _offer(s, 7, "ms:1").label == "4 darts" and _offer(s, 7, "ms:1").info == "have 4")
	var before := s.spent()
	s.buy("sw:1")
	var sword := s.spent() - before
	s.buy("sw:4")
	_check("edited prices: your weapon costs its price less the issued one's (long sword 90, the "
		+ "dagger gives 100 back)", sword == 90 and s.spent() - before == -100, [sword, s.spent() - before])
	s.coffers = s.spent() + 50
	_check("edited prices: going back to a dearer issued weapon is paid for",
		s.refund("sw:4") == GuildShop.NO_GOLD and s.weapon == 4)
	s.coffers = 1 << 40
	_check("edited prices: and refunded in full", s.refund("sw:4") == GuildShop.DONE
		and s.spent() == before)
	s.buy("rg:5")
	var adorn := s.rings.size() - 1
	var polish := []
	for i in 3:
		polish.append(s.buy("pr:%d" % adorn))
	_check("edited prices: polish max 2", polish == [GuildShop.DONE, GuildShop.DONE, GuildShop.AT_MAX],
		polish)
	s.buy("wd:0")
	s.buy("ec:0")
	var lo: Dictionary = s.loadout()
	_check("edited prices: the loadout carries the counts (hit points, darts, wand charges)",
		lo.hp == 5 and lo.missiles == [{"which": 6, "count": 4}] and lo.sticks.size() == 1
		and lo.sticks[0].charges == 23, lo)
	var ids := ["ec:0", "wd:0", "pr:%d" % adorn, "pr:%d" % adorn, "rg:5", "ms:1", "fd", "fd",
		"rg:9", "rg:9", "rg:0", "rg:0", "xw:8", "xw:8", "xw:8", "hp", "str", "str", "str"]
	var ok := true
	for id in ids:
		ok = ok and s.refund(id) == GuildShop.DONE
	_check("edited prices: every purchase returned in full (the identifications stay)", ok
		and s.spent() == 25, s.spent())


# ---- the skills ------------------------------------------------------------------

## The offer id of a skill (GuildCatalog.SKILLS' name).
static func _sk(name: String) -> String:
	for i in C.SKILLS.size():
		if C.SKILLS[i][0] == name:
			return "sk:%d" % i
	return "sk:?"


func _test_skills() -> void:
	var names := []
	for sk in C.SKILLS:
		names.append(sk[0])
	_check("skills: ten, in the order asked", names == ["frost resistance", "frost immunity", "sure sight",
		"high intellect", "low-light vision", "throw anything", "coin scrounger", "safe pockets",
		"serpentine cult", "advanced recovery"], names)
	var ok := true
	for sk in C.SKILLS:
		ok = ok and sk[0] == {"frost resistance": RogueBase.SK_FROST_RES, "frost immunity": RogueBase.SK_FROST_IMM,
			"sure sight": RogueBase.SK_SURE_SIGHT, "high intellect": RogueBase.SK_INTELLECT,
			"low-light vision": RogueBase.SK_LOW_LIGHT, "throw anything": RogueBase.SK_THROW,
			"coin scrounger": RogueBase.SK_COIN, "safe pockets": RogueBase.SK_POCKETS,
			"serpentine cult": RogueBase.SK_CULT, "advanced recovery": RogueBase.SK_RECOVERY}.get(sk[0], "")
	_check("skills: the game knows them by the same names", ok)
	var s := GuildShop.new()
	s.coffers = 100000
	var prices := []
	for sk in C.SKILLS:
		prices.append(_offer(s, GuildShop.SKILLS_SECTION, _sk(sk[0])).price)
	_check("skills: the prices", prices == [200, 300, 100, 500, 700, 200, 1000, 300, 0, 800], prices)
	var fr := _sk("frost resistance")
	var fi := _sk("frost immunity")
	_check("skills: frost immunity needs frost resistance", s.buy(fi) == GuildShop.NEEDS and s.spent() == 0
		and _offer(s, GuildShop.SKILLS_SECTION, fi).note == "needs res.")
	_check("skills: frost resistance, then frost immunity", s.buy(fr) == GuildShop.DONE and s.spent() == 200
		and s.buy(fi) == GuildShop.DONE and s.spent() == 500
		and _offer(s, GuildShop.SKILLS_SECTION, fi).note == "")
	_check("skills: each is bought once", s.buy(fr) == GuildShop.ALREADY and s.buy(fi) == GuildShop.ALREADY
		and s.spent() == 500)
	var o := _offer(s, GuildShop.SKILLS_SECTION, fr)
	_check("skills: one you have is marked yours", o.status == "yours" and o.mark == "*")
	_check("skills: frost resistance can't go back before frost immunity", s.refund(fr) == GuildShop.NEEDED
		and s.spent() == 500 and s.needed_by("frost resistance") == "Frost Immunity")
	_check("skills: returned in full", s.refund(fi) == GuildShop.DONE and s.refund(fr) == GuildShop.DONE
		and s.spent() == 0 and s.refund(fr) == GuildShop.NONE)
	var coin := _sk("coin scrounger")
	var paid := []
	for i in 3:
		var before := s.spent()
		s.buy(coin)
		paid.append(s.spent() - before)
	_check("skills: coin scrounger costs 1000, 2000, 3000", paid == [1000, 2000, 3000], paid)
	o = _offer(s, GuildShop.SKILLS_SECTION, coin)
	_check("skills: coin scrounger shows its multiplier", o.info == "gold x1 -> x4" and o.note == "next x5"
		and o.price == 4000, [o.info, o.note, o.price])
	_check("skills: in the loadout", s.loadout().skills == {"coin scrounger": 3}, s.loadout().skills)
	_check("skills: coin scrounger goes back a level at a time", s.refund(coin) == GuildShop.DONE
		and s.skill_level("coin scrounger") == 2 and s.spent() == 3000)
	_check("skills: the serpentine cult is free", s.buy(_sk("serpentine cult")) == GuildShop.DONE
		and s.spent() == 3000)
	_check("skills: no such skill", s.buy("sk:10") == GuildShop.NO_SUCH and s.refund("sk:-1") == GuildShop.NO_SUCH)
	ok = true
	var lines := s.offers(GuildShop.SKILLS_SECTION)
	for i in C.SKILLS.size():
		ok = ok and lines[i].text == C.SKILLS[i][3]
	_check("skills: ten lines, each with its description", lines.size() == 10 and ok)
	var t := GuildShop.new()
	t.coffers = 150
	_check("skills: within the coffers", t.buy(_sk("sure sight")) == GuildShop.DONE
		and t.buy(_sk("frost resistance")) == GuildShop.NO_GOLD and t.left() == 50)


func _test_skills_loadout() -> void:
	var R := RogueBase
	var s := GuildShop.new()
	s.coffers = 1 << 40
	for id in [_sk("frost resistance"), _sk("frost immunity"), _sk("coin scrounger"), _sk("coin scrounger"),
			_sk("serpentine cult")]:
		s.buy(id)
	var lo: Variant = JSON.parse_string(JSON.stringify(s.loadout()))	# as a file would give it
	var cs := _start_game(lo)
	_check("skills loadout: the game has them", R.skill(R.SK_FROST_RES) == 1 and R.skill(R.SK_FROST_IMM) == 1
		and R.skill(R.SK_COIN) == 2 and R.cult_member() and R.skill(R.SK_THROW) == 0, R.skills)
	R.guild = false
	_check("skills loadout: none out of guild mode", R.skill(R.SK_COIN) == 0 and not R.cult_member())
	_stop_game(cs)


func _test_skills_screen() -> void:
	var path := _dir.path_join("skills.scr")
	_write_hall(path, [2400, 1500, 1000], 20)
	var g := GuildScreen.new(path, GuildPrices.defaults())
	var bar := _row(g, 3)
	_check("skills screen: nine tabs, within 79 columns", bar.contains("1 Train") and bar.contains("9 Skills")
		and bar.strip_edges(false, true).length() <= 79 and bar.substr(79).strip_edges() == "", bar)
	g.key(ord("9"))
	var all := ""
	for y in 24:
		all += _row(g, y) + "\n"
	_check("skills screen: the list", all.contains("Frost Resistance") and all.contains("Advanced Recovery")
		and all.contains("gold x1") and all.contains("needs res."), all)
	_check("skills screen: the description of the line under the cursor",
		all.contains("Ice Monster can no longer instant kill you."), all)
	for i in 5:
		g.key(ord("j"))
	all = ""
	for y in 24:
		all += _row(g, y) + "\n"
	_check("skills screen: a long description is wrapped under the list", all.contains("Thrown items have effects.")
		and all.contains("You cannot throw the amulet."), all)
	for i in 5:
		g.key(ord("k"))
	g.key(ord("j"))
	g.key(13)
	_check("skills screen: frost immunity first is refused", _row(g, 23).contains("you need Frost Resistance first")
		and g.shop.skill_level("frost immunity") == 0, _row(g, 23))
	g.key(ord("k"))
	g.key(13)
	g.key(ord("j"))
	g.key(13)
	g.key(ord("k"))
	g.key(8)
	_check("skills screen: frost resistance can't go back first", _row(g, 23).contains("return Frost Immunity first")
		and g.shop.skill_level("frost resistance") == 1, _row(g, 23))
