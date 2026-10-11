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

## What the Quartermaster says when a section opens.
const GREETING: Array[String] = [
	"Strength is bought with sweat, student. Here it is bought with gold.",
	"Steel is honest. Choose what your arm can swing.",
	"Ring mail is what we issue. Better costs better.",
	"Rings, every one of them known. Two of a kind cost dearly.",
	"Wands and staves. Point them away from me, if you please.",
	"The alchemist names one bottle at a time. A name stays given.",
	"The scribe reads one scroll at a time. What is read stays read.",
	"Food, missiles and packs. Starving heroes don't come back.",
]

var cs: Curses
var shop: GuildShop
var section := 0
var _mode := SHOP
var _cursor: Array[int] = []
var _top: Array[int] = []
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
	if shop.coffers == 0:
		_say = "Welcome, student. The coffers are empty: free exchanges only."
	else:
		_say = "Welcome, student. The coffers hold %d gold for you. Spend it well." % shop.coffers
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
		_say = "Take your time. The dungeon isn't going anywhere."
		draw()
		return
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
		ord("+"), ord("l"), ord("="):
			_act(lines, true)
		ord("-"), ord("h"), ord("_"):
			_act(lines, false)
		Curses.KEY_RIGHT, 9:	# Tab
			_open((section + 1) % GuildShop.SECTIONS.size())
		Curses.KEY_LEFT:
			_open((section + GuildShop.SECTIONS.size() - 1) % GuildShop.SECTIONS.size())
		ord("?"):
			_mode = HELP
		ord(">"), 13, 10:
			_mode = CONFIRM
		27:
			_say = "There's no backing out, student. Descend when you're ready."
		_:
			if code >= ord("1") and code < ord("1") + GuildShop.SECTIONS.size():
				_open(code - ord("1"))
	draw()


func _open(s: int) -> void:
	if s != section:
		section = s
		_say = GREETING[s]


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
	if why == GuildShop.DONE:
		_say = _bought(o) if buying else _returned(o)
	else:
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


# ---- what the Quartermaster says ------------------------------------------------

func _bought(o: Dictionary) -> String:
	var kind: String = o.id.get_slice(":", 0)
	var label: String = o.label
	var lo := label.to_lower()
	match kind:
		"str":
			return "Push-ups at dawn, then. Strength %d." % shop.strength_now()
		"hp":
			return "Scars make the hero. %d hit points." % shop.hp_now()
		"sw":
			return "A %s, +1,+1, for your own hand. Mind the edge." % lo
		"xw":
			return "A spare %s, +0,+0. Keep it oiled." % lo
		"ew":
			return "The smith's hammer rings: %s now." % _after(shop.offers(section), o.id)
		"sa":
			return "%s, +1. It suits you." % label
		"xa":
			return "A spare suit of %s, +0." % lo
		"ea":
			return "The armourer tightens every strap: %s now." % _after(shop.offers(section), o.id)
		"rg":
			if o.note == "cursed":
				return "A ring of %s. Cursed, as they all are: you asked for it." % lo
			return "A ring of %s, known for what it is." % lo
		"er":
			return "The enchanter whispers to the ring: %s now." % _after(shop.offers(section), o.id)
		"pr":
			return "Polished until it shines: worth %s times as much to a winner." \
				% _after(shop.offers(section), o.id).trim_prefix("x")
		"wd":
			return "A wand or staff of %s, charged. Point it away from me." % lo
		"ec":
			return "Recharged: %s." % _after(shop.offers(section), o.id)
		"ip":
			return "The alchemist sniffs it: %s. For sale now." \
				% GuildCatalog.POTIONS[shop.last_named][0]
		"is":
			return "The scribe reads it: %s. For sale now." \
				% GuildCatalog.SCROLLS[shop.last_named][0]
		"bp":
			return "A potion of %s, corked and packed." % lo
		"bs":
			return "A scroll of %s, rolled and packed." % lo
		"fd":
			return "A ration, wrapped in oilcloth. Don't eat it all at once."
		"ms":
			return "%s, packed." % label
		"pk":
			return "A bigger pack: %d slots." % shop.pack_size()
	return "Written in the ledger."


