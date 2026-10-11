# Requests from translation group B

Foundation changes needed, UB found, and notes for the lead.

Files: `monsters.gd`, `chase.gd`, `fight.gd`, `move.gd` (monsters.c, chase.c, fight.c,
move.c).

## Requests

1. **`rainbow[]` / `cNCOLORS` (init.c, `extern` in rogue.h:746-747)**: move.c
   `be_trapped()` (T_MYST) uses them. At HEAD, init.gd is a stub, so the isolated check
   cannot see them. `move.gd` has temporary copies, `Move._rainbow` and `Move._cNCOLORS`,
   marked `# REQUEST`. Group A's working copy of init.gd defines `const rainbow` and
   `const cNCOLORS`. Once that lands, replace the four `_rainbow[rnd(_cNCOLORS)]` in
   `Move.be_trapped` with `Init.rainbow[rnd(Init.cNCOLORS)]` and delete the two
   constants. Moving them to RogueBase works too. The underscore names cannot clash with
   a RogueBase member.

No other foundation changes needed. All statics used are already in RogueBase:
`_chase_ch_ret`, `_runners_orig_pos`, `_do_chase_this`, `_chase_tryp`, `_cansee_tp`,
`_wanderer_cp`, `_rndmove_ret`, `nh`.

## Signatures other groups call (C types kept)

- `Fight.fight(mp: Coord, weap: Thing, thrown: bool) -> int` returns `int(did_hit)`,
  so weapons.c `hit_monster` can return it.
- `Monsters.save(which) -> int`, `Monsters.save_throw(which, tp) -> int` and
  `Fight.swing(...) -> int` return 0/1.
- `Fight.roll_em` is a coroutine (MASTER `debug`). `Chase.see_monst`, `Chase.cansee`,
  `Chase.diag_ok`, `Chase.chase` and `Move.turn_ok` return `bool`.
- `Move.be_trapped(tc) -> int` returns the trap type.
- `Fight.set_mname(tp) -> String` and `Fight.prname(mname: Variant, upper) -> String`
  return the C static buffer `tbuf` as a String.
- `Fight.hit(er, ee, noend)` and `Fight.miss(er, ee, noend)` take `Variant`
  (`null` is C NULL). `thunk`/`bounce` take `mname: String`.
- `Chase.find_dest(tp) -> Coord` and `Move.rndmove(who) -> Coord` return references:
  `hero`, `obj.o_pos` or the static `_rndmove_ret`. Callers copy `rndmove`'s result.
- `Chase.runners(_arg: int = 0)` is the daemon. `Chase.roomin` and `Chase.runto` are
  not coroutines (port_nonblocking).

## Notes / deviations

- `Chase.roomin`: in a MASTER build, C calls `abort()` after the "bizarre place"
  message; the port only does `push_error` + `return null` (port_nonblocking).
  - Also, `cansee()` does not dereference roomin's NULL: it compares it with `proom`.
    So in C this message would show on screen rather than crash.
  - I believe it is unreachable: every coordinate `cansee()` gets is a room or passage
    square.
- `Chase.runto` and `Fight.fight` (MASTER): the "no monster" message is followed by a
  NULL dereference, in C and in the port alike. runto uses `push_error`; fight uses
  `await debug(...)`, as C does.
- `Monsters.wake_monster` (non-MASTER, no monster): `endwin(), abort();` becomes
  `endwin()` + `await abort()`.
- `Monsters.wanderer` calls `Rooms.find_floor(null, _wanderer_cp, false, true)` with
  FALSE for the int `limit`, as in C. GDScript converts bool to int.
- Original bugs kept:
  - `relocate()` reads `oroom` after updating `t_room`.
  - `find_dest()` reuses `tp` as the inner loop variable.
  - "frozen by the the ice monster" (`" by the %s"` with a `set_mname` result).
  - The flytrap's `"%dx1"` only affects monsters created later.
  - `do_move` recomputes `proom = roomin(&hero)` from the *old* position.
- gotos:
  - do_move `over`: a loop, with the backward jump entering the else branch and skipping
    `rnd(5)`.
  - do_move `hit_bound` and `move_stuff`: state flags.
  - do_chase `over`: a loop that keeps `mindist`.
  - rndmove `bad`: a flag.

## UB found

None beyond what docs/FIDELITY.md already covers:
- `runners()` with monsters freed mid-loop.
- A nymph stealing one item of a stack: `leave_pack()` keeps the node in the pack, then
  `discard()`. The port's `List.discard` is a no-op, as the policy says.
- Uninitialized reads that are not UB:
  - do_move's `ch`/`fl` on the `goto hit_bound` path are never read.
  - do_chase's static `this` is zero-initialized, and the port keeps it persistent.

## Verification done

A scratch differential harness compared the original C against the port and found **0
differing lines** out of 1158, covering RNG state, a screen hash, the cursor, the
message line and monster state.
- **Setup.** The original monsters.c, chase.c, fight.c and move.c were linked with
  io.c, list.c, daemon.c, extern.c and real ncurses. The other modules were replaced
  by identical stubs on both sides. Both ran 10 scenario sections on a synthetic
  two-room level.
- **Sections:**
  - randmonster, new_monster for all 26 monsters (levels 1 and 30) and give_pack
  - every roll_em weapon/ring/armor path, save/save_throw, set_mname, prname and swing
  - runners/do_chase/chase across doors and passages, with objects picked up and a
    dragon flame; relocate
  - fight: xeroc, thrown weapons, CANHUH, terse, to_death
  - attack for L, N, I, R, W, V, A, F and H, and killed (including the leprechaun's gold
    falling into `r_gold`)
  - do_move: walls, confusion, every trap, a hidden trap, levitation, passgo corridor
    turns, held moves, stairs/take, leave_room
  - wake_monster (medusa fuse/lengthen), door_open, see_monst, cansee, set_oldch
  - wanderer, hasted/slowed/confused runners, ISTARGET bookkeeping, a theft inside
    runners
- **Not covered:** MASTER-only paths.
