## RogueBase: rogue.h + extern.h + extern.c.
##
## Every game module (one per C file) `extends RogueBase`, so module code can
## use the constants, macros, global state and C helpers unqualified, exactly
## like the C code does. Calls into other modules are qualified: Io.msg(...).
##
## All mutable game state lives here as static vars (extern.c globals, other
## files' globals, and file/function statics named _<file>_<var> or
## _<function>_<var>). reset() re-creates all of it for a new game; the
## "constant" tables the C code mutates at run time are rebuilt from pristine
## copies there too.
class_name RogueBase
extends RefCounted

# =========================================================================
# extern.h / rogue.h constants
# =========================================================================

const MAXSTR := 1024
const MAXLINES := 32
const MAXCOLS := 80

const MAXROOMS := 9
const MAXTHINGS := 9
const MAXOBJ := 9
const MAXPACK := 23
const MAXTRAPS := 10
const AMULETLEVEL := 26
const NUMTHINGS := 7
const MAXPASS := 13
const NUMLINES := 24
const NUMCOLS := 80
const STATLINE := NUMLINES - 1
const BORE_LEVEL := 50

## return values for get functions
const NORM := 0
const QUIT := 1
const MINUS := 2

## inventory types
const INV_OVER := 0
const INV_SLOW := 1
const INV_CLEAR := 2

## things that appear on the screens
const PASSAGE := 35	# '#'
const DOOR := 43	# '+'
const FLOOR := 46	# '.'
const PLAYER := 64	# '@'
const TRAP := 94	# '^'
const STAIRS := 37	# '%'
const GOLD := 42	# '*'
const POTION := 33	# '!'
const SCROLL := 63	# '?'
const MAGIC := 36	# '$'
const FOOD := 58	# ':'
const WEAPON := 41	# ')'
const ARMOR := 93	# ']'
const AMULET := 44	# ','
const RING := 61	# '='
const STICK := 47	# '/'
const CALLABLE := -1
const R_OR_S := -2

## Various constants (BEARTIME etc. are functions below: they call spread())
const HEALTIME := 30
const HUHDURATION := 20
const SEEDURATION := 850
const HUNGERTIME := 1300
const MORETIME := 150
const STOMACHSIZE := 2000
const STARVETIME := 850
const ESCAPE := 27
const LEFT := 0
const RIGHT := 1
const BOLT_LENGTH := 6
const LAMPDIST := 3
const PASSWD := "mTBellIQOsLNA"

## Save against things
const VS_POISON := 0
const VS_PARALYZATION := 0
const VS_DEATH := 0
const VS_BREATH := 2
const VS_MAGIC := 3

## flags for rooms
const ISDARK := 0x1
const ISGONE := 0x2
const ISMAZE := 0x4

## flags for objects
const ISCURSED := 0x1
const ISKNOW := 0x2
const ISMISL := 0x4
const ISMANY := 0x8
const ISPROT := 0x20
## (Guild mode, Throw Anything) a ring or scroll a monster was hit with: it works on
## the monster that carries it, and goes with it when it dies (docs/GUILD.md).
const ISMONWORN := 0x40

## flags for creatures
const CANHUH := 0x1
const CANSEE := 0x2
const ISBLIND := 0x4
const ISCANC := 0x8
const ISLEVIT := 0x8
const ISFOUND := 0x10
const ISGREED := 0x20
const ISHASTE := 0x40
const ISTARGET := 0x80
const ISHELD := 0x100
const ISHUH := 0x200
const ISINVIS := 0x400
const ISMEAN := 0x800
const ISHALU := 0x800
const ISREGEN := 0x1000
const ISRUN := 0x2000
const SEEMONST := 0x4000
const ISFLY := 0x4000
const ISSLOW := 0x8000
## (Guild mode, the Serpentine Cult) a rattlesnake whose bite has made the hero
## stronger: each one does it once (docs/GUILD.md, "Skills"). Saved with it.
const GAVESTR := 0x10000

## flags for level map
const F_PASS := 0x80
const F_SEEN := 0x40
const F_DROPPED := 0x20
const F_LOCKED := 0x20
const F_REAL := 0x10
const F_PNUM := 0x0f
const F_TMASK := 0x07

## trap types
const T_DOOR := 0
const T_ARROW := 1
const T_SLEEP := 2
const T_BEAR := 3
const T_TELEP := 4
const T_DART := 5
const T_RUST := 6
const T_MYST := 7
const NTRAPS := 8

## potion types
const P_CONFUSE := 0
const P_LSD := 1
const P_POISON := 2
const P_STRENGTH := 3
const P_SEEINVIS := 4
const P_HEALING := 5
const P_MFIND := 6
const P_TFIND := 7
const P_RAISE := 8
const P_XHEAL := 9
const P_HASTE := 10
const P_RESTORE := 11
const P_BLIND := 12
const P_LEVIT := 13
const MAXPOTIONS := 14

## scroll types
const S_CONFUSE := 0
const S_MAP := 1
const S_HOLD := 2
const S_SLEEP := 3
const S_ARMOR := 4
const S_ID_POTION := 5
const S_ID_SCROLL := 6
const S_ID_WEAPON := 7
const S_ID_ARMOR := 8
const S_ID_R_OR_S := 9
const S_SCARE := 10
const S_FDET := 11
const S_TELEP := 12
const S_ENCH := 13
const S_CREATE := 14
const S_REMOVE := 15
const S_AGGR := 16
const S_PROTECT := 17
const MAXSCROLLS := 18

## weapon types
const MACE := 0
const SWORD := 1
const BOW := 2
const ARROW := 3
const DAGGER := 4
const TWOSWORD := 5
const DART := 6
const SHIRAKEN := 7
const SPEAR := 8
const FLAME := 9
const MAXWEAPONS := 9

## armor types
const LEATHER := 0
const RING_MAIL := 1
const STUDDED_LEATHER := 2
const SCALE_MAIL := 3
const CHAIN_MAIL := 4
const SPLINT_MAIL := 5
const BANDED_MAIL := 6
const PLATE_MAIL := 7
const MAXARMORS := 8

## ring types
const R_PROTECT := 0
const R_ADDSTR := 1
const R_SUSTSTR := 2
const R_SEARCH := 3
const R_SEEINVIS := 4
const R_NOP := 5
const R_AGGR := 6
const R_ADDHIT := 7
const R_ADDDAM := 8
const R_REGEN := 9
const R_DIGEST := 10
const R_TELEPORT := 11
const R_STEALTH := 12
const R_SUSTARM := 13
const MAXRINGS := 14

## rod/wand/staff types
const WS_LIGHT := 0
const WS_INVIS := 1
const WS_ELECT := 2
const WS_FIRE := 3
const WS_COLD := 4
const WS_POLYMORPH := 5
const WS_MISSILE := 6
const WS_HASTE_M := 7
const WS_SLOW_M := 8
const WS_DRAIN := 9
const WS_NOP := 10
const WS_TELAWAY := 11
const WS_TELTO := 12
const WS_CANCEL := 13
const MAXSTICKS := 14

