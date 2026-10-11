## The Fighters' Guild: the Quartermaster's screen (docs/GUILD.md).
##
## "The local guildmasters have sent you into the Dungeons of Doom ... you are
## allowed to keep all the loot you bring back." The Guild's coffers hold the loot
## of the heroes in the Hall of Fame; before each descent the Quartermaster outfits
## the new student from them.
##
## The screen is 80x24, drawn with its own Curses (never RogueBase's: no game is
## running) and shown on the game's TerminalView. ui/main.gd feeds it the keys
## (key()) until the student descends: it then emits `descended` with the shop's
## loadout. There is no other way out: no Escape, no cancel.
class_name GuildScreen
extends RefCounted

## The student descends with these purchases (see loadout.gd).
signal descended(loadout: Dictionary)

const LIST_TOP := 5
const LIST_ROWS := 16
const WIDTH := 79

## Screen modes.
const SHOP := 0
const HELP := 1
const CONFIRM := 2

var cs: Curses
var shop: GuildShop
var section := 0
var _mode := SHOP
var _cursor: Array[int] = []
var _top: Array[int] = []
## The message line: why the last key did nothing ("" if it did something).
var _say := ""


## A screen for the Hall of Fame in the score file at score_path.
func _init(score_path: String) -> void:
	shop = GuildShop.new(HallOfFame.read_file(score_path))
	cs = Curses.new()
	cs.leaveok(cs.stdscr, true)
	_cursor.resize(GuildShop.SECTIONS.size())
	_top.resize(GuildShop.SECTIONS.size())
	for s in GuildShop.SECTIONS.size():
		_cursor[s] = _start_line(shop.offers(s))
	draw()


# ---- keys ---------------------------------------------------------------------

## A key, as TerminalView.key_code() gives it.
func key(code: int) -> void:
	if _mode == HELP:
		_mode = SHOP
		draw()
		return
	if _mode == CONFIRM:
		if code == ord("y") or code == ord("Y"):
			descended.emit(shop.loadout())
			return
		_mode = SHOP
		draw()
		return
	_say = ""
	var lines := shop.offers(section)
	match code:
		ord("j"), Curses.KEY_DOWN, 14:	# ^N
			_move(lines, 1)
		ord("k"), Curses.KEY_UP, 16:	# ^P
			_move(lines, -1)
		Curses.KEY_NPAGE, ord(" "):
			for i in LIST_ROWS - 1:
				_move(lines, 1)
		Curses.KEY_PPAGE:
			for i in LIST_ROWS - 1:
				_move(lines, -1)
		Curses.KEY_HOME:
			_cursor[section] = _next_offer(lines, -1, 1)
		Curses.KEY_END:
			_cursor[section] = _next_offer(lines, lines.size(), -1)
		13, 10, ord("+"), ord("l"), ord("="):	# Enter: buy one more
			_act(lines, true)
		8, 127, Curses.KEY_BACKSPACE, ord("-"), ord("h"), ord("_"):	# Backspace: return one
			_act(lines, false)
		Curses.KEY_RIGHT, 9:	# Tab
			_open((section + 1) % GuildShop.SECTIONS.size())
		Curses.KEY_LEFT:
			_open((section + GuildShop.SECTIONS.size() - 1) % GuildShop.SECTIONS.size())
		ord("?"):
			_mode = HELP
		ord("e"), ord("E"):	# enter the dungeon (asks first)
			_mode = CONFIRM
		_:	# no Escape: the only way out is down
			if code >= ord("1") and code < ord("1") + GuildShop.SECTIONS.size():
				_open(code - ord("1"))
	draw()


func _open(s: int) -> void:
	section = s


func _move(lines: Array, d: int) -> void:
	var i := _next_offer(lines, _cursor[section], d)
	if i >= 0 and i < lines.size():
		_cursor[section] = i


## Buy (or return) one of the offer under the cursor.
func _act(lines: Array, buying: bool) -> void:
	var i := _cursor[section]
	if i < 0 or i >= lines.size() or not lines[i].has("id"):
		return
	var o: Dictionary = lines[i]
	var why := shop.buy(o.id) if buying else shop.refund(o.id)
	if why != GuildShop.DONE:
		_say = _refused(o, why)
	# lines come and go (enhancements of what was bought): stay on an offer
	lines = shop.offers(section)
	if _cursor[section] >= lines.size() or not lines[_cursor[section]].has("id"):
		_cursor[section] = _next_offer(lines, mini(_cursor[section], lines.size()), -1)


## The next selectable line from i in direction d (i itself excluded), or i.
func _next_offer(lines: Array, i: int, d: int) -> int:
	var j := i + d
	while j >= 0 and j < lines.size():
		if lines[j].has("id"):
			return j
		j += d
	return i if i >= 0 and i < lines.size() else _first_offer(lines)


func _first_offer(lines: Array) -> int:
	for j in lines.size():
		if lines[j].has("id"):
			return j
	return 0


## Where the cursor starts in a section: on the student's own weapon or armour
## (so a stray + does not swap it), else on the first offer.
func _start_line(lines: Array) -> int:
	for j in lines.size():
		if lines[j].get("mark", "") == "*":
			return j
	return _first_offer(lines)


# ---- messages ---------------------------------------------------------------

