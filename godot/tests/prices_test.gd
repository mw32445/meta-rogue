## Tests of the Fighters' Guild's price list (godot/guild_prices.txt, docs/GUILD.md
## section 7): the formulas (GuildFormula); the file's reader (GuildPrices): its
## syntax, the lines it can't read and what it uses instead; the shipped file
## against the built-in list and both against the prices the Guild had before the
## file; the coffers formula against the old integer one; files that change prices;
## the places the game looks in; the Guild screen's messages.
##   godot --headless --path godot --script res://tests/prices_test.gd
## Prints FAIL for each failed check, then a summary; exit status 1 if any check
## fails. Works in (and removes) the folder "prices_test" of the project's user data
## folder; it never reads or writes the player's guild_prices.txt.
extends SceneTree

const C := preload("res://guild/catalog.gd")
const SHIPPED := "res://guild_prices.txt"

## The prices the Guild had before its price list was a file (GuildCatalog's
## constants and its exact integer grow()): a number is a flat price (or an
## amount); [base, num, den] the price floor(base * (num / den)^k).
const BEFORE := {
	"training": {"strength": [100, 2, 1], "hit points": [60, 2, 1], "hit points per purchase": 2},
	"your weapon": {"dagger": 0, "spear": 0, "mace": 0, "long sword": 190,
		"two handed sword": 540},
	"spare weapons": {"spear": 40, "mace": 60, "long sword": 250, "two handed sword": 600},
	"your armour": {"leather armor": 0, "studded leather armor": 0, "ring mail": 0,
		"scale mail": 140, "chain mail": 340, "splint mail": 640, "banded mail": 640,
		"plate mail": 1040},
	"spare armour": {"leather armor": 20, "studded leather armor": 60, "ring mail": 60,
		"scale mail": 200, "chain mail": 400, "splint mail": 700, "banded mail": 700,
		"plate mail": 1100},
	"enhancing": {"weapon": [75, 2, 1], "armour": [100, 2, 1], "ring": [150, 2, 1],
		"polish": [5, 2, 1], "polish max": 7, "wand charges": [80, 2, 1],
		"charges per purchase": 2},
	"rings": {"protection": [500, 4, 1], "add strength": [500, 4, 1],
		"sustain strength": [400, 4, 1], "searching": [250, 4, 1], "see invisible": [300, 4, 1],
		"adornment": [0, 4, 1], "aggravate monster": [10, 4, 1], "dexterity": [450, 4, 1],
		"increase damage": [550, 4, 1], "regeneration": [900, 4, 1],
		"slow digestion": [700, 4, 1], "teleportation": [200, 4, 1], "stealth": [600, 4, 1],
		"maintain armor": [400, 4, 1]},
	"wands": {"charges": 5, "light charges": 15, "light": [120, 4, 1],
		"invisibility": [5, 4, 1], "lightning": [600, 4, 1], "fire": [600, 4, 1],
		"cold": [600, 4, 1], "polymorph": [300, 4, 1], "magic missile": [250, 4, 1],
		"haste monster": [5, 4, 1], "slow monster": [650, 4, 1], "drain life": [400, 4, 1],
		"nothing": [5, 4, 1], "teleport away": [900, 4, 1], "teleport to": [150, 4, 1],
		"cancellation": [500, 4, 1]},
	"potions": {"identify": 40, "confusion": [5, 2, 1], "hallucination": [5, 2, 1],
		"poison": [5, 2, 1], "gain strength": [180, 2, 1], "see invisible": [40, 2, 1],
		"healing": [120, 2, 1], "monster detection": [30, 2, 1], "magic detection": [50, 2, 1],
		"raise level": [250, 2, 1], "extra healing": [200, 2, 1], "haste self": [100, 2, 1],
		"restore strength": [60, 2, 1], "blindness": [5, 2, 1], "levitation": [20, 2, 1]},
	"scrolls": {"identify": 40, "monster confusion": [20, 2, 1], "magic mapping": [100, 2, 1],
		"hold monster": [70, 2, 1], "sleep": [5, 2, 1], "enchant armor": [200, 2, 1],
		"identify potion": [30, 2, 1], "identify scroll": [25, 2, 1],
		"identify weapon": [25, 2, 1], "identify armor": [30, 2, 1],
		"identify ring, wand or staff": [40, 2, 1], "scare monster": [160, 2, 1],
		"food detection": [20, 2, 1], "teleportation": [160, 2, 1],
		"enchant weapon": [200, 2, 1], "create monster": [10, 2, 1], "remove curse": [50, 2, 1],
		"aggravate monsters": [5, 2, 1], "protect armor": [120, 2, 1]},
	"stores": {"food": [30, 13, 10], "pack slot": [50, 3, 2], "arrows": 10,
		"arrows per purchase": 10, "darts": 8, "darts per purchase": 10, "shuriken": 25,
		"shuriken per purchase": 5, "daggers": 30, "daggers per purchase": 2},
}