func _returned(o: Dictionary) -> String:
	var kind: String = o.id.get_slice(":", 0)
	match kind:
		"sw":
			return "Back to the mace, then. The Guild pays you back."
		"sa":
			return "Back to ring mail, then. The Guild pays you back."
	return "Back on the shelf. The Guild pays back every copper."


func _refused(o: Dictionary, why: String) -> String:
	var kind: String = o.id.get_slice(":", 0)
	match why:
		GuildShop.NO_GOLD:
			return "The coffers won't stretch that far, student."
		GuildShop.NO_ROOM:
			return "Your pack is full. The Stores sell bigger ones."
		GuildShop.AT_MAX:
			match kind:
				"str":
					return "Thirty-one is as strong as a body gets."
				"pr":
					return "It can't shine any brighter than that."
				"pk":
					return "The packmaker has nothing bigger."
			return "That is as far as it goes."
		GuildShop.FINAL:
			return "A name once given is not taken back."
		GuildShop.NONE:
			return "You have nothing of the kind to return."
		GuildShop.ISSUED:
			return "That's what the Guild issues. It stays with you."
		GuildShop.ALREADY:
			return "That's yours already."
		GuildShop.ALL_KNOWN:
			return "Every kind has its name already. Nothing left to name."
		GuildShop.IN_USE:
			return "Your purchases fill that slot. Return something first."
	return "That's not for sale."


## The new state of an offer, after a purchase ("+1,+2", "40", "7 charges").
func _after(lines: Array, id: String) -> String:
	for l in lines:
		if l.has("id") and l.id == id:
			var info: String = l.info
			var arrow := info.find("-> ")
			return info.substr(arrow + 3) if arrow >= 0 else info
	return "done"


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
		_put(1, 1, "Coffers 0 gold: the Hall of Fame is empty. Free exchanges only.")
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
	_put(22, 1, "j/k choose  +/- buy/return  1-8 section  ? help  > descend")
	if _mode == CONFIRM:
		_put(23, 1, "Descend into the Dungeons of Doom? (%d gold unspent) [y/n]" % shop.left())
	else:
		_put(23, 1, "\"%s\"" % _say)


## One line of the list.
func _line(y: int, l: Dictionary, selected: bool) -> void:
	if l.has("head"):
		var t := "-- %s " % l.head
		_put(y, 3, t + "-".repeat(maxi(0, WIDTH - 4 - t.length())))
		return
	if l.has("text"):
		_put(y, 5, l.text)
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
	_title("THE FIGHTERS' GUILD  -  THE QUARTERMASTER'S RULES")
	var h := shop.hall
	var rows: Array[String] = [
		"",
		"Before each descent the Guild outfits its new student from its coffers,",
		"which hold the loot of the heroes in the Hall of Fame:",
		"",
		"    coffers = best / 2  +  sum * (10 + n) / 400",
		"            = %d / 2  +  %d * (10 + %d) / 400  =  %d gold" % [h.best, h.total, h.heroes,
			shop.coffers],
		"",
		"best is the Hall's highest score and sum the total of its n scores (at most",
		"20). Every death, quit or win that enters the Hall adds to them. Gold left",
		"unspent is not kept: the next student gets the coffers afresh.",
		"",
		"Anything bought can be returned for its full price until you descend, except",
		"an identification: the alchemist or the scribe names one random unknown kind",
		"(the common ones more often), and a name is final. The kinds they name stay",
		"the same until the Hall of Fame changes.",
		"",
		"  j k, up down    choose a line        1-8, left right   change section",
		"  + l             buy one              - h               return one",
		"  ?               this page            > Enter           descend",
		"",
		"There is no way out of the Guild but down.",
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