const MAXDAEMONS := 20
## daemon.c
const EMPTY := 0
const DAEMON := -1

## mach_dep.c
const NUMSCORES := 10
const NUMNAME := "Ten"
## vers.c
const release := "5.4.4"
const version := "rogue (rogueforge) 09/05/07"

## Daemon / fuse function ids (C passes function pointers). Dispatched by
## Daemon._call(); saved by name.
const D_RUNNERS := &"runners"
const D_DOCTOR := &"doctor"
const D_SWANDER := &"swander"
const D_STOMACH := &"stomach"
const D_ROLLWAND := &"rollwand"
const D_UNCONFUSE := &"unconfuse"
const D_NOHASTE := &"nohaste"
const D_UNSEE := &"unsee"
const D_SIGHT := &"sight"
const D_LAND := &"land"
const D_COME_DOWN := &"come_down"
const D_VISUALS := &"visuals"
const D_TURN_SEE := &"turn_see"

## Control characters: CTRL('x') == x & 037
const CTRL_A := 1
const CTRL_B := 2
const CTRL_C := 3
const CTRL_D := 4
const CTRL_E := 5
const CTRL_F := 6
const CTRL_G := 7
const CTRL_H := 8
const CTRL_I := 9
const CTRL_J := 10
const CTRL_K := 11
const CTRL_L := 12
const CTRL_M := 13
const CTRL_N := 14
const CTRL_O := 15
const CTRL_P := 16
const CTRL_Q := 17
const CTRL_R := 18
const CTRL_S := 19
const CTRL_T := 20
const CTRL_U := 21
const CTRL_V := 22
const CTRL_W := 23
const CTRL_X := 24
const CTRL_Y := 25
const CTRL_Z := 26

## curses constants used by the game
const OK := Curses.OK
const ERR := Curses.ERR
const A_CHARTEXT := Curses.A_CHARTEXT
const A_STANDOUT := Curses.A_STANDOUT
const LINES := 24
const COLS := 80

## extern.c tables that never change
const a_class: Array[int] = [8, 7, 7, 6, 5, 4, 4, 3]
const e_levels: Array[int] = [10, 20, 40, 80, 160, 320, 640, 1300, 2600, 5200,
	13000, 26000, 50000, 100000, 200000, 400000, 800000, 2000000, 4000000,
	8000000, 0]
const inv_t_name: Array[String] = ["Overwrite", "Slow", "Clear"]
const tr_name: Array[String] = ["a trapdoor", "an arrow trap", "a sleeping gas trap",
	"a beartrap", "a teleport trap", "a poison dart trap", "a rust trap",
	"a mysterious trap"]

# =========================================================================
# Program / environment settings (set by the runner before Main.main)
# =========================================================================

## The curses emulation for this game.
static var cs: Curses
## MASTER: wizard mode compiled in (a build-time #define in C).
static var MASTER := false
## Gameplay switches (docs/CHANGES.md). Like MASTER they are set by the host before
## Main.main() and reset() leaves them alone. The playable game turns them on;
## godot/tests/replay.gd keeps them off unless a test asks, so the classic game stays
## differential-tested against the stock C.
## fixes: fixes for the original's bugs. The same fixes are in
## harness/oracle/fixes.patch (oracle variants "fixed" and "fixedmaster").
static var fixes := false
## guild: the Fighters' Guild (godot/guild): the shop before each new game and a
## 20-entry Hall of Fame.
static var guild := false
## The Guild purchases for the next new game (a Dictionary, see godot/guild/loadout.gd),
## or null. Main.main() applies it once, in guild mode.
static var loadout: Variant = null
## menus: PC Rogue-style item menus. A command that asks for an item lists the
## items that fit at once (Pack.get_item), instead of "(* for list)".
static var menus := false
## exp_next: the status line also shows the experience at which the next level
## starts: "Exp: 2/15/20" (Io.status).
static var exp_next := false
## Values the C program gets from its environment (pinned in test mode).
static var env_rogueopts: Variant = null	## getenv("ROGUEOPTS"): String or null
static var env_name := "rodney"		## md_getusername()
static var env_home := "/home/rodney/"	## md_gethomedir(), with trailing '/'
static var env_time := 1000000000	## time(NULL)
static var env_pid := 0			## md_getpid()
static var env_uid := 1000		## md_getuid()
static var env_seedvar: Variant = null	## getenv("SEED") (MASTER only)
static var env_scorefile := "rogue.scr"	## SCOREFILE (configure default: relative to the cwd)
static var env_lockfile := "rogue.lck"	## LOCKFILE
## The process's current directory: relative file names resolve against it.
static var env_cwd := ""


## Test mode: files may only be written in the run directory (the oracle's
## hooks.c refuses the same names with ENOENT).
static var env_sandbox := false


## A file name that leaves the run directory ("/x", "../x", "a/b"; a leading
## "./" is allowed) while the sandbox is on.
static func outside_rundir(p: String) -> bool:
	if not env_sandbox:
		return false
	if p.begins_with("./"):
		p = p.substr(2)
	return p.contains("/")


## A C file name as the port opens it (relative names resolve against env_cwd).
static func cpath(p: String) -> String:
	if env_cwd == "" or p.is_absolute_path() or p.begins_with("user://") or p.begins_with("res://"):
		return p
	return env_cwd.path_join(p)
static var argv: PackedStringArray = PackedStringArray()

# =========================================================================
# Global state (extern.c and other files' globals)
# =========================================================================

static var after := false
static var again := false
static var noscore := 0
static var seenstairs := false
static var amulet := false
static var door_stop := false
static var fight_flush := false
static var firstmove := false
static var got_ltc := false
static var has_hit := false
static var in_shell := false
static var inv_describe := true
static var jump := false
static var kamikaze := false
static var lower_msg := false
static var move_on := false
static var msg_esc := false
static var passgo := false
static var playing := true
static var q_comm := false
static var running := false
static var save_msg := true
static var see_floor := true
static var stat_msg := false
static var terse := false
static var to_death := false
static var tombstone := true
static var wizard := false
static var pack_used: Array[bool] = []

static var dir_ch := 0
static var file_name := ""
static var huh := ""
static var p_colors: Array[String] = []
static var prbuf := ""
static var r_stones: Array[String] = []
static var runch := 0
static var s_names: Array[String] = []
static var take := 0
static var whoami := ""
static var ws_made: Array[String] = []
static var ws_type: Array[String] = []
static var orig_dsusp := 0
static var fruit := "slime-mold"
static var home := ""
static var l_last_comm := 0
static var l_last_dir := 0
static var last_comm := 0
static var last_dir := 0

