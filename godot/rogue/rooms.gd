## rooms.c: Create the layout for the new level
##
## @(#)rooms.c	4.45 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## File statics: Maxy, Maxx, Starty, Startx are RogueBase._rooms_*; the
## function statics are _do_rooms_top, _do_maze_pos and _dig_pos.
## typedef struct spot { int nexits; coord exits[4]; int used; } SPOT and the
## file static SPOT maze[NUMLINES/3+1][NUMCOLS/3+1] (position matrix for maze
## positions) are write-only in the C, so the port keeps no maze table: see
## accnt_maze().
class_name Rooms
extends RogueBase

const GOLDGRP := 1

## static coord del[4] = { {2, 0}, {-2, 0}, {0, 2}, {0, -2} } in dig(), as
## {x, y} pairs (coord is { int x; int y; })
const _dig_del: Array = [[2, 0], [-2, 0], [0, 2], [0, -2]]


## do_rooms:
##	Create rooms and corridors with a connectivity graph
static func do_rooms() -> void:
	var rm: int
	var tp: Thing
	var left_out: int
	var top := _do_rooms_top	# static coord top
	var bsze := Coord.new()		# maximum room size
	var mp := Coord.new()

	bsze.x = NUMCOLS / 3
	bsze.y = NUMLINES / 3
	# Clear things for a new level
	for rp in rooms:
		rp.r_goldval = 0
		rp.r_nexits = 0
		rp.r_flags = 0
	# Put the gone rooms, if any, on the level
	left_out = rnd(4)
	for i in left_out:
		rm = NewLevel.rnd_room()
		rooms[rm].r_flags |= ISGONE
	# dig and populate all the rooms on the level
	for i in MAXROOMS:
		var rp: Room = rooms[i]
		# Find upper left corner of box that this room goes in
		top.x = (i % 3) * bsze.x + 1
		top.y = (i / 3) * bsze.y
		if (rp.r_flags & ISGONE) != 0:
			# Place a gone room.  Make certain that there is a blank line
			# for passage drawing.
			while true:
				rp.r_pos.x = top.x + rnd(bsze.x - 2) + 1
				rp.r_pos.y = top.y + rnd(bsze.y - 2) + 1
				rp.r_max.x = -NUMCOLS
				rp.r_max.y = -NUMLINES
				if rp.r_pos.y > 0 and rp.r_pos.y < NUMLINES - 1:
					break
			continue
		# set room type
		if rnd(10) < level - 1:
			rp.r_flags |= ISDARK		# dark room
			if rnd(15) == 0:
				rp.r_flags = ISMAZE		# maze room
		# Find a place and size for a random room
		if (rp.r_flags & ISMAZE) != 0:
			rp.r_max.x = bsze.x - 1
			rp.r_max.y = bsze.y - 1
			rp.r_pos.x = top.x
			if rp.r_pos.x == 1:
				rp.r_pos.x = 0
			rp.r_pos.y = top.y
			if rp.r_pos.y == 0:
				rp.r_pos.y += 1
				rp.r_max.y -= 1
		else:
			while true:
				rp.r_max.x = rnd(bsze.x - 4) + 4
				rp.r_max.y = rnd(bsze.y - 4) + 4
				rp.r_pos.x = top.x + rnd(bsze.x - rp.r_max.x)
				rp.r_pos.y = top.y + rnd(bsze.y - rp.r_max.y)
				if rp.r_pos.y != 0:
					break
		draw_room(rp)
		# Put the gold in
		if rnd(2) == 0 and (not amulet or level >= max_level):
			var gold: Thing

			gold = List.new_item()
			rp.r_goldval = GOLDCALC()
			gold.o_goldval = rp.r_goldval
			find_floor(rp, rp.r_gold, 0, false)
			gold.o_pos.copy_from(rp.r_gold)
			INDEX(rp.r_gold.y, rp.r_gold.x).p_ch = GOLD
			gold.o_flags = ISMANY
			gold.o_group = GOLDGRP
			gold.o_type = GOLD
			lvl_obj = List._attach(lvl_obj, gold)
		# Put the monster in
		if rnd(100) < (80 if rp.r_goldval > 0 else 25):
			tp = List.new_item()
			find_floor(rp, mp, 0, true)
			Monsters.new_monster(tp, Monsters.randmonster(false), mp)
			Monsters.give_pack(tp)


