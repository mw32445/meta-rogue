## The Fighters' Guild: its price list, read from guild_prices.txt (docs/GUILD.md).
##
## The file (godot/guild_prices.txt; GuildCatalog.PRICES is its built-in copy) has
## [section] headings and "name = value" lines; "#" starts a comment, and a name is
## everything before the first "=". A value is a GuildFormula over the names its
## line allows:
##   coffers ([coffers])             best, sum and n: the Hall of Fame's
##   the amounts (AMOUNTS)           none: a whole number in a range
##   price ([rings], [wands],
##     [potions], [scrolls])         k, and base: the kind's own number
##   every other line, a price       k: how many of that line were bought already
## Prices are whole gold pieces, rounded down, from 0 to PRICE_MAX.
##
## A line the file does not set keeps its built-in value. So does one that can't
## be read (a syntax error, an unknown name, a name its section does not have, a
## value out of range, ...), and `errors` says so with its line number, e.g.
## "guild_prices.txt line 12: unknown name 'kk' (using 100 * 2^k)". Every formula
## is tried when the file is read: a price at k = 0, an amount for its range. One
## that fails later (a division by zero at some k, ...) is reported then, and the
## built-in value is used whenever it fails.
##
## read() is the game's: the first file found of
##   1. the folder of the game's executable (an exported game, on a desktop);
##   2. the user data folder (user://guild_prices.txt);
##   3. the project (res://guild_prices.txt: godot/ in a source download).
## An exported game that finds neither 1 nor 2 writes the default list to 1, or if
## it can't, to 2, for the player to edit. defaults(), from_text(), from_file() and
## read_from() touch no file of the player's (the tests use them).
class_name GuildPrices
extends RefCounted

const C := preload("res://guild/catalog.gd")	## GuildCatalog

const FILE_NAME := "guild_prices.txt"
## The dearest a price (or the coffers) can be: 10^15 gold pieces.
const PRICE_MAX := 1000000000000000
## The sections whose kinds each have their own number (base) and share a price
## formula ("price").
const LISTS: Array[String] = ["rings", "wands", "potions", "scrolls"]
## The lines that are amounts, not prices: whole numbers, from the first number
## to the second.
const AMOUNTS := {
	"training": {"hit points per purchase": [1, 1000]},
	"enhancing": {"polish max": [0, C.POLISH_LIMIT], "charges per purchase": [1, 1000]},
	"wands": {"charges": [1, 1000], "light charges": [1, 1000]},
	"stores": {"arrows per purchase": [1, 1000], "darts per purchase": [1, 1000],
		"shuriken per purchase": [1, 1000], "daggers per purchase": [1, 1000]},
}

## The file the prices were read from ("" for the built-in list).
var path := ""
## What could not be read or computed: the file's lines in order, then what
## failed later.
var errors: Array[String] = []

## section -> name -> Entry, in the order of the built-in list.
var _entries := {}
## The file's name in the messages.
var _file := FILE_NAME
## While reading a file: its errors as [line, message], sorted at the end.
var _loading := false
var _pending: Array = []

static var _builtin: GuildPrices = null


## One line of the price list.
class Entry:
	extends RefCounted
	var section := ""
	var name := ""
	## A kind of [rings], [wands], [potions] or [scrolls]: its value is base.
	var kind := false
	## The built-in formula; the file's (null: the file does not set it, or it
	## could not be read) and its line.
	var builtin: GuildFormula
	var formula: GuildFormula = null
	var line := 0
	## Values computed: k -> gold pieces (an amount: 0 -> the amount).
	var memo := {}
	## A failure of the file's formula was reported.
	var reported := false


# ---- making one -------------------------------------------------------------------

## The game's price list (see above).
static func read() -> GuildPrices:
	var places: Array[String] = []
	if not OS.has_feature("editor") and OS.has_feature("pc"):
		places.append(_exe_dir().path_join(FILE_NAME))
	places.append("user://" + FILE_NAME)
	var write_to: Array[String] = []
	if not OS.has_feature("editor"):
		write_to = places
	return read_from(places, write_to, "res://" + FILE_NAME)


