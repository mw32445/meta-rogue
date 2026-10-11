## Phase 0 spike: base class with constants, static vars and static helpers.
class_name SpikeBase
extends RefCounted

const K := 5
static var counter := 0
static var keys: Curses
static var log_lines: PackedStringArray = PackedStringArray()


static func helper(x: int) -> int:
	return x + K


static func note(s: String) -> void:
	log_lines.append(s)