static var n_objs := 0
static var ntraps := 0
static var hungry_state := 0
static var inpack := 0
## Guild mode: the pack's size (Rogue's MAXPACK, more with slots bought from the
## Guild, see godot/guild/loadout.gd); pack_room() uses it instead of MAXPACK.
static var maxpack := MAXPACK
## Guild mode: the skills bought from the Guild (docs/GUILD.md, "Skills"): name
## (GuildCatalog.SKILLS, the SK_* below) -> level (1; the coin scrounger's level).
## Loadout.apply sets them; the save keeps them. skill() reads them.
static var skills := {}
## The Serpentine Cult: the hero killed a snake (the benefits are lost and snakes
## hit 50% harder). Saved.
static var cult_banished := false
## The snakes a hostile action was confirmed against, and those the last warning
## was about (a hostile action on them now goes through). Not saved.
static var cult_confirmed: Array = []
static var cult_warned: Array = []
static var inv_type := 0
static var level := 1
static var max_hit := 0
static var max_level := 0
static var mpos := 0
static var no_food := 0
static var count := 0
static var food_left := 0
static var lastscore := -1
static var no_command := 0
static var no_move := 0
static var purse := 0
static var quiet := 0
static var vf_hit := 0
static var dnum := 0
## RNG state, an unsigned 32-bit value (C: int seed with wrapping arithmetic)
static var seed_ := 0

static var delta := Coord.new()
static var oldpos := Coord.new()
static var stairs := Coord.new()
static var places: Array[Place] = []

static var cur_armor: Thing = null
static var cur_ring: Array = [null, null]	## THING *cur_ring[2]
static var cur_weapon: Thing = null
static var l_last_pick: Thing = null
static var last_pick: Thing = null
static var lvl_obj: Thing = null
static var mlist: Thing = null
static var player := Thing.new()

static var hw: Curses.CWindow = null
static var max_stats := Stats.new()
static var oldrp: Room = null
static var rooms: Array[Room] = []
static var passages: Array[Room] = []
static var monsters: Array[Monster] = []
static var things: Array[ObjInfo] = []
static var arm_info: Array[ObjInfo] = []
static var pot_info: Array[ObjInfo] = []
static var ring_info: Array[ObjInfo] = []
static var scr_info: Array[ObjInfo] = []
static var weap_info: Array[ObjInfo] = []
static var ws_info: Array[ObjInfo] = []
static var helpstr: Array[HList] = []

## daemon.c
static var d_list: Array[DelayedAction] = []
## daemons.c
static var between := 0
## list.c
static var total := 0
## move.c
static var nh := Coord.new()
## weapons.c
static var group := 2
## mach_dep.c
static var allscore := true
static var numscores := NUMSCORES
static var Numname := NUMNAME
## extern.c: FILE *scoreboard, opened by open_score() at startup
static var scoreboard: FileAccess = null

# ---- file statics and function statics (persist across calls in C) ------
## chase.c
static var _chase_ch_ret := Coord.new()
static var _cansee_tp := Coord.new()
static var _chase_tryp := Coord.new()
static var _do_chase_this := Coord.new()
static var _runners_orig_pos := Coord.new()
## command.c
static var _command_countch := 0
static var _command_direction := 0
static var _command_newcount := false
## init.c
static var _init_used: Array[bool] = []
static var _init_materials_metused: Array[bool] = []
## io.c
static var _io_msgbuf := ""
static var _io_newpos := 0
static var _status_hpwidth := 0
static var _status_s_hungry := 0
static var _status_s_lvl := 0
static var _status_s_pur := -1
static var _status_s_hp := 0
static var _status_s_arm := 0
static var _status_s_str := 0
static var _status_s_exp := 0
## misc.c
static var _get_dir_last_delt := Coord.new()
## monsters.c
static var _wanderer_cp := Coord.new()
## move.c
static var _rndmove_ret := Coord.new()
## new_level.c
static var _treas_room_mp := Coord.new()
## passages.c
static var _passages_newpnum := false
static var _passages_pnum := 0
static var _conn_curr := Coord.new()
static var _conn_del := Coord.new()
static var _conn_epos := Coord.new()
static var _conn_spos := Coord.new()
static var _conn_turn_delta := Coord.new()
## rooms.c
static var _rooms_Maxx := 0
static var _rooms_Maxy := 0
static var _rooms_Startx := 0
static var _rooms_Starty := 0
static var _dig_pos := Coord.new()
static var _do_maze_pos := Coord.new()
static var _do_rooms_top := Coord.new()
## scrolls.c
static var _read_scroll_mp := Coord.new()
## sticks.c
static var _do_zap_bolt := Thing.new()
static var _fire_bolt_pos := Coord.new()
static var _fire_bolt_spotpos: Array[Coord] = []
## things.c
static var _things_lastfmt := ""
static var _things_lastarg: Variant = null	## char *lastarg: String or NULL
static var _things_line_cnt := 0
static var _things_newpage := false
static var _add_line_maxlen := -1
static var _print_disc_obj := Thing.new()
## options.c
static var _get_num_buf := ""	## get_num(): static char buf[MAXSTR] (MASTER)
## save.c
static var _save_scoreline := PackedByteArray()	## static char scoreline[100]
## weapons.c
static var _fall_fpos := Coord.new()
static var _hit_monster_mp := Coord.new()

## map index of out-of-range squares (x == -1 in left-column mazes)
static var _dummy_place := Place.new()