## The first file of places that exists. When none does, the default list (the
## text of the file shipped, if it exists, else the built-in one) is written to the
## first of write_to that takes it, and read from there; when none takes it, the
## file shipped is read, or else the built-in list used.
static func read_from(places: Array[String], write_to: Array[String],
		shipped: String) -> GuildPrices:
	for p in places:
		if FileAccess.file_exists(p):
			return from_file(p)
	var have := shipped != "" and FileAccess.file_exists(shipped)
	var text: String = FileAccess.get_file_as_string(shipped) if have else C.PRICES
	for p in write_to:
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
			return from_text(text, p)
	return from_text(text, shipped) if have else defaults()


## The built-in list (GuildCatalog.PRICES), shared: no file, no errors.
static func defaults() -> GuildPrices:
	if _builtin == null:
		_builtin = GuildPrices.new()
		_builtin._build()
	return _builtin


## The list a file's text gives (file_path: the file, for `path` and the messages).
static func from_text(text: String, file_path := "") -> GuildPrices:
	var p := GuildPrices.new()
	var d := defaults()
	for section in d._entries:
		p._entries[section] = {}
		for nm in d._entries[section]:
			var b: Entry = d._entries[section][nm]
			var e := Entry.new()
			e.section = b.section
			e.name = b.name
			e.kind = b.kind
			e.builtin = b.builtin
			p._entries[section][nm] = e
	p.path = file_path
	if file_path != "":
		p._file = file_path.get_file()
	p._read(text)
	return p


## The list a file gives (one that can't be opened: the built-in list, and an error).
static func from_file(file_path: String) -> GuildPrices:
	var f := FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		var p := from_text("")
		p.errors.append("%s can't be opened (using the built-in prices)" % file_path)
		return p
	var text := f.get_as_text()
	f.close()
	return from_text(text, file_path)


## The folder of the game's executable (on macOS, the one holding the .app).
static func _exe_dir() -> String:
	var d := OS.get_executable_path().get_base_dir()
	if d.ends_with(".app/Contents/MacOS"):
		d = d.get_base_dir().get_base_dir().get_base_dir()
	return d


# ---- the values ---------------------------------------------------------------------

## What the next one of a line costs when k of it were bought already. A kind of
## [rings], [wands], [potions] or [scrolls] costs its section's price formula with
## base = the kind's own number; the name "price" gives that formula for base.
func price(section: String, name: String, k := 0, base := 0.0) -> int:
	var e := _entry(section, name)
	if e == null:
		return 0
	if LISTS.has(section) and name == "price":
		return _gold(_value(e, {"k": k, "base": base}), 0, PRICE_MAX)
	if not e.memo.has(k):
		var x := _value(e, {"k": k})
		if e.kind:
			x = _value(_entries[section]["price"], {"k": k, "base": x})
		e.memo[k] = _gold(x, 0, PRICE_MAX)
	return e.memo[k]


## An amount (AMOUNTS): a whole number in its range.
func amount(section: String, name: String) -> int:
	var e := _entry(section, name)
	if e == null or not _amount(section, name):
		return 0
	if not e.memo.has(0):
		var lim: Array = AMOUNTS[section][name]
		e.memo[0] = _gold(_value(e, {}), lim[0], lim[1])
	return e.memo[0]


## The Guild's coffers for a Hall of Fame: its best score, the sum of its scores,
## the number of its heroes.
func coffers(best: int, sum: int, n: int) -> int:
	var e := _entry("coffers", "coffers")
	return _gold(_value(e, {"best": best, "sum": sum, "n": n}), 0, PRICE_MAX)


## The formula of a line that gives its value for vars: the file's, or the
## built-in one where the file's fails (or the file does not set it).
func formula_of(section: String, name: String, vars: Dictionary) -> GuildFormula:
	var e := _entry(section, name)
	if e == null:
		return GuildFormula.parse("0", [])
	if e.formula != null:
		e.formula.evaluate(vars)
		if e.formula.last_error == "":
			return e.formula
	return e.builtin


## Every line of the list, as [section, name], in the built-in order.
func entry_names() -> Array:
	var out: Array = []
	for section in _entries:
		for nm in _entries[section]:
			out.append([section, nm])
	return out


