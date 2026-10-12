class_name SpikeB
extends SpikeBase


static func b1() -> int:
	var x: int = await SpikeC.c1()
	return x * 2


static func not_coroutine() -> int:
	return 7
