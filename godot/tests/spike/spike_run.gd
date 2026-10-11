## Phase 0 spike runner: godot --headless --path godot --script res://tests/spike/spike_run.gd
extends SceneTree

var results: Array[String] = []


func check(name: String, ok: bool, detail := "") -> void:
	results.append("%s %s %s" % ["PASS" if ok else "FAIL", name, detail])


func _init() -> void:
	_main()


func _main() -> void:
	# 1. static coroutines across a 3-file cycle, inherited static vars/consts, replay driver
	var c := Curses.new()
	c.replay = true
	c.script_keys = PackedInt32Array([42, 43])
	SpikeBase.keys = c
	var done := [false, 0]
	var run := func():
		done[1] = await SpikeA.a1()
		done[0] = true
	run.call()
	check("coroutine suspends at key read", not done[0])
	c.feed()
	check("coroutine resumes and returns through 3 static coroutines", done[0] and done[1] == 42 * 2 + 5, str(done[1]))
	check("inherited static var shared", SpikeBase.counter == 1 and SpikeA.counter == 1)
	check("cross-file call inside coroutine", SpikeBase.log_lines.has("c1 key 42, a2=6"), str(SpikeBase.log_lines))

	# 2. await through Callable.call() on a static coroutine
	var cb := Callable(SpikeB, "b1")
	var done2 := [false, 0]
	var run2 := func():
		done2[1] = await cb.call()
		done2[0] = true
	run2.call()
	c.feed()
	check("await Callable(Class, static coroutine).call()", done2[0] and done2[1] == 86, str(done2))

	# 3. await inside and/or short-circuits
	var calls := [0]
	var f := func() -> bool:
		calls[0] += 1
		return true
	var t := false
	if t and await f.call():
		pass
	check("await in 'and' short-circuits", calls[0] == 0)
	t = true
	if t or await f.call():
		pass
	check("await in 'or' short-circuits", calls[0] == 0)

	# 4. abandoning a coroutine: drop the emitter, nothing resumes
	var c2 := Curses.new()
	c2.replay = true
	SpikeBase.keys = c2
	var resumed := [false]
	var run3 := func():
		await SpikeC.c1()
		resumed[0] = true
	run3.call()
	SpikeBase.keys = null
	c2 = null
	check("abandoned coroutine does not resume", not resumed[0])

	# 5. match with ord() / constants
	var ch := ord("h")
	var m := ""
	match ch:
		ord("j"): m = "j"
		ord("h"): m = "h"
		_: m = "other"
	check("match with ord() patterns", m == "h", m)

	# 6. integer semantics
	check("int division truncates toward zero", -7 / 2 == -3)
	check("int modulo has the sign of the dividend", -7 % 2 == -1)
	var neg := -8
	var shifted: int = neg >> 1
	check(">> on a negative variable at runtime", shifted == -4, str(shifted))
	var negx := -1
	var lsh: int = negx << 5
	check("<< on a negative variable at runtime", lsh == -32, str(lsh))
	var s := 0xFFFFFFFF
	s = (s * 11109 + 13849) & 0xFFFFFFFF
	check("32-bit LCG step", s == ((4294967295 * 11109 + 13849) % 4294967296), str(s))
	check("int is 64-bit", (1 << 62) > 0)

	# 7. throughput
	var t0 := Time.get_ticks_usec()
	var acc := 0
	for i in 1000000:
		acc += SpikeBase.helper(i)
	var t1 := Time.get_ticks_usec()
	check("1e6 static calls", true, "%.0f ms" % ((t1 - t0) / 1000.0))
	t0 = Time.get_ticks_usec()
	for i in 100000:
		acc += await SpikeA.a2_coro()
	t1 = Time.get_ticks_usec()
	check("1e5 awaited non-suspending coroutine calls", true, "%.0f ms" % ((t1 - t0) / 1000.0))

	for r in results:
		print(r)
	var failed := results.filter(func(r): return r.begins_with("FAIL")).size()
	print("spike: %d checks, %d failed" % [results.size(), failed])
	quit(1 if failed else 0)