## Re-create all game state with its initial values (a fresh process in C).
static func reset() -> void:
	after = false
	again = false
	noscore = 0
	seenstairs = false
	amulet = false
	door_stop = false
	fight_flush = false
	firstmove = false
	got_ltc = false
	has_hit = false
	in_shell = false
	inv_describe = true
	jump = false
	kamikaze = false
	lower_msg = false
	move_on = false
	msg_esc = false
	passgo = false
	playing = true
	q_comm = false
	running = false
	save_msg = true
	see_floor = true
	stat_msg = false
	terse = false
	to_death = false
	tombstone = true
	wizard = false
	pack_used = []
	pack_used.resize(26)
	pack_used.fill(false)

	dir_ch = 0
	file_name = ""
	huh = ""
	p_colors = []
	p_colors.resize(MAXPOTIONS)
	prbuf = ""
	r_stones = []
	r_stones.resize(MAXRINGS)
	runch = 0
	s_names = []
	s_names.resize(MAXSCROLLS)
	take = 0
	whoami = ""
	ws_made = []
	ws_made.resize(MAXSTICKS)
	ws_type = []
	ws_type.resize(MAXSTICKS)
	orig_dsusp = 0
	fruit = "slime-mold"
	home = ""
	l_last_comm = 0
	l_last_dir = 0
	last_comm = 0
	last_dir = 0

	n_objs = 0
	ntraps = 0
	hungry_state = 0
	inpack = 0
	maxpack = MAXPACK
	skills = {}
	cult_banished = false
	cult_confirmed = []
	cult_warned = []
	inv_type = 0
	level = 1
	max_hit = 0
	max_level = 0
	mpos = 0
	no_food = 0
	count = 0
	food_left = 0
	lastscore = -1
	no_command = 0
	no_move = 0
	purse = 0
	quiet = 0
	vf_hit = 0
	dnum = 0
	seed_ = 0

	delta = Coord.new()
	oldpos = Coord.new()
	stairs = Coord.new()
	places = []
	for i in MAXLINES * MAXCOLS:
		places.append(Place.new())
	for p in places:
		p.p_ch = 0	# zeroed global array
	_dummy_place = Place.new()

	cur_armor = null
	cur_ring = [null, null]
	cur_weapon = null
	l_last_pick = null
	last_pick = null
	lvl_obj = null
	mlist = null
	player = Thing.new()

	hw = null
	max_stats = Stats.new(16, 0, 1, 10, 12, "1x4", 12)
	oldrp = null
	rooms = []
	for i in MAXROOMS:
		rooms.append(Room.new())
	passages = []
	for i in MAXPASS:
		var rp := Room.new()
		if i < 12:	# the C initializer lists 12 of the 13 entries
			rp.r_flags = ISGONE | ISDARK
		passages.append(rp)
	_reset_tables()

	d_list = []
	for i in MAXDAEMONS:
		d_list.append(DelayedAction.new())
	between = 0
	total = 0
	nh = Coord.new()
	group = 2
	allscore = true
	numscores = NUMSCORES
	Numname = NUMNAME
	scoreboard = null
	_get_num_buf = ""
	_save_scoreline = PackedByteArray()
	_save_scoreline.resize(100)

	_chase_ch_ret = Coord.new()
	_cansee_tp = Coord.new()
	_chase_tryp = Coord.new()
	_do_chase_this = Coord.new()
	_runners_orig_pos = Coord.new()
	_command_countch = 0
	_command_direction = 0
	_command_newcount = false
	_init_used = []
	_init_used.resize(33)
	_init_used.fill(false)
	_init_materials_metused = []
	_init_materials_metused.resize(22)
	_init_materials_metused.fill(false)
	_io_msgbuf = ""
	_io_newpos = 0
	_status_hpwidth = 0
	_status_s_hungry = 0
	_status_s_lvl = 0
	_status_s_pur = -1
	_status_s_hp = 0
	_status_s_arm = 0
	_status_s_str = 0
	_status_s_exp = 0
	_get_dir_last_delt = Coord.new()
	_wanderer_cp = Coord.new()
	_rndmove_ret = Coord.new()
	_treas_room_mp = Coord.new()
	_passages_newpnum = false
	_passages_pnum = 0
	_conn_curr = Coord.new()
	_conn_del = Coord.new()
	_conn_epos = Coord.new()
	_conn_spos = Coord.new()
	_conn_turn_delta = Coord.new()
	_rooms_Maxx = 0
	_rooms_Maxy = 0
	_rooms_Startx = 0
	_rooms_Starty = 0
	_dig_pos = Coord.new()
	_do_maze_pos = Coord.new()
	_do_rooms_top = Coord.new()
	_read_scroll_mp = Coord.new()
	_do_zap_bolt = Thing.new()
	_fire_bolt_pos = Coord.new()
	_fire_bolt_spotpos = []
	for i in BOLT_LENGTH:
		_fire_bolt_spotpos.append(Coord.new())
	_things_lastfmt = ""
	_things_lastarg = null
	_things_line_cnt = 0
	_things_newpage = false
	_add_line_maxlen = -1
	_print_disc_obj = Thing.new()
	_fall_fpos = Coord.new()
	_hit_monster_mp = Coord.new()


