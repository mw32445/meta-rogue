## The Fighters' Guild: the Hall of Fame, read for the Guild's coffers
## (docs/GUILD.md).
##
## The score file has C's layout: entries of an encrypted 1024-byte name and a
## 100-byte score line (Save.wr_score). This reader uses only the pure helpers
## Save.encread and Save._scan_scoreline: it touches no game state and not the
## game's open `scoreboard`, so it can run before RogueBase.reset() and between
## games. It reads as many entries as the file holds, at most 20, so an older
## 10-entry file yields 10 entries.
##
## The coffers: the formula of the price list ([coffers] in guild_prices.txt;
## built in: best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20)), where best is the
## best score, n the number of entries with a score above 0, and sum their total.
class_name HallOfFame
extends RefCounted

const ENTRY_SIZE := RogueBase.MAXSTR + 100

## The entries read (Rip.Score), in file order.
var entries: Array = []
## Entries with a score above 0, their best score and their total.
var heroes := 0
var best := 0
var total := 0
## FNV-1a hash of the file's bytes (the seed of the Guild's random draws).
var digest := 0


## Read the score file at path (no file: an empty Hall of Fame).
static func read_file(path: String) -> HallOfFame:
	var h := HallOfFame.new()
	var bytes := PackedByteArray()
	if path != "" and FileAccess.file_exists(path):
		bytes = FileAccess.get_file_as_bytes(path)
	h.digest = fnv(bytes)
	var n := mini(GuildCatalog.HALL_SIZE, bytes.size() / ENTRY_SIZE)
	if n > 0:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			for i in n:
				var sc := Rip.Score.new()
				sc.sc_name = Save._cstr(Save.encread(PackedByteArray(), RogueBase.MAXSTR, f))
				var line := Save.encread(PackedByteArray(), 100, f)
				Save._scan_scoreline(Save._cstr(line), sc)
				h.entries.append(sc)
			f.close()
	for sc in h.entries:
		if sc.sc_score > 0:
			h.heroes += 1
			h.total += sc.sc_score
			h.best = maxi(h.best, sc.sc_score)
	return h


## The Guild's coffers, by a price list (none: the built-in one).
func coffers(prices: GuildPrices = null) -> int:
	if prices == null:
		prices = GuildPrices.defaults()
	return prices.coffers(best, total, heroes)


## FNV-1a (32 bits) of some bytes, continued from h.
static func fnv(bytes: PackedByteArray, h: int = 2166136261) -> int:
	for b in bytes:
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h
