## struct monster (rogue.h): the monster table entry.
class_name Monster
extends RefCounted

var m_name := ""
var m_carry := 0
var m_flags := 0	## short
var m_stats := Stats.new()


func _init(name := "", carry := 0, flags := 0, stats: Stats = null) -> void:
	m_name = name
	m_carry = carry
	m_flags = flags
	if stats != null:
		m_stats = stats


func copy_from(o: Monster) -> void:
	m_name = o.m_name
	m_carry = o.m_carry
	m_flags = o.m_flags
	m_stats.copy_from(o.m_stats)


func dup() -> Monster:
	var r := Monster.new()
	r.copy_from(self)
	return r