## The extern.c tables the game modifies at run time, rebuilt pristine.
static func _reset_tables() -> void:
	const XX := 10
	const U := 1	# ___ in extern.c
	monsters = [
		Monster.new("aquator", 0, ISMEAN, Stats.new(XX, 20, 5, 2, U, "0x0/0x0")),
		Monster.new("bat", 0, ISFLY, Stats.new(XX, 1, 1, 3, U, "1x2")),
		Monster.new("centaur", 15, 0, Stats.new(XX, 17, 4, 4, U, "1x2/1x5/1x5")),
		Monster.new("dragon", 100, ISMEAN, Stats.new(XX, 5000, 10, -1, U, "1x8/1x8/3x10")),
		Monster.new("emu", 0, ISMEAN, Stats.new(XX, 2, 1, 7, U, "1x2")),
		Monster.new("venus flytrap", 0, ISMEAN, Stats.new(XX, 80, 8, 3, U, "%%%x0")),
		Monster.new("griffin", 20, ISMEAN | ISFLY | ISREGEN, Stats.new(XX, 2000, 13, 2, U, "4x3/3x5")),
		Monster.new("hobgoblin", 0, ISMEAN, Stats.new(XX, 3, 1, 5, U, "1x8")),
		Monster.new("ice monster", 0, 0, Stats.new(XX, 5, 1, 9, U, "0x0")),
		Monster.new("jabberwock", 70, 0, Stats.new(XX, 3000, 15, 6, U, "2x12/2x4")),
		Monster.new("kestrel", 0, ISMEAN | ISFLY, Stats.new(XX, 1, 1, 7, U, "1x4")),
		Monster.new("leprechaun", 0, 0, Stats.new(XX, 10, 3, 8, U, "1x1")),
		Monster.new("medusa", 40, ISMEAN, Stats.new(XX, 200, 8, 2, U, "3x4/3x4/2x5")),
		Monster.new("nymph", 100, 0, Stats.new(XX, 37, 3, 9, U, "0x0")),
		Monster.new("orc", 15, ISGREED, Stats.new(XX, 5, 1, 6, U, "1x8")),
		Monster.new("phantom", 0, ISINVIS, Stats.new(XX, 120, 8, 3, U, "4x4")),
		Monster.new("quagga", 0, ISMEAN, Stats.new(XX, 15, 3, 3, U, "1x5/1x5")),
		Monster.new("rattlesnake", 0, ISMEAN, Stats.new(XX, 9, 2, 3, U, "1x6")),
		Monster.new("snake", 0, ISMEAN, Stats.new(XX, 2, 1, 5, U, "1x3")),
		Monster.new("troll", 50, ISREGEN | ISMEAN, Stats.new(XX, 120, 6, 4, U, "1x8/1x8/2x6")),
		Monster.new("black unicorn", 0, ISMEAN, Stats.new(XX, 190, 7, -2, U, "1x9/1x9/2x9")),
		Monster.new("vampire", 20, ISREGEN | ISMEAN, Stats.new(XX, 350, 8, 1, U, "1x10")),
		Monster.new("wraith", 0, 0, Stats.new(XX, 55, 5, 4, U, "1x6")),
		Monster.new("xeroc", 30, 0, Stats.new(XX, 100, 7, 7, U, "4x4")),
		Monster.new("yeti", 30, 0, Stats.new(XX, 50, 4, 6, U, "1x6/1x6")),
		Monster.new("zombie", 0, ISMEAN, Stats.new(XX, 6, 2, 8, U, "1x8")),
	]
	things = [
		ObjInfo.new(null, 26), ObjInfo.new(null, 36), ObjInfo.new(null, 16),
		ObjInfo.new(null, 7), ObjInfo.new(null, 7), ObjInfo.new(null, 4),
		ObjInfo.new(null, 4),
	]
	arm_info = [
		ObjInfo.new("leather armor", 20, 20), ObjInfo.new("ring mail", 15, 25),
		ObjInfo.new("studded leather armor", 15, 20), ObjInfo.new("scale mail", 13, 30),
		ObjInfo.new("chain mail", 12, 75), ObjInfo.new("splint mail", 10, 80),
		ObjInfo.new("banded mail", 10, 90), ObjInfo.new("plate mail", 5, 150),
	]
	pot_info = [
		ObjInfo.new("confusion", 7, 5), ObjInfo.new("hallucination", 8, 5),
		ObjInfo.new("poison", 8, 5), ObjInfo.new("gain strength", 13, 150),
		ObjInfo.new("see invisible", 3, 100), ObjInfo.new("healing", 13, 130),
		ObjInfo.new("monster detection", 6, 130), ObjInfo.new("magic detection", 6, 105),
		ObjInfo.new("raise level", 2, 250), ObjInfo.new("extra healing", 5, 200),
		ObjInfo.new("haste self", 5, 190), ObjInfo.new("restore strength", 13, 130),
		ObjInfo.new("blindness", 5, 5), ObjInfo.new("levitation", 6, 75),
	]
	ring_info = [
		ObjInfo.new("protection", 9, 400), ObjInfo.new("add strength", 9, 400),
		ObjInfo.new("sustain strength", 5, 280), ObjInfo.new("searching", 10, 420),
		ObjInfo.new("see invisible", 10, 310), ObjInfo.new("adornment", 1, 10),
		ObjInfo.new("aggravate monster", 10, 10), ObjInfo.new("dexterity", 8, 440),
		ObjInfo.new("increase damage", 8, 400), ObjInfo.new("regeneration", 4, 460),
		ObjInfo.new("slow digestion", 9, 240), ObjInfo.new("teleportation", 5, 30),
		ObjInfo.new("stealth", 7, 470), ObjInfo.new("maintain armor", 5, 380),
	]
	scr_info = [
		ObjInfo.new("monster confusion", 7, 140), ObjInfo.new("magic mapping", 4, 150),
		ObjInfo.new("hold monster", 2, 180), ObjInfo.new("sleep", 3, 5),
		ObjInfo.new("enchant armor", 7, 160), ObjInfo.new("identify potion", 10, 80),
		ObjInfo.new("identify scroll", 10, 80), ObjInfo.new("identify weapon", 6, 80),
		ObjInfo.new("identify armor", 7, 100),
		ObjInfo.new("identify ring, wand or staff", 10, 115),
		ObjInfo.new("scare monster", 3, 200), ObjInfo.new("food detection", 2, 60),
		ObjInfo.new("teleportation", 5, 165), ObjInfo.new("enchant weapon", 8, 150),
		ObjInfo.new("create monster", 4, 75), ObjInfo.new("remove curse", 7, 105),
		ObjInfo.new("aggravate monsters", 3, 20), ObjInfo.new("protect armor", 2, 250),
	]
	weap_info = [
		ObjInfo.new("mace", 11, 8), ObjInfo.new("long sword", 11, 15),
		ObjInfo.new("short bow", 12, 15), ObjInfo.new("arrow", 12, 1),
		ObjInfo.new("dagger", 8, 3), ObjInfo.new("two handed sword", 10, 75),
		ObjInfo.new("dart", 12, 2), ObjInfo.new("shuriken", 12, 5),
		ObjInfo.new("spear", 12, 5),
		ObjInfo.new(null, 0),	# DO NOT REMOVE: fake entry for dragon's breath
	]
	ws_info = [
		ObjInfo.new("light", 12, 250), ObjInfo.new("invisibility", 6, 5),
		ObjInfo.new("lightning", 3, 330), ObjInfo.new("fire", 3, 330),
		ObjInfo.new("cold", 3, 330), ObjInfo.new("polymorph", 15, 310),
		ObjInfo.new("magic missile", 10, 170), ObjInfo.new("haste monster", 10, 5),
		ObjInfo.new("slow monster", 11, 350), ObjInfo.new("drain life", 9, 300),
		ObjInfo.new("nothing", 1, 5), ObjInfo.new("teleport away", 6, 340),
		ObjInfo.new("teleport to", 6, 50), ObjInfo.new("cancellation", 5, 280),
	]
	helpstr = [
		HList.new(ord("?"), "\tprints help", true),
		HList.new(ord("/"), "\tidentify object", true),
		HList.new(ord("h"), "\tleft", true),
		HList.new(ord("j"), "\tdown", true),
		HList.new(ord("k"), "\tup", true),
		HList.new(ord("l"), "\tright", true),
		HList.new(ord("y"), "\tup & left", true),
		HList.new(ord("u"), "\tup & right", true),
		HList.new(ord("b"), "\tdown & left", true),
		HList.new(ord("n"), "\tdown & right", true),
		HList.new(ord("H"), "\trun left", false),
		HList.new(ord("J"), "\trun down", false),
		HList.new(ord("K"), "\trun up", false),
		HList.new(ord("L"), "\trun right", false),
		HList.new(ord("Y"), "\trun up & left", false),
		HList.new(ord("U"), "\trun up & right", false),
		HList.new(ord("B"), "\trun down & left", false),
		HList.new(ord("N"), "\trun down & right", false),
		HList.new(CTRL_H, "\trun left until adjacent", false),
		HList.new(CTRL_J, "\trun down until adjacent", false),
		HList.new(CTRL_K, "\trun up until adjacent", false),
		HList.new(CTRL_L, "\trun right until adjacent", false),
		HList.new(CTRL_Y, "\trun up & left until adjacent", false),
		HList.new(CTRL_U, "\trun up & right until adjacent", false),
		HList.new(CTRL_B, "\trun down & left until adjacent", false),
		HList.new(CTRL_N, "\trun down & right until adjacent", false),
		HList.new(0, "\t<SHIFT><dir>: run that way", true),
		HList.new(0, "\t<CTRL><dir>: run till adjacent", true),
		HList.new(ord("f"), "<dir>\tfight till death or near death", true),
		HList.new(ord("t"), "<dir>\tthrow something", true),
		HList.new(ord("m"), "<dir>\tmove onto without picking up", true),
		HList.new(ord("z"), "<dir>\tzap a wand in a direction", true),
		HList.new(ord("^"), "<dir>\tidentify trap type", true),
		HList.new(ord("s"), "\tsearch for trap/secret door", true),
		HList.new(ord(">"), "\tgo down a staircase", true),
		HList.new(ord("<"), "\tgo up a staircase", true),
		HList.new(ord("."), "\trest for a turn", true),
		HList.new(ord(","), "\tpick something up", true),
		HList.new(ord("i"), "\tinventory", true),
		HList.new(ord("I"), "\tinventory single item", true),
		HList.new(ord("q"), "\tquaff potion", true),
		HList.new(ord("r"), "\tread scroll", true),
		HList.new(ord("e"), "\teat food", true),
		HList.new(ord("w"), "\twield a weapon", true),
		HList.new(ord("W"), "\twear armor", true),
		HList.new(ord("T"), "\ttake armor off", true),
		HList.new(ord("P"), "\tput on ring", true),
		HList.new(ord("R"), "\tremove ring", true),
		HList.new(ord("d"), "\tdrop object", true),
		HList.new(ord("c"), "\tcall object", true),
		HList.new(ord("a"), "\trepeat last command", true),
		HList.new(ord(")"), "\tprint current weapon", true),
		HList.new(ord("]"), "\tprint current armor", true),
		HList.new(ord("="), "\tprint current rings", true),
		HList.new(ord("@"), "\tprint current stats", true),
		HList.new(ord("D"), "\trecall what's been discovered", true),
		HList.new(ord("o"), "\texamine/set options", true),
		HList.new(CTRL_R, "\tredraw screen", true),
		HList.new(CTRL_P, "\trepeat last message", true),
		HList.new(ESCAPE, "\tcancel command", true),
		HList.new(ord("S"), "\tsave game", true),
		HList.new(ord("Q"), "\tquit", true),
		HList.new(ord("!"), "\tshell escape", true),
		HList.new(ord("F"), "<dir>\tfight till either of you dies", true),
		HList.new(ord("v"), "\tprint version number", true),
		HList.new(0, null, false),
	]


