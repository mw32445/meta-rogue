class_name SpikeC
extends SpikeBase


static func c1() -> int:
	var k: int = await keys._next_key()
	note("c1 key %d, a2=%d" % [k, SpikeA.a2()])
	return k
