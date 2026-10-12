## list.c: Functions for dealing with linked lists of goodies
##
## @(#)list.c	4.12 (Berkeley) 02/05/99
##
## C passes the address of the list head (THING **). GDScript cannot, so the
## list functions return the new head:
##   attach(mlist, tp)   ->  mlist = List._attach(mlist, tp)
##   detach(pack, obj)   ->  pack = List._detach(pack, obj)
##   free_list(lvl_obj)  ->  lvl_obj = List._free_list(lvl_obj)
class_name List
extends RogueBase


## _detach:
##	takes an item out of whatever linked list it might be in
static func _detach(list: Thing, item: Thing) -> Thing:
	if list == item:
		list = item.l_next
	if item.l_prev != null:
		item.l_prev.l_next = item.l_next
	if item.l_next != null:
		item.l_next.l_prev = item.l_prev
	item.l_next = null
	item.l_prev = null
	return list


## _attach:
##	add an item to the head of a list
static func _attach(list: Thing, item: Thing) -> Thing:
	# Attaching an item that is already on the list makes it circular (the
	# add_pack() empty-pack bug) and the original hangs at the next walk of
	# it. The attach is skipped and the game ends at the next key read, as in
	# the oracle (docs/FIDELITY.md).
	var t := list
	var n := 0
	while t != null and n < 100000:
		if t == item:
			cs.doomed = "\nrogue: an object list became circular (a bug in Rogue 5.4.4); the game cannot continue.\n"
			return list
		t = t.l_next
		n += 1
	if list != null:
		item.l_next = list
		list.l_prev = item
		item.l_prev = null
	else:
		item.l_next = null
		item.l_prev = null
	return item


## _free_list:
##	Throw the whole blamed thing away
static func _free_list(ptr: Thing) -> Thing:
	var item: Thing
	while ptr != null:
		item = ptr
		ptr = item.l_next
		discard(item)
	return ptr


## discard:
##	Free up an item. free() is a no-op (docs/FIDELITY.md): a discarded
##	object stays intact for any stale pointer that still reads it.
static func discard(_item: Thing) -> void:
	if MASTER:
		total -= 1


## new_item
##	Get a new item with a specified size (zero-filled, like calloc).
##	MASTER's "ran out of memory" message cannot happen in GDScript.
static func new_item() -> Thing:
	var item := Thing.new()
	if MASTER:
		total += 1
	item.l_next = null
	item.l_prev = null
	return item