# =========================================================================
# rogue.h macros
# =========================================================================

## #define hero player.t_pos (struct: assign with hero.copy_from(c))
static var hero: Coord:
	get:
		return player.t_pos

## #define pstats player.t_stats (struct: assign with pstats.copy_from(s))
static var pstats: Stats:
	get:
		return player.t_stats

## #define pack player.t_pack
static var pack: Thing:
	get:
		return player.t_pack
	set(v):
		player.t_pack = v

## #define proom player.t_room
static var proom: Room:
	get:
		return player.t_room
	set(v):
		player.t_room = v

## #define max_hp player.t_stats.s_maxhp
static var max_hp: int:
	get:
		return player.t_stats.s_maxhp
	set(v):
		player.t_stats.s_maxhp = v


## on(thing, flag): takes the THING (struct), tests t_flags
static func on(thing: Thing, flag: int) -> bool:
	return (thing.t_flags & flag) != 0


## ce(a, b): coords equal
static func ce(a: Coord, b: Coord) -> bool:
	return a.x == b.x and a.y == b.y


static func GOLDCALC() -> int:
	return rnd(50 + 10 * level) + 2


# ---- the Guild's skills (guild mode; docs/GUILD.md, "Skills") ------------------

## Their names, as GuildCatalog.SKILLS and the price list have them.
const SK_FROST_RES := "frost resistance"
const SK_FROST_IMM := "frost immunity"
const SK_SURE_SIGHT := "sure sight"
const SK_INTELLECT := "high intellect"
const SK_LOW_LIGHT := "low-light vision"
const SK_THROW := "throw anything"
const SK_COIN := "coin scrounger"
const SK_POCKETS := "safe pockets"
const SK_CULT := "serpentine cult"
const SK_RECOVERY := "advanced recovery"


## The level of a skill the hero has (0: none; always 0 out of guild mode).
static func skill(name: String) -> int:
	return int(skills.get(name, 0)) if guild else 0


## The hero is in the Serpentine Cult (and not banished from it).
static func cult_member() -> bool:
	return skill(SK_CULT) > 0 and not cult_banished


## A snake, for the Serpentine Cult: a rattlesnake or a snake.
static func is_snake(tp: Thing) -> bool:
	return tp != null and (tp.t_type == ord("R") or tp.t_type == ord("S"))


static func ISRING(h: int, r: int) -> bool:
	return cur_ring[h] != null and cur_ring[h].o_which == r


static func ISWEARING(r: int) -> bool:
	return ISRING(LEFT, r) or ISRING(RIGHT, r)


static func ISMULT(type: int) -> bool:
	return type == POTION or type == SCROLL or type == FOOD


## INDEX(y,x) = &places[(x << 5) + y]. Out-of-range indices (x == -1 in
## left-column mazes; C reads foreign memory) get a blank dummy (FIDELITY.md).
static func INDEX(y: int, x: int) -> Place:
	var idx := x * 32 + y
	if idx >= 0 and idx < MAXLINES * MAXCOLS:
		return places[idx]
	_dummy_place.p_ch = 32
	_dummy_place.p_flags = F_REAL if fixes else 0	# FIX 27: off the map is solid rock
	_dummy_place.p_monst = null
	return _dummy_place


## chat/flat/moat read; to assign write INDEX(y, x).p_ch = c etc.
static func chat(y: int, x: int) -> int:
	return INDEX(y, x).p_ch


static func flat(y: int, x: int) -> int:
	return INDEX(y, x).p_flags


static func moat(y: int, x: int) -> Thing:
	return INDEX(y, x).p_monst


static func winat(y: int, x: int) -> int:
	return moat(y, x).t_disguise if moat(y, x) != null else chat(y, x)


## CCHAR(x): (char)(x & A_CHARTEXT)
static func CCHAR(x: int) -> int:
	return to_schar(x & A_CHARTEXT)


## CTRL(c): c & 037
static func CTRL(c: int) -> int:
	return c & 0x1F


## BEARTIME etc. call spread(), which may consume RNG: evaluate at use.
static func BEARTIME() -> int:
	return Misc.spread(3)


static func SLEEPTIME() -> int:
	return Misc.spread(5)


static func HOLDTIME() -> int:
	return Misc.spread(2)


static func WANDERTIME() -> int:
	return Misc.spread(70)


static func BEFORE() -> int:
	return Misc.spread(1)


static func AFTER() -> int:
	return Misc.spread(2)


## #ifdef MASTER: #define debug if (wizard) msg
static func debug(fmt: String, args: Array = []) -> void:
	if wizard:
		await Io.msg(fmt, args)


# =========================================================================
# main.c: rnd, roll (unqualified everywhere)
# =========================================================================

## rnd: pick a very random number. RN = ((seed = seed*11109+13849) >> 16) & 0xffff
static func rnd(range_: int) -> int:
	if range_ == 0:
		return 0
	seed_ = (seed_ * 11109 + 13849) & 0xFFFFFFFF
	return ((seed_ >> 16) & 0xFFFF) % absi(range_)


## The raw RN macro (rip.c uses it directly).
static func RN() -> int:
	seed_ = (seed_ * 11109 + 13849) & 0xFFFFFFFF
	return (seed_ >> 16) & 0xFFFF


## roll: roll a number of dice
static func roll(number: int, sides: int) -> int:
	var dtotal := 0
	while number > 0:
		number -= 1
		dtotal += rnd(sides) + 1
	return dtotal


# =========================================================================
# C library helpers (chars are ints, strings are Strings of codes 0..255)
# =========================================================================

## (char) v: C char is signed on x86
static func to_schar(v: int) -> int:
	v &= 0xFF
	return v - 256 if v >= 128 else v


## (short) v
static func to_short(v: int) -> int:
	v &= 0xFFFF
	return v - 65536 if v >= 32768 else v


static func isupper(c: int) -> bool:
	return c >= 65 and c <= 90