var _fails := 0
var _passes := 0
var _dir := ""


func _initialize() -> void:
	_dir = OS.get_user_data_dir().path_join("prices_test")
	_clean(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	_test_formulas()
	_test_functions()
	_test_formula_errors()
	_test_file()
	_test_late_errors()
	_test_lists()
	_test_shipped()
	_test_coffers()
	_test_override()
	_test_places()
	_test_every_name()
	_test_screen()
	_clean(_dir)
	print("prices_test: %d passed, %d failed" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func _check(name: String, ok: bool, detail: Variant = "") -> void:
	if ok:
		_passes += 1
	else:
		_fails += 1
		print("FAIL ", name, "  ", detail)


func _clean(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for d in DirAccess.get_directories_at(dir):
		_clean(dir.path_join(d))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## A formula's value, or its error.
static func _value(text: String, vars := {}) -> Variant:
	var f := GuildFormula.parse(text, vars.keys())
	if f.error != "":
		return f.error
	var x := f.evaluate(vars)
	return f.last_error if f.last_error != "" else x


static func _near(got: Variant, want: float) -> bool:
	return (got is float or got is int) and absf(got - want) <= 1e-9 * maxf(1.0, absf(want))


# ---- formulas -----------------------------------------------------------------------

func _test_formulas() -> void:
	var cases := [
		["1 + 2 * 3", {}, 7.0],
		["(1 + 2) * 3", {}, 9.0],
		["10 - 4 - 3", {}, 3.0],		# left to right
		["64 / 4 / 2", {}, 8.0],
		["7 / 2", {}, 3.5],			# exact division
		["2 ^ 3 ^ 2", {}, 512.0],		# right to left
		["-2^2", {}, -4.0],			# ^ above the sign
		["(-2)^2", {}, 4.0],
		["2^-1", {}, 0.5],
		["-2^-2", {}, -0.25],
		["2 * 3^2", {}, 18.0],
		["2^3 * 2", {}, 16.0],
		["2^-k * 8", {"k": 2}, 2.0],
		["3 - -2", {}, 5.0],
		["+3", {}, 3.0],
		["- (2 + 3) * 2", {}, -10.0],
		["1.5 * 2", {}, 3.0],
		[".5 + 5.", {}, 5.5],
		["1e3 + 2.5E-1", {}, 1000.25],
		["2 ** 10", {}, 1024.0],
		["  100*2^k  ", {"k": 3}, 800.0],
		["K * 2", {"k": 3}, 6.0],		# names in any case
		["30 * 1.3^k", {"k": 2}, 50.7],
		["base * 4^k", {"k": 2, "base": 500}, 8000.0],
		["best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20)", {"best": 2400, "sum": 9400, "n": 17},
			1834.5],
	]
	for c in cases:
		var got: Variant = _value(c[0], c[1])
		_check("formula: %s = %s" % [c[0], c[2]], _near(got, c[2]), got)
	var deep: Variant = _value("(".repeat(98) + "k" + ")".repeat(98) + "+1", {"k": 1})
	_check("formula: 98 brackets deep (199 parts; 200 at most)", _near(deep, 2.0), deep)


func _test_functions() -> void:
	var cases := [
		["floor(2.7)", 2.0], ["floor(-2.5)", -3.0], ["ceil(2.1)", 3.0], ["ceil(-2.1)", -2.0],
		["round(2.5)", 3.0], ["round(2.4)", 2.0], ["min(3, 1, 2)", 1.0], ["max(1, 5)", 5.0],
		["max(1, 5, 9, 2)", 9.0], ["pow(2, 10)", 1024.0], ["pow(4, 0.5)", 2.0], ["sqrt(16)", 4.0],
		["abs(-3)", 3.0], ["abs(3)", 3.0], ["clamp(15, 0, 10)", 10.0], ["clamp(-5, 0, 10)", 0.0],
		["clamp(5, 0, 10)", 5.0], ["lerp(0.5, 1.5, 0.5)", 1.0], ["lerp(10, 20, 0.25)", 12.5],
		["FLOOR(2.5) + Max(1, 2)", 4.0], ["min(max(1, 2) * 3, 10 - 5)", 5.0],
		["floor(7 / 2) * 10", 30.0],
	]
	for c in cases:
		var got: Variant = _value(c[0])
		_check("function: %s = %s" % [c[0], c[1]], _near(got, c[1]), got)


func _test_formula_errors() -> void:
	var k := {"k": 3}
	var cases := [
		["kk", k, "unknown name 'kk'"],
		["base * 2", k, "unknown name 'base'"],
		["pow(2)", {}, "pow takes 2 arguments"],
		["floor(1, 2)", {}, "floor takes 1 argument"],
		["min(1)", {}, "min takes 2 or more arguments"],
		["lerp(1, 2)", {}, "lerp takes 3 arguments"],
		["clamp(1)", {}, "clamp takes 3 arguments"],
		["sqrt()", {}, "sqrt takes 1 argument"],
		["(1 + 2", {}, "expected ')'"],
		["min(1 2)", {}, "expected ')'"],
		["1 +", {}, "something is missing at the end"],
		["", {}, "there is no value"],
		["1 2", {}, "an operator (+ - * / ^) is missing before '2'"],
		["2k", k, "an operator (+ - * / ^) is missing before 'k'"],
		["1 $ 2", {}, "unexpected '$'"],
		["1 + )", {}, "unexpected ')'"],
		["1,000", {}, "unexpected ','"],
		["* 3", {}, "unexpected '*'"],
		["foo(1)", {}, "unknown function 'foo'"],
		["k(2)", k, "'k' is not a function"],
		["floor", {}, "floor needs brackets: floor(...)"],
		["1.2.3", {}, "'1.2.3' is not a number"],
		["(".repeat(150) + "1" + ")".repeat(150), {}, "the formula is too long"],
		["1" + "+1".repeat(5000), {}, "the formula is too long"],
		# when computed
		["1 / 0", {}, "division by zero"],
		["1 / (k - 3)", k, "division by zero"],
		["sqrt(-1)", {}, "the square root of a negative number"],
		["(-8)^(1/3)", {}, "a power of a negative number that is not whole"],
		["0^-1", {}, "division by zero"],
		["pow(0, -2)", {}, "division by zero"],
	]
	for c in cases:
		var got: Variant = _value(c[0], c[1])
		_check("formula error: %s -> %s" % [c[0], c[2]], got is String and got == c[2], got)
	var f := GuildFormula.parse("10 / (k - 3)", ["k"])
	var bad := f.evaluate({"k": 3})
	var good := f.evaluate({"k": 5})
	_check("formula error: NAN when it fails, and the next evaluation is fine", is_nan(bad)
		and good == 5.0 and f.last_error == "", [bad, good, f.last_error])
	f = GuildFormula.parse("best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20)", ["best", "sum", "n"])
	var shown := f.with_values({"best": 2400, "sum": 9400, "n": 17})
	_check("formula: with its values", shown == "2400 / 2 + (9400 / 20) * lerp(0.5, 1.5, 17 / 20)",
		shown)
	shown = GuildFormula.parse("Base*4^K", ["base", "k"]).with_values({"base": 500, "k": 2.5})
	_check("formula: with its values (any case, fractions)", shown == "500*4^2.5", shown)


# ---- the file -------------------------------------------------------------------------

func _test_file() -> void:
	var text := "\n".join([
		"strength = 1",					# 1: before any section
		"# a comment line",				# 2
		"[training]   # the training",		# 3
		"strength = 100 * 3^k   # a trailing comment",	# 4
		"hit points = 60 * 2^kk",			# 5: unknown name
		"hit points per purchase = 3",			# 6
		"",						# 7
		"[Your  Weapon]",				# 8: any case and spacing
		"  Long   Sword =150",				# 9
		"[scrolls]",					# 10
		"identify ring, wand or staff = 33",		# 11: a comma in the name
		"identify = 40 *",				# 12: syntax error
		"strength = 5",					# 13: another section's
		"foo = 1",					# 14: no such name
		"[bogus]",					# 15: no such section
		"anything = 1",					# 16: (under it: not read)
		"[stores]",					# 17
		"food 30",					# 18: no =
		"food = 20",					# 19
		"food = 25",					# 20: twice
		"darts per purchase = 0",			# 21: out of range
		"pack slot = -5",				# 22: below 0
		"arrows = 1 / k",				# 23: fails at k = 0
		"daggers = ",					# 24: no value
		"[enhancing",					# 25: a broken heading
		"polish = 3",					# 26: (under it: not read)
		"[enhancing]",					# 27
		"polish max = 25",				# 28: out of range
		"charges per purchase = 1e9",			# 29: out of range
		"wand charges = 1e16",				# 30: over the dearest price
	])
	var p := GuildPrices.from_text(text)
	var want := [
		"guild_prices.txt line 1: 'strength' comes before the first [section]",
		"guild_prices.txt line 5: unknown name 'kk' (using 60 * 2^k)",
		"guild_prices.txt line 12: something is missing at the end (using 40)",
		"guild_prices.txt line 13: there is no 'strength' in [scrolls] (it is in [training])",
		"guild_prices.txt line 14: there is no 'foo' in [scrolls]",
		"guild_prices.txt line 15: unknown section [bogus]",
		"guild_prices.txt line 18: expected 'name = value'",
		"guild_prices.txt line 20: 'food' is set on line 19 already (this line is not used)",
		"guild_prices.txt line 21: darts per purchase must be from 1 to 1000 (not 0) (using 10)",
		"guild_prices.txt line 22: a price can't be below 0 (here -5 when k = 0) (using 50 * 1.5^k)",
		"guild_prices.txt line 23: division by zero when k = 0 (using 10)",
		"guild_prices.txt line 24: there is no value (using 30)",
		"guild_prices.txt line 25: a heading is written [name]",
		"guild_prices.txt line 28: polish max must be from 0 to 20 (not 25) (using 7)",
		"guild_prices.txt line 29: charges per purchase must be from 1 to 1000 (not 1000000000)"
			+ " (using 2)",
		"guild_prices.txt line 30: a price can't be over 1000000000000000 (here 10000000000000000"
			+ " when k = 0)"
			+ " (using 80 * 2^k)",
	]
	_check("file: every line that can't be read is reported, in order", p.errors == want,
		"\n".join(p.errors))
	for i in maxi(want.size(), p.errors.size()):
		var a: String = want[i] if i < want.size() else "(none)"
		var b: String = p.errors[i] if i < p.errors.size() else "(none)"
		if a != b:
			print("  want: ", a, "\n  got:  ", b)
	_check("file: what it sets (comments, spacing and case, a comma in a name)",
		p.price("training", "strength", 1) == 300 and p.amount("training", "hit points per purchase") == 3
		and p.price("your weapon", "long sword") == 150
		and p.price("scrolls", "identify ring, wand or staff", 1) == 66,
		[p.price("training", "strength", 1), p.price("your weapon", "long sword"),
		p.price("scrolls", "identify ring, wand or staff", 1)])
	_check("file: the first of a line set twice", p.price("stores", "food", 3) == 20)
	_check("file: the original values where a line can't be read",
		p.price("training", "hit points", 1) == 120 and p.price("scrolls", "identify") == 40
		and p.amount("stores", "darts per purchase") == 10 and p.price("stores", "pack slot", 2) == 112
		and p.price("stores", "arrows", 4) == 10 and p.price("stores", "daggers") == 30
		and p.price("enhancing", "polish", 2) == 20 and p.amount("enhancing", "polish max") == 7
		and p.amount("enhancing", "charges per purchase") == 2
		and p.price("enhancing", "wand charges", 1) == 160)
	_check("file: and where it sets none", p.price("rings", "protection", 1) == 2000
		and p.price("training", "strength", 0) == 100)
	_check("file: no path for a text", p.path == "" and p.where() == "")
	# Windows line ends and a byte order mark
	p = GuildPrices.from_text("\ufeff[training]\r\nstrength = 7\r\n# end\r\n")
	_check("file: Windows line ends, a byte order mark", p.errors.is_empty()
		and p.price("training", "strength", 5) == 7, p.errors)
	p = GuildPrices.from_text("")
	_check("file: an empty file is the built-in list", p.errors.is_empty()
		and p.price("stores", "food", 2) == 50)
	# what a line quotes in a message is cut short
	p = GuildPrices.from_text("[training]\n%s = 1\nstrength = %s\n[%s]\n" % ["x".repeat(500),
		"9".repeat(300) + " " + "y".repeat(300), "z".repeat(100)])
	_check("file: long text in a message is cut short", p.errors == [
		"guild_prices.txt line 2: there is no '%s...' in [training]" % "x".repeat(37),
		"guild_prices.txt line 3: an operator (+ - * / ^) is missing before '%s...' (using 100 * 2^k)"
			% "y".repeat(37),
		"guild_prices.txt line 4: unknown section [%s...]" % "z".repeat(37)], p.errors)


## A formula that fails for a later k: reported once, when met; the built-in value is
## used whenever it fails.
func _test_late_errors() -> void:
	var p := GuildPrices.from_text("[training]\nstrength = 100 / (3 - k)\n")
	_check("late error: none when read (it works at k = 0)", p.errors.is_empty()
		and p.price("training", "strength", 0) == 33, p.errors)
	var at3 := p.price("training", "strength", 3)
	var again := p.price("training", "strength", 3)
	var at4 := p.price("training", "strength", 4)
	_check("late error: at k = 3 the built-in price, reported once", at3 == 800 and again == 800
		and p.errors == ["guild_prices.txt line 2: division by zero when k = 3 (using 100 * 2^k)"],
		[at3, p.errors])
	_check("late error: a price below 0 is free", at4 == 0, at4)
	p = GuildPrices.from_text("[coffers]\ncoffers = best / n + 7\n")
	var empty := p.coffers(0, 0, 0)
	var one := p.coffers(500, 500, 1)
	_check("late error: the coffers, with the numbers they failed for", empty == 0 and one == 507
		and p.errors == ["guild_prices.txt line 2: division by zero when best = 0, sum = 0, n = 0"
		+ " (using best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20))"], [empty, one, p.errors])
	var f := p.formula_of("coffers", "coffers", {"best": 0, "sum": 0, "n": 0})
	var g := p.formula_of("coffers", "coffers", {"best": 500, "sum": 500, "n": 1})
	_check("late error: the formula used for those numbers", f.text.begins_with("best / 2 + (sum")
		and g.text == "best / n + 7")
	p = GuildPrices.from_text("[coffers]\ncoffers = 1e20 - best\n[training]\nstrength = 2^k\n")
	_check("late error: none for too much: the dearest price is 10^15",
		p.coffers(5, 5, 1) == GuildPrices.PRICE_MAX and p.price("training", "strength", 60)
		== GuildPrices.PRICE_MAX and p.errors.is_empty(), p.errors)


## [rings], [wands], [potions], [scrolls]: each kind's number is base for the price.
func _test_lists() -> void:
	var p := GuildPrices.from_text("[wands]\nprice = base + 100 * k\nlight = 50\n")
	_check("lists: the price formula with each kind's number", p.price("wands", "light", 2) == 250
		and p.price("wands", "fire", 1) == 700 and p.price("wands", "price", 3, 7) == 307)
	p = GuildPrices.from_text("[rings]\nprice = 1000 / base\n")
	_check("lists: a price formula that fails for a kind (adornment, base 0) is not used",
		p.price("rings", "protection", 1) == 2000 and p.errors == [
		"guild_prices.txt line 2: division by zero when k = 0, base = 0 (using base * 4^k)"],
		p.errors)
	p = GuildPrices.from_text("[rings]\nprotection = -5\nstealth = 10 * (k + 1)\n")
	_check("lists: a kind's number below 0 is not used; one may use k",
		p.price("rings", "protection") == 500 and p.price("rings", "stealth", 1) == 80
		and p.errors == ["guild_prices.txt line 2: a price can't be below 0 (here -5 when k = 0)"
		+ " (using 500)"], p.errors)


# ---- the shipped file ---------------------------------------------------------------

## floor(base * (num / den)^k) in exact integers (GuildCatalog.grow() before the file).
static func _grow(base: int, num: int, den: int, k: int) -> int:
	var n := base
	var d := 1
	for i in k:
		n *= num
		d *= den
	return n / d


func _test_shipped() -> void:
	var text := FileAccess.get_file_as_string(SHIPPED)
	_check("shipped: res://guild_prices.txt is GuildCatalog.PRICES, character for character"
		+ " (copy one onto the other)", text == C.PRICES, "%d and %d characters" % [text.length(),
		C.PRICES.length()])
	var file := GuildPrices.from_file(SHIPPED)
	var built := GuildPrices.defaults()
	_check("shipped: read without an error", file.errors.is_empty() and file.path == SHIPPED,
		file.errors)
	_check("shipped: the built-in list has no error", built.errors.is_empty(), built.errors)
	var names := file.entry_names()
	var used := file.lines_used()
	_check("shipped: it sets every line of the list (%d)" % names.size(), used.size() == names.size()
		and names.size() == built.entry_names().size(), used.size())
	# against the prices before the file, k = 0 to 12
	var seen := 0
	for e in names:
		var section: String = e[0]
		var nm: String = e[1]
		if section == "coffers" or (GuildPrices.LISTS.has(section) and nm == "price"):
			continue
		var was: Variant = BEFORE.get(section, {}).get(nm)
		if was == null:
			_check("shipped: [%s] %s was in the catalog" % [section, nm], false)
			continue
		seen += 1
		if GuildPrices.AMOUNTS.get(section, {}).has(nm):
			_check("shipped: [%s] %s = %d, as before" % [section, nm, was], file.amount(section, nm)
				== was and built.amount(section, nm) == was, file.amount(section, nm))
			continue
		var bad := []
		for k in 13:
			var want: int = was if was is int else _grow(was[0], was[1], was[2], k)
			if file.price(section, nm, k) != want or built.price(section, nm, k) != want:
				bad.append([k, want, file.price(section, nm, k), built.price(section, nm, k)])
		_check("shipped: [%s] %s, k = 0 to 12, as before" % [section, nm], bad.is_empty(), bad)
	var all := 0
	for section in BEFORE:
		all += BEFORE[section].size()
	_check("shipped: every price of before is in it (%d of %d)" % [seen, all], seen == all)
	# the kinds the shop sells, by the catalog's names
	var missing := []
	for t in [["rings", C.RINGS], ["wands", C.STICKS], ["potions", C.POTIONS],
			["scrolls", C.SCROLLS]]:
		for kind in t[1]:
			if not BEFORE[t[0]].has(kind[0]):
				missing.append(kind[0])
	for w in C.WEAPON_START_ORDER:
		if not BEFORE["your weapon"].has(C.WEAPONS[w][0]):
			missing.append(C.WEAPONS[w][0])
	for w in C.WEAPON_SPARE_ORDER:
		if not BEFORE["spare weapons"].has(C.WEAPONS[w][0]):
			missing.append(C.WEAPONS[w][0])
	for a in C.ARMOR_ORDER:
		if not BEFORE["your armour"].has(C.ARMORS[a][0]) or not BEFORE["spare armour"].has(
				C.ARMORS[a][0]):
			missing.append(C.ARMORS[a][0])
	for m in C.MISSILES:
		if not BEFORE["stores"].has(m[1]) or not BEFORE["stores"].has(m[1] + " per purchase"):
			missing.append(m[1])
	_check("shipped: a line for every kind the catalog sells", missing.is_empty(), missing)
	var bases := [0, 5, 120, 900]
	var same := true
	for section in GuildPrices.LISTS:
		for b in bases:
			for k in 13:
				same = same and file.price(section, "price", k, b) == built.price(section, "price", k, b)
	_check("shipped: the lists' price formulas", same)


# ---- the coffers ------------------------------------------------------------------------

func _test_coffers() -> void:
	var p := GuildPrices.from_file(SHIPPED)
	var cases := [[1000, 1000, 1, 527], [1000, 5500, 10, 775], [500, 10000, 20, 1000],
		[2400, 9400, 17, 1834], [0, 0, 0, 0]]
	var ok := true
	for c in cases:
		ok = ok and p.coffers(c[0], c[1], c[2]) == c[3]
	_check("coffers: the samples of docs/GUILD.md (527, 775, 1000, 1834, 0)", ok)
	# best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20) = (200 * best + sum * (10 + n)) / 400:
	# rounded down once, where the old formula, best / 2 + sum * (10 + n) / 400 in
	# integers, rounded each term down
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261012
	var bad := []
	var more := 0
	var tried := 0
	for i in 3000:
		var n := rng.randi_range(0, 20)
		var best := 0 if n == 0 else rng.randi_range(1, [100, 5000, 100000, 50000000][i % 4])
		var sum := best
		for j in n - 1:
			sum += rng.randi_range(1, best)
		if n == 0:
			sum = 0
		var old := best / 2 + sum * (10 + n) / 400
		var exact := (200 * best + sum * (10 + n)) / 400
		var got := p.coffers(best, sum, n)
		tried += 1
		if got != exact or got - old < 0 or got - old > 1:
			bad.append([best, sum, n, got, exact, old])
		elif got != old:
			more += 1
	_check("coffers: %d Halls of Fame: the formula exactly, at most 1 more than the old one"
		% tried + " (1 more in %d)" % more, bad.is_empty() and more > 0, bad.slice(0, 5))


# ---- files ------------------------------------------------------------------------------

func _test_override() -> void:
	var path := _dir.path_join("override.txt")
	_write(path, "# my Guild\n[coffers]\ncoffers = 500 + sum\n[training]\nstrength = 7 * (k + 1)\n"
		+ "[stores]\narrows per purchase = 25\n")
	var p := GuildPrices.from_file(path)
	_check("override: read", p.errors.is_empty() and p.path == path, p.errors)
	_check("override: a price, an amount and the coffers change",
		p.price("training", "strength", 2) == 21 and p.amount("stores", "arrows per purchase") == 25
		and p.coffers(100, 1000, 3) == 1500)
	_check("override: the rest is the built-in list", p.price("rings", "protection", 1) == 2000
		and p.price("training", "hit points", 2) == 240 and p.amount("wands", "charges") == 5)
	var h := HallOfFame.new()
	h.best = 100
	h.total = 1000
	h.heroes = 3
	var s := GuildShop.new(h, p)
	s.buy("ms:0")
	s.buy("ms:0")
	_check("override: a shop with it (coffers 1500, 50 arrows for 20 gold)", s.coffers == 1500
		and h.coffers(p) == 1500 and h.coffers() == 82 and s.loadout().arrows == 50
		and s.spent() == 20, [s.coffers, h.coffers(), s.loadout().arrows])
	_check("override: its path, in full", p.where() == path and not p.where().begins_with("user://"))
	p = GuildPrices.from_file(_dir.path_join("no such file.txt"))
	_check("override: a file that can't be opened: the built-in list, and why", p.path == ""
		and p.errors.size() == 1 and p.errors[0].ends_with("can't be opened (using the built-in prices)")
		and p.price("training", "strength", 1) == 200, p.errors)


## read_from(): the first file found; else the default list written where it can be.
func _test_places() -> void:
	var dir := _dir.path_join("places")
	DirAccess.make_dir_recursive_absolute(dir)
	var a := dir.path_join("a.txt")
	var b := dir.path_join("b.txt")
	var places: Array[String] = [a, b]
	var none: Array[String] = []
	var p := GuildPrices.read_from(places, none, "")
	_check("places: none, nowhere to write, nothing shipped: the built-in list", p.path == ""
		and p.errors.is_empty() and not FileAccess.file_exists(a))
	p = GuildPrices.read_from(places, none, SHIPPED)
	_check("places: none, nowhere to write: the shipped file", p.path == SHIPPED)
	var unwritable: Array[String] = [dir.path_join("no such folder").path_join("x.txt"), b]
	p = GuildPrices.read_from(places, unwritable, SHIPPED)
	_check("places: none: the shipped file is written to the first place that takes it",
		p.path == b and FileAccess.file_exists(b) and FileAccess.get_file_as_string(b)
		== FileAccess.get_file_as_string(SHIPPED) and p.errors.is_empty(), p.path)
	DirAccess.remove_absolute(b)
	p = GuildPrices.read_from(places, places, "")
	_check("places: with nothing shipped, the built-in list is written", p.path == a
		and FileAccess.get_file_as_string(a) == C.PRICES)
	_write(b, "[training]\nstrength = 1\n")
	p = GuildPrices.read_from(places, places, SHIPPED)
	_check("places: the first that exists is read", p.path == a and p.price("training", "strength")
		== 100)
	DirAccess.remove_absolute(a)
	p = GuildPrices.read_from(places, places, SHIPPED)
	_check("places: and only it", p.path == b and p.price("training", "strength") == 1
		and not FileAccess.file_exists(a))
	_write(b, "[training]\nstrength = 2\n")
	p = GuildPrices.read_from(places, places, SHIPPED)
	_check("places: read again each time (an edit counts at once)",
		p.price("training", "strength") == 2)
	# the game's read(): from source (this editor binary) it only reads: the user data
	# folder's file if there is one (the player's: its values are not checked), else
	# the shipped one
	var mine := "user://" + GuildPrices.FILE_NAME
	var had := FileAccess.file_exists(mine)
	p = GuildPrices.read()
	_check("places: read() from source reads %s, writes nothing" % ("the player's file" if had
		else "the shipped file"), p != null and p.path == (mine if had else SHIPPED)
		and FileAccess.file_exists(mine) == had and (had or p.errors.is_empty()),
		[p.path if p != null else null, had])


## Every name the shop and the loadout ask the list for is in it: a shop with every
## kind of purchase, every line on offer (every potion and scroll identified), and
## its loadout ask for no line the list lacks.
func _test_every_name() -> void:
	var p := GuildPrices.from_text("")
	var s := GuildShop.new(null, p)
	s.coffers = 1 << 50
	var ids := []
	for i in 29:
		ids.append("pk")
	for i in C.POTIONS.size():
		ids.append("ip")
	for i in C.SCROLLS.size():
		ids.append("is")
	ids.append_array(["str", "hp", "sw:1", "ew:you", "ew:bow", "sa:7", "ea:you", "fd", "xw:8",
		"ew:0", "xa:0", "ea:0", "rg:0", "er:0", "rg:5", "pr:1", "wd:0", "ec:0", "ms:0", "ms:1",
		"ms:2", "ms:3", "bp:0", "bs:0"])
	var refused := []
	for id in ids:
		var why := s.buy(id)
		if why != GuildShop.DONE:
			refused.append([id, why])
	var lines := 0
	for section in GuildShop.SECTIONS.size():
		lines += s.offers(section).size()
	var lo := s.loadout()
	_check("every name: a shop with every kind of purchase and every line on offer (%d) asks"
		% lines + " for no line the list lacks", refused.is_empty() and p.errors.is_empty()
		and lo.sticks[0].charges == 17 and s.spent() > 0, [refused, p.errors])


# ---- the Guild screen ---------------------------------------------------------------------

static func _row(g: GuildScreen, y: int) -> String:
	var s := ""
	for x in 80:
		var c: int = g.cs.curscr.get_cell(y, x) & 0xFF
		s += char(c) if c >= 32 and c < 127 else "?"
	return s


func _test_screen() -> void:
	var hall := _dir.path_join("none.scr")
	var p := GuildPrices.from_text("[training]\nstrength = 100 * 2^kk\nhit points = 60 * 2^k\n"
		+ "[stores]\nfood = 1 / 0\n")
	var g := GuildScreen.new(hall, p)
	_check("screen: the first error on the bottom line, and how many there are", _row(g, 23)
		.strip_edges() == "guild_prices.txt line 2: unknown name 'kk' (using 100 * 2^k) (? shows all 2)",
		_row(g, 23))
	g.key(ord("j"))
	_check("screen: until a key is pressed", _row(g, 23).strip_edges() == "", _row(g, 23))
	g.key(ord("?"))
	var page := ""
	for y in 24:
		page += _row(g, y) + "\n"
	_check("screen: ? shows that the prices are built in (a text has no file)",
		page.contains("The prices are the built-in ones.") and page.contains("Not used (the original")
		and page.contains("unknown name 'kk'") and page.contains("division by zero when k = 0"), page)
	g.key(ord(" "))
	# a file's path on the ? page
	var path := _dir.path_join("screen.txt")
	_write(path, "[training]\nstrength = 100 / (2 - k)\n")
	g = GuildScreen.new(hall, GuildPrices.from_file(path))
	_check("screen: no error, an empty bottom line", _row(g, 23).strip_edges() == "")
	g.key(ord("?"))
	page = ""
	for y in 24:
		page += _row(g, y) + "\n"
	_check("screen: ? shows the file's path", page.contains("The prices are in this file")
		and page.contains(path), page)
	g.key(ord(" "))
	# an error met later shows when it is met
	g.shop.coffers = 100000
	g.key(13)	# strength: 50; the next, 100
	var before := _row(g, 23).strip_edges()
	g.key(13)	# strength: 100; the next, k = 2, divides by zero
	_check("screen: an error met later shows when it is met", before == "" and _row(g, 23)
		.contains("line 2: division by zero when k = 2 (using 100 * 2^k)") and g.shop.strength == 2,
		[before, _row(g, 23)])
	# a long one takes two lines
	g = GuildScreen.new(hall, GuildPrices.from_text("[coffers]\ncoffers = best / n\n"))
	var two := _row(g, 22).strip_edges() + " " + _row(g, 23).strip_edges()
	_check("screen: a long message takes the line above too", two == "guild_prices.txt line 2:"
		+ " division by zero when best = 0, sum = 0, n = 0 (using best / 2 + (sum / 20) * lerp(0.5,"
		+ " 1.5, n / 20))", [_row(g, 22), _row(g, 23)])
	g.key(ord("j"))
	_check("screen: and gives it back", _row(g, 22).contains("Enter buy  Backspace return")
		and _row(g, 23).strip_edges() == "")
	g.key(ord("?"))
	_check("screen: ? shows the formula used for these numbers (the built-in one, here)",
		_row(g, 2).contains("coffers = best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20)")
		and _row(g, 3).contains("= 0 / 2 + (0 / 20) * lerp(0.5, 1.5, 0 / 20)")
		and _row(g, 4).contains("= 0 gold"), [_row(g, 2), _row(g, 3), _row(g, 4)])