## draw_room:
##	Draw a box around a room and lay down the floor for normal
##	rooms; for maze rooms, draw maze.
static func draw_room(rp: Room) -> void:
	if (rp.r_flags & ISMAZE) != 0:
		do_maze(rp)
	else:
		vert(rp, rp.r_pos.x)				# Draw left side
		vert(rp, rp.r_pos.x + rp.r_max.x - 1)	# Draw right side
		horiz(rp, rp.r_pos.y)				# Draw top
		horiz(rp, rp.r_pos.y + rp.r_max.y - 1)	# Draw bottom

		# Put the floor down
		for y in range(rp.r_pos.y + 1, rp.r_pos.y + rp.r_max.y - 1):
			for x in range(rp.r_pos.x + 1, rp.r_pos.x + rp.r_max.x - 1):
				INDEX(y, x).p_ch = FLOOR


## vert:
##	Draw a vertical line
static func vert(rp: Room, startx: int) -> void:
	# for (y = rp->r_pos.y + 1; y <= rp->r_max.y + rp->r_pos.y - 1; y++)
	for y in range(rp.r_pos.y + 1, rp.r_max.y + rp.r_pos.y):
		INDEX(y, startx).p_ch = ord("|")


## horiz:
##	Draw a horizontal line
static func horiz(rp: Room, starty: int) -> void:
	# for (x = rp->r_pos.x; x <= rp->r_pos.x + rp->r_max.x - 1; x++)
	for x in range(rp.r_pos.x, rp.r_pos.x + rp.r_max.x):
		INDEX(starty, x).p_ch = ord("-")


## do_maze:
##	Dig a maze
static func do_maze(rp: Room) -> void:
	var starty: int
	var startx: int
	var pos := _do_maze_pos	# static coord pos

	# C: for (sp = &maze[0][0]; sp <= &maze[NUMLINES / 3][NUMCOLS / 3]; sp++)
	#        { sp->used = FALSE; sp->nexits = 0; }
	# maze[][] is write-only (see accnt_maze), so the port keeps no table.

	_rooms_Maxy = rp.r_max.y
	_rooms_Maxx = rp.r_max.x
	_rooms_Starty = rp.r_pos.y
	_rooms_Startx = rp.r_pos.x
	starty = (rnd(rp.r_max.y) / 2) * 2
	startx = (rnd(rp.r_max.x) / 2) * 2
	pos.y = starty + _rooms_Starty
	pos.x = startx + _rooms_Startx
	Passages.putpass(pos)
	dig(starty, startx)


## dig:
##	Dig out from around where we are now, if possible
static func dig(y: int, x: int) -> void:
	var cnt: int
	var newy: int
	var newx: int
	var nexty := 0
	var nextx := 0
	var pos := _dig_pos	# static coord pos

	while true:
		cnt = 0
		for cp: Array in _dig_del:	# for (cp = del; cp <= &del[3]; cp++)
			newy = y + cp[1]
			newx = x + cp[0]
			if newy < 0 or newy > _rooms_Maxy or newx < 0 or newx > _rooms_Maxx:
				continue
			if (flat(newy + _rooms_Starty, newx + _rooms_Startx) & F_PASS) != 0:
				continue
			cnt += 1
			if rnd(cnt) == 0:
				nexty = newy
				nextx = newx
		if cnt == 0:
			return
		accnt_maze(y, x, nexty, nextx)
		accnt_maze(nexty, nextx, y, x)
		if nexty == y:
			pos.y = y + _rooms_Starty
			if nextx - x < 0:
				pos.x = nextx + _rooms_Startx + 1
			else:
				pos.x = nextx + _rooms_Startx - 1
		else:
			pos.x = x + _rooms_Startx
			if nexty - y < 0:
				pos.y = nexty + _rooms_Starty + 1
			else:
				pos.y = nexty + _rooms_Starty - 1
		Passages.putpass(pos)
		pos.y = nexty + _rooms_Starty
		pos.x = nextx + _rooms_Startx
		Passages.putpass(pos)
		dig(nexty, nextx)