## The line numbers of the file's lines in use: "section/name" -> line.
func lines_used() -> Dictionary:
	var out := {}
	for section in _entries:
		for nm in _entries[section]:
			if _entries[section][nm].formula != null:
				out[section + "/" + nm] = _entries[section][nm].line
	return out


## The file for the player: its full path ("" for the built-in list).
func where() -> String:
	if path.begins_with("user://") or (path.begins_with("res://") and OS.has_feature("editor")):
		return ProjectSettings.globalize_path(path)
	return path


func _entry(section: String, name: String) -> Entry:
	if _entries.has(section) and _entries[section].has(name):
		return _entries[section][name]
	var why := "the price list has no '%s' in [%s]" % [name, section]
	push_error("GuildPrices: " + why)
	errors.append(why)
	return null


## The value of a line for vars: its file formula's, else the built-in one's.
func _value(e: Entry, vars: Dictionary) -> float:
	if e.formula != null:
		var x := e.formula.evaluate(vars)
		if e.formula.last_error == "":
			return x
		if not e.reported:
			e.reported = true
			_error(e.line, "%s when %s" % [e.formula.last_error, _values_text(vars)], e)
	return e.builtin.evaluate(vars)


## x as a whole number from lo to hi (see _whole).
static func _gold(x: float, lo: int, hi: int) -> int:
	if is_nan(x) or x <= lo:
		return lo
	if x >= hi:
		return hi
	return clampi(int(_whole(x)), lo, hi)


## x rounded down, after adding a hair: a value that is whole on paper but lands a
## hair below it in floating point (0.29 * 100 = 28.999999999999996) is not one
## short. The hair, 10^-9 plus 10^-13 of x, is far below a gold piece.
static func _whole(x: float) -> float:
	return floorf(x + 1e-9 + absf(x) * 1e-13)


## "k = 3", "best = 0, sum = 0, n = 0"
static func _values_text(vars: Dictionary) -> String:
	var parts := PackedStringArray()
	for v in vars:
		parts.append("%s = %s" % [v, GuildFormula.number_text(vars[v])])
	return ", ".join(parts)


# ---- reading ------------------------------------------------------------------------

## The built-in entries, from GuildCatalog.PRICES (which must read without an error).
func _build() -> void:
	var section := ""
	var lines := C.PRICES.split("\n")
	for i in lines.size():
		var s := _strip(lines[i])
		if s == "":
			continue
		if s.begins_with("["):
			section = _norm(s.substr(1, s.length() - 2))
			_entries[section] = {}
			continue
		var eq := s.find("=")
		var e := Entry.new()
		e.section = section
		e.name = _norm(s.substr(0, eq))
		e.kind = _kinds(section).has(e.name)
		e.builtin = GuildFormula.parse(s.substr(eq + 1), _names_of(section, e.name))
		if e.builtin.error != "":
			push_error("GuildCatalog.PRICES line %d: %s" % [i + 1, e.builtin.error])
		_entries[section][e.name] = e


## Read a file's text into the entries.
func _read(text: String) -> void:
	_loading = true
	var section := ""	# "" before the first heading, "?" under one that can't be read
	var seen := {}		# "section/name" -> line
	var lines := text.split("\n")
	for i in lines.size():
		var n := i + 1
		var s := _strip(lines[i])
		if s == "":
			continue
		if s.begins_with("["):
			section = _heading(n, s)
			continue
		if section == "?":
			continue	# its heading was reported
		var eq := s.find("=")
		if eq < 0:
			_error(n, "expected 'name = value'")
			continue
		var nm := _norm(s.substr(0, eq))
		if section == "":
			_error(n, "%s comes before the first [section]" % GuildFormula.quoted(nm))
			continue
		if not _entries[section].has(nm):
			_error(n, _not_in(section, nm))
			continue
		var key: String = section + "/" + nm
		if seen.has(key):
			_error(n, "'%s' is set on line %d already (this line is not used)" % [nm, seen[key]])
			continue
		seen[key] = n
		var e: Entry = _entries[section][nm]
		var f := GuildFormula.parse(s.substr(eq + 1), _names_of(section, nm))
		if f.error != "":
			_error(n, f.error, e)
			continue
		e.formula = f
		e.line = n
	_try_all()
	_loading = false
	_pending.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for p in _pending:
		errors.append(p[1])
	_pending = []


