extends SceneTree

class Holder:
	var v := 3

static var player_h := Holder.new()
static var hero: Holder:
	get: return player_h
	set(value): player_h = value
static var seed_ := 0
static var count := 0
static var level := 1

static func rnd(rng: int) -> int:
	seed_ = (seed_ * 11109 + 13849) & 0xFFFFFFFF
	return 0 if rng == 0 else ((seed_ >> 16) & 0xFFFF) % absi(rng)

func _init() -> void:
	hero.v = 7
	print("hero.v=", player_h.v)
	hero = Holder.new()
	print("rebound=", player_h.v)
	seed_ = 12345
	print("rnd=", rnd(10), " seed=", seed_)
	var str_ := "x"
	print("maxi=", maxi(3, 9))
	quit(0)