## accnt_maze:
##	Account for maze exits
##
## C:	sp = &maze[y][x];
##	for (cp = sp->exits; cp < &sp->exits[sp->nexits]; cp++)
##	    if (cp->y == ny && cp->x == nx)
##		return;
##	cp->y = ny;
##	cp->x = nx;
## do_maze() zeroes every nexits and nothing ever increments it, so the loop
## never runs and the store always goes to exits[0], which nothing ever reads
## (y <= Maxy <= 7 and x <= Maxx <= 25 stay inside maze[9][27]). maze[][] is
## write-only: it has no effect on the map, the screen or the RNG, so the
## port keeps no table and this function does nothing.
static func accnt_maze(y: int, x: int, ny: int, nx: int) -> void:
	pass


## rnd_pos:
##	Pick a random spot in a room
static func rnd_pos(rp: Room, cp: Coord) -> void:
	cp.x = rp.r_pos.x + rnd(rp.r_max.x - 2) + 1
	cp.y = rp.r_pos.y + rnd(rp.r_max.y - 2) + 1


## find_floor:
##	Find a valid floor spot in this room.  If rp is NULL, then
##	pick a new room each time around the loop.
##	(*cp holds the last square tried, also when it fails.)
static func find_floor(rp: Room, cp: Coord, limit: int, monst: bool) -> bool:
	var pp: Place
	var cnt: int
	var compchar := 0
	var pickroom: bool

	pickroom = (rp == null)

	if not pickroom:
		compchar = PASSAGE if (rp.r_flags & ISMAZE) != 0 else FLOOR
	cnt = limit
	while true:
		# if (limit && cnt-- == 0)
		if limit != 0:
			if cnt == 0:
				return false
			cnt -= 1
		if pickroom:
			var rm: int = NewLevel.rnd_room()
			rp = rooms[rm]
			compchar = PASSAGE if (rp.r_flags & ISMAZE) != 0 else FLOOR
		rnd_pos(rp, cp)
		pp = INDEX(cp.y, cp.x)
		if monst:
			if pp.p_monst == null and Io.step_ok(pp.p_ch):
				return true
		elif pp.p_ch == compchar:
			return true
	return false	# not reached: the C loop is for (;;)


## enter_room:
##	Code that is executed whenver you appear in a room
static func enter_room(cp: Coord) -> void:
	var rp: Room
	var tp: Thing
	var y: int
	var x: int
	var ch: int

	proom = Chase.roomin(cp)	# rp = proom = roomin(cp);
	rp = proom
	await Move.door_open(rp)
	if (rp.r_flags & ISDARK) == 0 and not on(player, ISBLIND):
		y = rp.r_pos.y
		while y < rp.r_max.y + rp.r_pos.y:
			move(y, rp.r_pos.x)
			x = rp.r_pos.x
			while x < rp.r_max.x + rp.r_pos.x:
				tp = moat(y, x)
				ch = chat(y, x)
				if tp == null:
					if CCHAR(inch()) != ch:
						addch(ch)
					else:
						move(y, x + 1)
				else:
					tp.t_oldch = ch
					if not Chase.see_monst(tp):
						if on(player, SEEMONST):
							standout()
							addch(tp.t_disguise)
							standend()
						else:
							addch(ch)
					else:
						addch(tp.t_disguise)
				x += 1
			y += 1


## leave_room:
##	Code for when we exit a room
static func leave_room(cp: Coord) -> void:
	var pp: Place
	var rp: Room
	var y: int
	var x: int
	var floor_: int	# char floor
	var ch: int

	rp = proom

	if (rp.r_flags & ISMAZE) != 0:
		return

	if (rp.r_flags & ISGONE) != 0:
		floor_ = PASSAGE
	elif (rp.r_flags & ISDARK) == 0 or on(player, ISBLIND):
		floor_ = FLOOR
	else:
		floor_ = ord(" ")

	proom = passages[flat(cp.y, cp.x) & F_PNUM]
	y = rp.r_pos.y
	while y < rp.r_max.y + rp.r_pos.y:
		x = rp.r_pos.x
		while x < rp.r_max.x + rp.r_pos.x:
			move(y, x)
			ch = CCHAR(inch())
			match ch:
				FLOOR:
					if floor_ == ord(" ") and ch != ord(" "):
						addch(ord(" "))
				_:
					# to check for monster, we have to strip out
					# standout bit
					if isupper(ch & 0x7F):	# isupper(toascii(ch))
						if on(player, SEEMONST):
							standout()
							addch(ch)
							standend()
						else:	# (C: break out of the switch above)
							pp = INDEX(y, x)
							addch(DOOR if pp.p_ch == DOOR else floor_)
			x += 1
		y += 1
	await Move.door_open(rp)
