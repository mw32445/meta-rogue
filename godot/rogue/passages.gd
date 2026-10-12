## passages.c: Draw the connecting passages
##
## @(#)passages.c	4.22 (Berkeley) 02/05/99
##
## Rogue: Exploring the Dungeons of Doom
## Copyright (C) 1980-1983, 1985, 1999 Michael Toy, Ken Arnold and Glenn Wichman
## All rights reserved.
##
## See the file LICENSE.TXT for full copyright and licensing information.
##
## File statics pnum/newpnum are RogueBase._passages_pnum/_passages_newpnum;
## conn()'s static coords are RogueBase._conn_*.
class_name Passages
extends RogueBase

## conn()'s door-picking loops spin forever in Rogue 5.4.4 when a maze room has
## no passage square on the side the door must go (docs/FIDELITY.md). After
## this many tries the game ends instead; the oracle does the same.
const STUCK_TRIES := 10000


## struct rdes (the room graph description of do_passages())
class Rdes:
	extends RefCounted
	var conn: Array[bool] = []	## possible to connect to room i?
	var isconn: Array[bool] = []	## connection been made to room i?
	var ingraph := false		## this room in graph already?


## The initializer of do_passages()' static struct rdes rdes[MAXROOMS]: the
## conn[] rows (never modified). The isconn[] and ingraph fields start as 0
## and are re-initialized at the top of every do_passages() call before
## anything reads them, so a fresh local table per call behaves the same.
const _rdes_conn: Array = [
	[0, 1, 0, 1, 0, 0, 0, 0, 0],
	[1, 0, 1, 0, 1, 0, 0, 0, 0],
	[0, 1, 0, 0, 0, 1, 0, 0, 0],
	[1, 0, 0, 0, 1, 0, 1, 0, 0],
	[0, 1, 0, 1, 0, 1, 0, 1, 0],
	[0, 0, 1, 0, 1, 0, 0, 0, 1],
	[0, 0, 0, 1, 0, 0, 0, 1, 0],
	[0, 0, 0, 0, 1, 0, 1, 0, 1],
	[0, 0, 0, 0, 0, 1, 0, 1, 0],
]


## do_passages:
##	Draw all the passages on a level.
static func do_passages() -> void:
	var r1: Rdes
	var r2: Rdes = null
	var i: int
	var j: int
	var roomcount: int
	var rdes: Array[Rdes] = []

	for k in MAXROOMS:
		var r := Rdes.new()
		for c: int in _rdes_conn[k]:
			r.conn.append(c != 0)
			r.isconn.append(false)
		r.ingraph = false
		rdes.append(r)

	# reinitialize room graph description
	for r in rdes:	# for (r1 = rdes; r1 <= &rdes[MAXROOMS-1]; r1++)
		for k in MAXROOMS:
			r.isconn[k] = false
		r.ingraph = false

	# starting with one room, connect it to a random adjacent room and
	# then pick a new room to start with.
	roomcount = 1
	r1 = rdes[rnd(MAXROOMS)]
	r1.ingraph = true
	while true:
		# find a room to connect with
		j = 0
		i = 0
		while i < MAXROOMS:
			if r1.conn[i] and not rdes[i].ingraph:
				j += 1
				if rnd(j) == 0:
					r2 = rdes[i]
			i += 1
		# if no adjacent rooms are outside the graph, pick a new room
		# to look from
		if j == 0:
			while true:
				r1 = rdes[rnd(MAXROOMS)]
				if r1.ingraph:
					break
		# otherwise, connect new room to the graph, and draw a tunnel
		# to it
		else:
			r2.ingraph = true
			i = rdes.find(r1)	# (int)(r1 - rdes)
			j = rdes.find(r2)
			await conn(i, j)
			r1.isconn[j] = true
			r2.isconn[i] = true
			roomcount += 1
		if not (roomcount < MAXROOMS):
			break

	# attempt to add passages to the graph a random number of times so
	# that there isn't always just one unique passage through it.
	roomcount = rnd(5)
	while roomcount > 0:
		r1 = rdes[rnd(MAXROOMS)]	# a random room to look from
		# find an adjacent room not already connected
		j = 0
		i = 0
		while i < MAXROOMS:
			if r1.conn[i] and not r1.isconn[i]:
				j += 1
				if rnd(j) == 0:
					r2 = rdes[i]
			i += 1
		# if there is one, connect it and look for the next added
		# passage
		if j != 0:
			i = rdes.find(r1)
			j = rdes.find(r2)
			await conn(i, j)
			r1.isconn[j] = true
			r2.isconn[i] = true
		roomcount -= 1
	passnum()