## Why a purchase or a return was refused, in Rogue's message style.
func _refused(o: Dictionary, why: String) -> String:
	match why:
		GuildShop.NO_GOLD:
			return "you can't afford that"
		GuildShop.NO_ROOM:
			return "there's no room in your pack"
		GuildShop.AT_MAX:
			return "you can't buy any more of that"
		GuildShop.FINAL:
			return "an identification can't be returned"
		GuildShop.NONE:
			return "you have none to return"
		GuildShop.ISSUED:
			return "you can't return your issued kit"
		GuildShop.ALREADY:
			return "that's yours already"
		GuildShop.ALL_KNOWN:
			return "every kind is known"
		GuildShop.IN_USE:
			return "your pack would be too full"
	return "that's not for sale"


# ---- drawing ------------------------------------------------------------------

func draw() -> void:
	var w := cs.stdscr
	cs.werase(w)
	if _mode == HELP:
		_draw_help()
	else:
		_draw_shop()
	cs.wrefresh(w)


func _draw_shop() -> void:
	_title("THE FIGHTERS' GUILD  -  QUARTERMASTER'S STORES")
	var h := shop.hall
	if h.heroes == 0:
		_put(1, 1, "Coffers 0 gold: the Hall of Fame is empty")
	else:
		_put(1, 1, "Coffers %d gold: %d of %d heroes in the Hall of Fame, best %d" % [shop.coffers,
			h.heroes, GuildCatalog.HALL_SIZE, h.best])
	_put(2, 1, "Spent %d   Left %d" % [shop.spent(), shop.left()])
	var pk := "Pack %d/%d" % [shop.pack_load(), shop.pack_size()]
	_put(2, WIDTH - 1 - pk.length(), pk)
	# the sections
	var x := 1
	for s in GuildShop.SECTIONS.size():
		var tab := "%d %s" % [s + 1, GuildShop.SECTIONS[s]]
		_put(3, x, tab, s == section)
		x += tab.length() + 2
	# the list
	var lines := shop.offers(section)
	var cur := _cursor[section]
	var top := _top[section]
	if cur < top:
		top = cur
		# show the heading or text just above the first offer
		while top > 0 and not lines[top - 1].has("id") and cur - (top - 1) < LIST_ROWS:
			top -= 1
	elif cur >= top + LIST_ROWS:
		top = cur - LIST_ROWS + 1
	top = clampi(top, 0, maxi(0, lines.size() - LIST_ROWS))
	if cur >= top + LIST_ROWS:
		top = cur - LIST_ROWS + 1
	_top[section] = top
	_rule(4, "more above" if top > 0 else "")
	for r in LIST_ROWS:
		var i := top + r
		if i >= lines.size():
			break
		_line(LIST_TOP + r, lines[i], i == cur)
	_rule(LIST_TOP + LIST_ROWS, "more below" if top + LIST_ROWS < lines.size() else "")
	_put(22, 1, "Enter buy  Backspace return  j/k choose  1-8 section  ? help  e enter dungeon")
	if _mode == CONFIRM:
		_put(23, 1, "Enter the Dungeons of Doom? (%d gold unspent) [y/n]" % shop.left())
	else:
		_put(23, 1, _say)


## One line of the list.
func _line(y: int, l: Dictionary, selected: bool) -> void:
	if l.has("head"):
		var t := "-- %s " % l.head
		_put(y, 3, t + "-".repeat(maxi(0, WIDTH - 4 - t.length())))
		return
	var price: String = l.status
	if price == "":
		price = "free" if l.price == 0 else str(l.price)
	var s := "%s %s %s%s%s%11s" % [">" if selected else " ", ("%-1s" % l.mark), _fit(l.label, 28),
		_fit(l.info, 22), _fit(l.note, 12), price]
	_put(y, 1, s, selected)


## Title bar: centered, in standout across the screen.
func _title(t: String) -> void:
	var pad := (WIDTH - t.length()) / 2
	_put(0, 0, " ".repeat(pad) + t + " ".repeat(WIDTH - pad - t.length()), true)


## A rule across the screen, with a note at its right end.
func _rule(y: int, note: String) -> void:
	var r := "-".repeat(WIDTH - 2)
	if note != "":
		r = r.substr(0, r.length() - note.length() - 4) + " " + note + " --"
	_put(y, 1, r)


func _draw_help() -> void:
	_title("THE FIGHTERS' GUILD  -  COFFERS AND KEYS")
	var h := shop.hall
	var rows: Array[String] = [
		"",
		"    coffers = best / 2  +  sum * (10 + n) / 400",
		"            = %d / 2  +  %d * (10 + %d) / 400  =  %d gold" % [h.best, h.total, h.heroes,
			shop.coffers],
		"",
		"  j k, up down    choose a line        1-8, left right   change section",
		"  Enter           buy one more         Backspace         return one",
		"  ?               this page            e                 enter the dungeon",
	]
	for i in rows.size():
		_put(1 + i, 1, rows[i])
	_put(23, WIDTH - 29, "--Press any key to continue--")


## Write s at (y, x), clipped to the screen (never the last cell: it would scroll).
func _put(y: int, x: int, s: String, standout := false) -> void:
	var w := cs.stdscr
	s = s.substr(0, maxi(0, WIDTH - x))
	if standout:
		cs.wstandout(w)
	cs.mvwaddstr(w, y, x, s)
	if standout:
		cs.wstandend(w)


## s cut or padded to width n (with at least one space after it).
static func _fit(s: String, n: int) -> String:
	if s.length() >= n:
		s = s.substr(0, n - 1)
	return s + " ".repeat(n - s.length())