## The section a heading names, or "?" (reported) if it can't be read.
func _heading(n: int, s: String) -> String:
	if not s.ends_with("]"):
		_error(n, "a heading is written [name]")
		return "?"
	var section := _norm(s.substr(1, s.length() - 2))
	if not _entries.has(section):
		_error(n, "unknown section [%s]" % GuildFormula.shortened(section))
		return "?"
	return section


## Why a name is not read in a section.
func _not_in(section: String, nm: String) -> String:
	var homes := PackedStringArray()
	for s in _entries:
		if _entries[s].has(nm):
			homes.append("[%s]" % s)
	if homes.is_empty():
		return "there is no %s in [%s]" % [GuildFormula.quoted(nm), section]
	return "there is no '%s' in [%s] (it is in %s)" % [nm, section, " and ".join(homes)]


## Try the file's formulas as the shop first uses them: a price at k = 0 (a kind's
## own number too), an amount for its range, then a list's price formula with each
## kind's number. One that fails is not used. The coffers are tried with the Hall
## of Fame they are for, when they are computed (_value).
func _try_all() -> void:
	for section in _entries:
		for nm in _entries[section]:
			var e: Entry = _entries[section][nm]
			if e.formula == null or section == "coffers" or (LISTS.has(section) and nm == "price"):
				continue
			if _amount(section, nm):
				_try(e, {}, AMOUNTS[section][nm])
			else:
				_try(e, {"k": 0}, [0, PRICE_MAX])
		if LISTS.has(section) and _entries[section]["price"].formula != null:
			var p: Entry = _entries[section]["price"]
			for nm in _entries[section]:
				var e: Entry = _entries[section][nm]
				if e.kind and not _try(p, {"k": 0, "base": _value(e, {"k": 0})}, [0, PRICE_MAX]):
					break


## Whether e's file formula gives, for vars, a whole number in lim ([lowest,
## highest]); if not, the formula is dropped and its line reported.
func _try(e: Entry, vars: Dictionary, lim: Array) -> bool:
	var x := e.formula.evaluate(vars)
	var why := e.formula.last_error
	var when := "" if vars.is_empty() else " when " + _values_text(vars)
	var got := GuildFormula.number_text(x)
	if why != "":
		why += when
	elif _amount(e.section, e.name) and (_whole(x) < lim[0] or _whole(x) > lim[1]):
		why = "%s must be from %d to %d (not %s)" % [e.name, lim[0], lim[1], got]
	elif _whole(x) < lim[0]:
		why = "a price can't be below 0 (here %s%s)" % [got, when]
	elif _whole(x) > lim[1]:
		why = "a price can't be over %d (here %s%s)" % [lim[1], got, when]
	if why == "":
		return true
	_error(e.line, why, e)
	e.formula = null
	return false


func _error(n: int, why: String, e: Entry = null) -> void:
	var s := "%s line %d: %s" % [_file, n, why]
	if e != null:
		s += " (using %s)" % e.builtin.text
	if _loading:
		_pending.append([n, s])
	else:
		errors.append(s)


## A line without its comment and the spaces around it.
static func _strip(raw: String) -> String:
	return raw.get_slice("#", 0).replace("\ufeff", "").strip_edges()


## A name as the list knows it: lower case, single spaces.
static func _norm(s: String) -> String:
	return " ".join(s.to_lower().replace("\t", " ").split(" ", false))


## The names a line's formula may use.
static func _names_of(section: String, name: String) -> Array:
	if section == "coffers":
		return ["best", "sum", "n"]
	if _amount(section, name):
		return []
	if LISTS.has(section) and name == "price":
		return ["k", "base"]
	return ["k"]


static func _amount(section: String, name: String) -> bool:
	return AMOUNTS.has(section) and AMOUNTS[section].has(name)


## The kinds of a list section, by the catalog's names.
static func _kinds(section: String) -> Array:
	var table: Array = []
	match section:
		"rings":
			table = C.RINGS
		"wands":
			table = C.STICKS
		"potions":
			table = C.POTIONS
		"scrolls":
			table = C.SCROLLS
	var out: Array = []
	for t in table:
		out.append(t[0])
	return out