## conn:
##	Draw a corridor from a room in a certain direction.
static func conn(r1: int, r2: int) -> void:
	var rpf: Room
	var rpt: Room = null
	var rmt: int
	var distance := 0
	var turn_spot: int
	var turn_distance := 0
	var rm: int
	var direc: int
	# static coord del, curr, turn_delta, spos, epos;
	var del := _conn_del
	var curr := _conn_curr
	var turn_delta := _conn_turn_delta
	var spos := _conn_spos
	var epos := _conn_epos

	if r1 < r2:
		rm = r1
		if r1 + 1 == r2:
			direc = ord("r")
		else:
			direc = ord("d")
	else:
		rm = r2
		if r2 + 1 == r1:
			direc = ord("r")
		else:
			direc = ord("d")
	rpf = rooms[rm]
	# Set up the movement variables, in two cases:
	# first drawing one down.
	if direc == ord("d"):
		rmt = rm + 3				# room # of dest
		rpt = rooms[rmt]			# room pointer of dest
		del.x = 0				# direction of move
		del.y = 1
		spos.x = rpf.r_pos.x			# start of move
		spos.y = rpf.r_pos.y
		epos.x = rpt.r_pos.x			# end of move
		epos.y = rpt.r_pos.y
		if (rpf.r_flags & ISGONE) == 0:		# if not gone pick door pos
			if fixes:	# FIX 8
				_maze_door(rpf, rpf.r_pos.y + rpf.r_max.y - 1, rpf.r_pos.x, 0, 1, rpf.r_max.x - 2)
			var tries := 0
			while true:
				tries += 1
				if tries > STUCK_TRIES:
					await _stuck()
					return
				spos.x = rpf.r_pos.x + rnd(rpf.r_max.x - 2) + 1
				spos.y = rpf.r_pos.y + rpf.r_max.y - 1
				if not ((rpf.r_flags & ISMAZE) != 0 and (flat(spos.y, spos.x) & F_PASS) == 0):
					break
		if (rpt.r_flags & ISGONE) == 0:
			if fixes:	# FIX 8
				_maze_door(rpt, epos.y, rpt.r_pos.x, 0, 1, rpt.r_max.x - 2)
			var tries := 0
			while true:
				tries += 1
				if tries > STUCK_TRIES:
					await _stuck()
					return
				epos.x = rpt.r_pos.x + rnd(rpt.r_max.x - 2) + 1
				if not ((rpt.r_flags & ISMAZE) != 0 and (flat(epos.y, epos.x) & F_PASS) == 0):
					break
		distance = absi(spos.y - epos.y) - 1	# distance to move
		turn_delta.y = 0			# direction to turn
		turn_delta.x = 1 if spos.x < epos.x else -1
		turn_distance = absi(spos.x - epos.x)	# how far to turn
	elif direc == ord("r"):			# setup for moving right
		rmt = rm + 1
		rpt = rooms[rmt]
		del.x = 1
		del.y = 0
		spos.x = rpf.r_pos.x
		spos.y = rpf.r_pos.y
		epos.x = rpt.r_pos.x
		epos.y = rpt.r_pos.y
		if (rpf.r_flags & ISGONE) == 0:
			if fixes:	# FIX 8
				_maze_door(rpf, rpf.r_pos.y, rpf.r_pos.x + rpf.r_max.x - 1, 1, 0, rpf.r_max.y - 2)
			var tries := 0
			while true:
				tries += 1
				if tries > STUCK_TRIES:
					await _stuck()
					return
				spos.x = rpf.r_pos.x + rpf.r_max.x - 1
				spos.y = rpf.r_pos.y + rnd(rpf.r_max.y - 2) + 1
				if not ((rpf.r_flags & ISMAZE) != 0 and (flat(spos.y, spos.x) & F_PASS) == 0):
					break
		if (rpt.r_flags & ISGONE) == 0:
			if fixes:	# FIX 8
				_maze_door(rpt, rpt.r_pos.y, epos.x, 1, 0, rpt.r_max.y - 2)
			var tries := 0
			while true:
				tries += 1
				if tries > STUCK_TRIES:
					await _stuck()
					return
				epos.y = rpt.r_pos.y + rnd(rpt.r_max.y - 2) + 1
				if not ((rpt.r_flags & ISMAZE) != 0 and (flat(epos.y, epos.x) & F_PASS) == 0):
					break
		distance = absi(spos.x - epos.x) - 1
		turn_delta.y = 1 if spos.y < epos.y else -1
		turn_delta.x = 0
		turn_distance = absi(spos.y - epos.y)
	elif MASTER:
		await debug("error in connection tables")

	turn_spot = rnd(distance - 1) + 1		# where turn starts

	# Draw in the doors on either side of the passage or just put #'s
	# if the rooms are gone.
	if (rpf.r_flags & ISGONE) == 0:
		door(rpf, spos)
	else:
		putpass(spos)
	if (rpt.r_flags & ISGONE) == 0:
		door(rpt, epos)
	else:
		putpass(epos)
	# Get ready to move...
	curr.x = spos.x
	curr.y = spos.y
	while distance > 0:
		# Move to new position
		curr.x += del.x
		curr.y += del.y
		# Check if we are at the turn place, if so do the turn
		if distance == turn_spot:
			while true:	# while (turn_distance--)
				var t := turn_distance
				turn_distance -= 1
				if t == 0:
					break
				putpass(curr)
				curr.x += turn_delta.x
				curr.y += turn_delta.y
		# Continue digging along
		putpass(curr)
		distance -= 1
	curr.x += del.x
	curr.y += del.y
	if not ce(curr, epos):
		await Io.msg("warning, connectivity problem on this level")