static func islower(c: int) -> bool:
	return c >= 97 and c <= 122


static func isalpha(c: int) -> bool:
	return isupper(c) or islower(c)


static func isdigit(c: int) -> bool:
	return c >= 48 and c <= 57


static func isalnum(c: int) -> bool:
	return isalpha(c) or isdigit(c)


static func isspace(c: int) -> bool:
	return c == 32 or (c >= 9 and c <= 13)


static func isprint(c: int) -> bool:
	return c >= 32 and c < 127


static func iscntrl(c: int) -> bool:
	return (c >= 0 and c < 32) or c == 127


static func toupper(c: int) -> int:
	return c - 32 if islower(c) else c


static func tolower(c: int) -> int:
	return c + 32 if isupper(c) else c


## The character at index i of a C string (0 past the end, like the NUL).
static func cat(s: String, i: int) -> int:
	return s.unicode_at(i) if i >= 0 and i < s.length() else 0


## A one-character string from a char code ("" for NUL, which ends a C string).
static func chr(c: int) -> String:
	return "" if (c & 0xFF) == 0 else char(c & 0xFF)


## atoi: optional whitespace, optional sign, digits.
static func atoi(s: String) -> int:
	var i := 0
	var n := s.length()
	while i < n and isspace(s.unicode_at(i)):
		i += 1
	var neg := false
	if i < n and (s.unicode_at(i) == 45 or s.unicode_at(i) == 43):
		neg = s.unicode_at(i) == 45
		i += 1
	var v := 0
	while i < n and isdigit(s.unicode_at(i)):
		v = v * 10 + (s.unicode_at(i) - 48)
		i += 1
	return -v if neg else v


## strchr(s, c) as an index, -1 for NULL.
static func strchr(s: String, c: int) -> int:
	return s.find(char(c))


## C sprintf for the conversions Rogue uses: %d %i %u %x %X %o %c %s %%,
## flags - 0 + space #, width/precision (number or *), length h hh l ll (ignored
## except h/hh truncation). %s of null prints "(null)" like glibc.
static func sprintf(fmt: String, args: Array = []) -> String:
	var out := ""
	var ai := 0
	var i := 0
	var n := fmt.length()
	while i < n:
		var c := fmt.unicode_at(i)
		if c != 37:
			out += char(c)
			i += 1
			continue
		i += 1
		if i >= n:
			break
		var left := false
		var zero := false
		var plus := false
		var space := false
		var alt := false
		while i < n:
			var f := fmt.unicode_at(i)
			if f == 45:
				left = true
			elif f == 48:
				zero = true
			elif f == 43:
				plus = true
			elif f == 32:
				space = true
			elif f == 35:
				alt = true
			else:
				break
			i += 1
		var width := -1
		if i < n and fmt.unicode_at(i) == 42:
			width = int(args[ai]) if ai < args.size() else 0
			ai += 1
			i += 1
			if width < 0:
				left = true
				width = -width
		else:
			while i < n and isdigit(fmt.unicode_at(i)):
				width = maxi(width, 0) * 10 + fmt.unicode_at(i) - 48
				i += 1
		var prec := -1
		if i < n and fmt.unicode_at(i) == 46:
			i += 1
			prec = 0
			if i < n and fmt.unicode_at(i) == 42:
				prec = int(args[ai]) if ai < args.size() else 0
				ai += 1
				i += 1
			else:
				while i < n and isdigit(fmt.unicode_at(i)):
					prec = prec * 10 + fmt.unicode_at(i) - 48
					i += 1
		var hcount := 0
		while i < n and "hlLqjzt".contains(char(fmt.unicode_at(i))):
			if fmt.unicode_at(i) == 104:
				hcount += 1
			i += 1
		if i >= n:
			break
		var conv := fmt.unicode_at(i)
		i += 1
		var s := ""
		var numeric := false
		var sign_ := ""
		match conv:
			37:	# %%
				out += "%"
				continue
			100, 105:	# d i
				var v := int(args[ai]) if ai < args.size() else 0
				ai += 1
				if hcount == 1:
					v = to_short(v)
				elif hcount >= 2:
					v = to_schar(v)
				else:
					v = _to_int32(v)
				numeric = true
				if v < 0:
					sign_ = "-"
					v = -v
				elif plus:
					sign_ = "+"
				elif space:
					sign_ = " "
				s = str(v)
			117, 120, 88, 111:	# u x X o
				var v := int(args[ai]) if ai < args.size() else 0
				ai += 1
				if hcount == 1:
					v &= 0xFFFF
				elif hcount >= 2:
					v &= 0xFF
				else:
					v &= 0xFFFFFFFF
				numeric = true
				if conv == 117:
					s = str(v)
				elif conv == 111:
					s = String.num_int64(v, 8)
					if alt and not s.begins_with("0"):
						s = "0" + s
				else:
					s = String.num_int64(v, 16, conv == 88)
					if alt and v != 0:
						sign_ = "0X" if conv == 88 else "0x"
			99:	# c
				var v := int(args[ai]) if ai < args.size() else 0
				ai += 1
				if (v & 0xFF) == 0:
					# a NUL ends the C string the caller uses
					if not left and width > 1:
						out += " ".repeat(width - 1)
					return out
				s = char(v & 0xFF)
			115:	# s
				var a: Variant = args[ai] if ai < args.size() else null
				ai += 1
				s = "(null)" if a == null else str(a)
				if prec >= 0 and s.length() > prec:
					s = s.substr(0, prec)
			_:
				continue
		if numeric:
			if prec >= 0:
				while s.length() < prec:
					s = "0" + s
				if prec == 0 and s == "0":
					s = ""
			var total_len := sign_.length() + s.length()
			if width > total_len:
				if left:
					s = sign_ + s + " ".repeat(width - total_len)
				elif zero and prec < 0:
					s = sign_ + "0".repeat(width - total_len) + s
				else:
					s = " ".repeat(width - total_len) + sign_ + s
			else:
				s = sign_ + s
		elif width > s.length():
			if left:
				s = s + " ".repeat(width - s.length())
			else:
				s = " ".repeat(width - s.length()) + s
		out += s
	return out


static func _to_int32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v >= 0x80000000 else v


# =========================================================================
# curses (stdscr shorthands and window functions on the emulation)
# =========================================================================

static var stdscr: Curses.CWindow:
	get:
		return cs.stdscr

static var curscr: Curses.CWindow:
	get:
		return cs.curscr


## initscr(): the emulation's screens already exist; nothing to do.
static func initscr() -> Curses.CWindow:
	return cs.stdscr


static func move(y: int, x: int) -> int:
	return cs.wmove(cs.stdscr, y, x)


static func addch(ch: int) -> int:
	return cs.waddch(cs.stdscr, ch)


static func mvaddch(y: int, x: int, ch: int) -> int:
	return cs.mvwaddch(cs.stdscr, y, x, ch)


static func addstr(s: String) -> int:
	return cs.waddstr(cs.stdscr, s)


static func mvaddstr(y: int, x: int, s: String) -> int:
	return cs.mvwaddstr(cs.stdscr, y, x, s)


