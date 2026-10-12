class_name SpikeA
extends SpikeBase


static func a1() -> int:
	counter += 1
	var v: int = await SpikeB.b1()
	note("a1 got %d" % v)
	return v + K


static func a2() -> int:
	return helper(counter)


## A coroutine that never suspends (await on a coroutine that returns immediately).
static func a2_coro() -> int:
	if counter < 0:
		await keys._next_key()
	return counter