## putpass:
##	add a passage character or secret passage here
static func putpass(cp: Coord) -> void:
	var pp: Place

	pp = INDEX(cp.y, cp.x)
	pp.p_flags |= F_PASS
	if rnd(10) + 1 < level and rnd(40) == 0:
		pp.p_flags &= ~F_REAL
	else:
		pp.p_ch = PASSAGE


## door:
##	Add a door or possibly a secret door.  Also enters the door in
##	the exits array of the room.
static func door(rm: Room, cp: Coord) -> void:
	var pp: Place

	rm.r_exit[rm.r_nexits].copy_from(cp)	# rm->r_exit[rm->r_nexits++] = *cp;
	rm.r_nexits += 1

	if (rm.r_flags & ISMAZE) != 0:
		return

	pp = INDEX(cp.y, cp.x)
	if rnd(10) + 1 < level and rnd(5) == 0:
		if cp.y == rm.r_pos.y or cp.y == rm.r_pos.y + rm.r_max.y - 1:
			pp.p_ch = ord("-")
		else:
			pp.p_ch = ord("|")
		pp.p_flags &= ~F_REAL
	else:
		pp.p_ch = DOOR


## add_pass:
##	Add the passages to the current window (wizard command)
##	(#ifdef MASTER in C)
static func add_pass() -> void:
	var pp: Place
	var ch: int

	for y in range(1, NUMLINES - 1):
		for x in NUMCOLS:
			pp = INDEX(y, x)
			if (pp.p_flags & F_PASS) != 0 or pp.p_ch == DOOR or \
					((pp.p_flags & F_REAL) == 0 and (pp.p_ch == ord("|") or pp.p_ch == ord("-"))):
				ch = pp.p_ch
				if (pp.p_flags & F_PASS) != 0:
					ch = PASSAGE
				pp.p_flags |= F_SEEN
				move(y, x)
				if pp.p_monst != null:
					pp.p_monst.t_oldch = pp.p_ch
				elif (pp.p_flags & F_REAL) != 0:
					addch(ch)
				else:
					standout()
					addch(PASSAGE if (pp.p_flags & F_PASS) != 0 else DOOR)
					standend()


## passnum:
##	Assign a number to each passageway
static func passnum() -> void:
	_passages_pnum = 0
	_passages_newpnum = false
	for rp in passages:
		rp.r_nexits = 0
	for rp in rooms:
		for i in rp.r_nexits:
			_passages_newpnum = true	# newpnum++ (a bool)
			numpass(rp.r_exit[i].y, rp.r_exit[i].x)


## numpass:
##	Number a passageway square and its brethren
static func numpass(y: int, x: int) -> void:
	var fp: Place	# char *fp = &flat(y, x): fp.p_flags
	var rp: Room
	var ch: int

	if x >= NUMCOLS or x < 0 or y >= NUMLINES or y <= 0:
		return
	fp = INDEX(y, x)
	if (fp.p_flags & F_PNUM) != 0:
		return
	if _passages_newpnum:
		_passages_pnum += 1
		_passages_newpnum = false
	# check to see if it is a door or secret door, i.e., a new exit,
	# or a numerable type of place
	ch = chat(y, x)
	if ch == DOOR or \
			((fp.p_flags & F_REAL) == 0 and (ch == ord("|") or ch == ord("-"))):
		rp = passages[_passages_pnum]
		rp.r_exit[rp.r_nexits].y = y
		rp.r_exit[rp.r_nexits].x = x
		rp.r_nexits += 1
	elif (fp.p_flags & F_PASS) == 0:
		return
	fp.p_flags |= _passages_pnum
	# recurse on the surrounding places
	numpass(y + 1, x)
	numpass(y - 1, x)
	numpass(y, x + 1)
	numpass(y, x - 1)


## (port, FIX 8) conn() picks a door among squares 1..n of a row (dy 0, dx 1)
## or column (dy 1, dx 0) of a room starting at (y, x), and for a maze it waits
## for a passage square there. A maze's cells are at even offsets from its
## corner; a row or column between two rows or columns of cells has a passage
## square only where the maze links them, and may have none in range: the loop
## never ended. Then dig one at an even offset, which links two cells.
static func _maze_door(rp: Room, y: int, x: int, dy: int, dx: int, n: int) -> void:
	var k: int
	var c := Coord.new()

	if (rp.r_flags & ISMAZE) == 0:
		return
	for i in range(1, n + 1):
		if (flat(y + i * dy, x + i * dx) & F_PASS) != 0:
			return
	k = 2 * (rnd(n / 2) + 1)
	c.y = y + k * dy
	c.x = x + k * dx
	putpass(c)


## The level generator is stuck (see STUCK_TRIES): end the game.
static func _stuck() -> void:
	endwin()
	printf("\nrogue: the level generator is stuck (a hang in Rogue 5.4.4); the game cannot continue.\n")
	await exit(1)