static func printw(fmt: String, args: Array = []) -> int:
	return cs.waddstr(cs.stdscr, sprintf(fmt, args))


static func mvprintw(y: int, x: int, fmt: String, args: Array = []) -> int:
	if cs.wmove(cs.stdscr, y, x) == ERR:
		return ERR
	return cs.waddstr(cs.stdscr, sprintf(fmt, args))


static func clrtoeol() -> int:
	return cs.wclrtoeol(cs.stdscr)


static func clear() -> int:
	return cs.wclear(cs.stdscr)


static func refresh() -> int:
	return cs.wrefresh(cs.stdscr)


static func standout() -> int:
	return cs.wstandout(cs.stdscr)


static func standend() -> int:
	return cs.wstandend(cs.stdscr)


static func inch() -> int:
	return cs.winch(cs.stdscr)


static func mvinch(y: int, x: int) -> int:
	return cs.mvwinch(cs.stdscr, y, x)


static func wmove(win: Curses.CWindow, y: int, x: int) -> int:
	return cs.wmove(win, y, x)


static func waddch(win: Curses.CWindow, ch: int) -> int:
	return cs.waddch(win, ch)


static func mvwaddch(win: Curses.CWindow, y: int, x: int, ch: int) -> int:
	return cs.mvwaddch(win, y, x, ch)


static func waddstr(win: Curses.CWindow, s: String) -> int:
	return cs.waddstr(win, s)


static func mvwaddstr(win: Curses.CWindow, y: int, x: int, s: String) -> int:
	return cs.mvwaddstr(win, y, x, s)


static func wprintw(win: Curses.CWindow, fmt: String, args: Array = []) -> int:
	return cs.waddstr(win, sprintf(fmt, args))


static func mvwprintw(win: Curses.CWindow, y: int, x: int, fmt: String, args: Array = []) -> int:
	if cs.wmove(win, y, x) == ERR:
		return ERR
	return cs.waddstr(win, sprintf(fmt, args))


static func wclrtoeol(win: Curses.CWindow) -> int:
	return cs.wclrtoeol(win)


static func wclear(win: Curses.CWindow) -> int:
	return cs.wclear(win)


static func werase(win: Curses.CWindow) -> int:
	return cs.werase(win)


static func wrefresh(win: Curses.CWindow) -> int:
	return cs.wrefresh(win)


static func touchwin(win: Curses.CWindow) -> int:
	return cs.touchwin(win)


static func clearok(win: Curses.CWindow, bf: bool) -> int:
	return cs.clearok(win, bf)


static func leaveok(win: Curses.CWindow, bf: bool) -> int:
	return cs.leaveok(win, bf)


static func idlok(win: Curses.CWindow, bf: bool) -> int:
	return cs.idlok(win, bf)


static func keypad(win: Curses.CWindow, bf: bool) -> int:
	return cs.keypad(win, bf)


static func newwin(nlines: int, ncols: int, begy: int, begx: int) -> Curses.CWindow:
	return cs.newwin(nlines, ncols, begy, begx)


static func subwin(orig: Curses.CWindow, nlines: int, ncols: int, begy: int, begx: int) -> Curses.CWindow:
	return cs.subwin(orig, nlines, ncols, begy, begx)


static func delwin(win: Curses.CWindow) -> int:
	return cs.delwin(win)


static func mvwin(win: Curses.CWindow, y: int, x: int) -> int:
	return cs.mvwin(win, y, x)


static func winch(win: Curses.CWindow) -> int:
	return cs.winch(win)


static func mvwinch(win: Curses.CWindow, y: int, x: int) -> int:
	return cs.mvwinch(win, y, x)


static func wstandout(win: Curses.CWindow) -> int:
	return cs.wstandout(win)


static func wstandend(win: Curses.CWindow) -> int:
	return cs.wstandend(win)


## getyx(win, y, x) is a macro: y = getcury(win); x = getcurx(win)
static func getcury(win: Curses.CWindow) -> int:
	return cs.getcury(win)


static func getmaxy(win: Curses.CWindow) -> int:
	return cs.getmaxy(win)


static func getmaxx(win: Curses.CWindow) -> int:
	return cs.getmaxx(win)


static func getcurx(win: Curses.CWindow) -> int:
	return cs.getcurx(win)


static func endwin() -> int:
	return cs.endwin()


static func isendwin() -> bool:
	return cs.isendwin()


static func flushinp() -> int:
	return cs.flushinp()


static func raw() -> int:
	return cs.raw()


static func noecho() -> int:
	return cs.noecho()


static func nocbreak() -> int:
	return cs.nocbreak()


static func halfdelay(tenths: int) -> int:
	return cs.halfdelay(tenths)


static func baudrate() -> int:
	return cs.baudrate()


static func erasechar() -> int:
	return cs.erasechar()


static func killchar() -> int:
	return cs.killchar()


static func unctrl(c: int) -> String:
	return Curses.unctrl(c)


## mvcur only moves the physical cursor (before endwin / exit): no-op
## mvcur: ncurses writes the cheapest cursor motion for the terminal (xterm)
## straight to stdout with putchar, so the bytes are part of the output. The
## only reachable call, (0, COLS-1) -> (LINES-1, 0) in save_file, is CR + VPA.
static func mvcur(oldrow: int, oldcol: int, newrow: int, newcol: int) -> int:
	if oldrow == newrow and oldcol == newcol:
		return OK
	if newcol == 0 and newrow != oldrow:
		cs.stdout_write("\r\u001b[%dd" % (newrow + 1))
	else:
		cs.stdout_write("\u001b[%d;%dH" % [newrow + 1, newcol + 1])
	return OK


## getch() = wgetch(stdscr): a coroutine, always await it
static func getch() -> int:
	return await cs.wgetch(cs.stdscr)


static func wgetch(win: Curses.CWindow) -> int:
	return await cs.wgetch(win)


## wgetnstr(win, buf, n): returns the string read
static func wgetnstr(win: Curses.CWindow, n: int) -> String:
	return await cs.wgetnstr(win, n)


## printf / putchar / fputs to stdout
static func printf(fmt: String, args: Array = []) -> void:
	cs.stdout_write(sprintf(fmt, args))


static func putchar(c: int) -> void:
	cs.stdout_write(char(c & 0xFF))


## fgets(buf, size, stdin): returns the line read
static func fgets_stdin(size: int) -> String:
	return await cs.read_line(size)


## exit(status): ends the program. The coroutine stack is abandoned.
static func exit(status: int) -> void:
	await cs.exit_program(status)


## abort(): the C process dies with SIGABRT.
static func abort() -> void:
	await cs.exit_program(134)


# =========================================================================
# translation placeholders (tools/gen_stubs.py)
# =========================================================================

## A stub of a blocking (coroutine) function.
static func _todo(name: String) -> void:
	push_error("not yet translated: " + name)
	if false:
		await cs._halt


## A stub of a non-blocking function.
static func _todo_sync(name: String) -> void:
	push_error("not yet translated: " + name)
