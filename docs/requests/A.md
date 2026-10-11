# Requests from translation group A

Foundation changes needed, UB found, and notes for the lead.

Files: `rooms.gd`, `passages.gd`, `new_level.gd`, `init.gd`.

## Foundation changes needed

None. Every static these files need was already in RogueBase. There are no `# REQUEST`
temporaries in group A's files.

**Follow-up for group B's `move.gd`.** Its `# REQUEST` temporaries `_rainbow` and
`_cNCOLORS` (used by `be_trapped` T_MYST) can now become `Init.rainbow` and
`Init.cNCOLORS`. I checked that the 27 strings are identical and in the same order.

## Statics that the port does not keep (decisions)

- **rooms.c `static SPOT maze[NUMLINES/3+1][NUMCOLS/3+1]`: dropped.** It is write-only:
  - `do_maze()` sets every `used = FALSE` and `nexits = 0`.
  - `accnt_maze()` is the only other user. It scans `exits[0 .. nexits-1]`, a loop that
    never runs because `nexits` is always 0, and then stores `(ny, nx)` into `exits[0]`.
  - Nothing ever reads `used` or `exits`, and the indices stay in bounds
    (`y <= Maxy <= 7`, `x <= Maxx <= 25`).

  So `Rooms.accnt_maze()` is an empty function with the C body in its comment, and
  `do_maze()`'s reset loop is a comment. Neither has any effect on the map, the screen or
  the RNG.
- **passages.c `static struct rdes rdes[MAXROOMS]`: a fresh local copy per call.**
  - `do_passages()` builds the copy from the inner class `Passages.Rdes` and the const
    `Passages._rdes_conn`.
  - `conn[]` is never modified.
  - `isconn[]` and `ingraph` are re-initialized at the top of every `do_passages()` call,
    before anything reads them.
  - `r1 - rdes` becomes `rdes.find(r1)`.

## Tables exported by `Init` (for move.c, save/restore and others)

- `Init.rainbow`, `Init.sylls`, `Init.wood` and `Init.metal` are `const Array[String]`.
- `Init.stones` is a `const Array[Dictionary]` of `{"st_name": ..., "st_value": ...}`.
  - `Init.stones[j].st_name` and `.st_value` read as in C.
  - A const cannot hold `Stone` objects, so `types/stone.gd` is unused.
- The counts are `Init.NCOLORS`/`cNCOLORS` (27), `NSTONES`/`cNSTONES` (26),
  `NWOOD`/`cNWOOD` (33), `NMETAL`/`cNMETAL` (22) and `NSYLLS` (147).
- `p_colors[]`, `r_stones[]` and `ws_made[]` hold the table strings themselves, so the
  value-based save in `save.gd` is enough.
  - If indices are ever needed, use `Init.rainbow.find(...)` and similar.
  - "gold", "silver", "topaz" and "turquoise" each appear in two different tables.

## Signatures other groups call

| Function | Notes |
|---|---|
| `Rooms.find_floor(rp: Room, cp: Coord, limit: int, monst: bool) -> bool` | `*cp` holds the last square tried, also when it fails, so pass the persistent Coord. A bool `false` for `limit` converts fine. |
| `Rooms.rnd_pos(rp: Room, cp: Coord)` | |
| `Rooms.enter_room(cp: Coord)` | Coroutine. |
| `Rooms.leave_room(cp: Coord)` | Coroutine. |
| `NewLevel.rnd_room() -> int` | |
| `NewLevel.new_level()` | Coroutine. |
| `Init.pick_color(col: String) -> String` | |
| `Init.sumprobs(info: Array[ObjInfo], bound: int, name: String = "")` | `name` is the MASTER-only third C parameter. |
| `Init.badcheck(name: String, info: Array[ObjInfo], bound: int)` | Uses `push_error` instead of `printf` plus `getchar()` (port_nonblocking). It never fires: every table sums to 100. |
| `Passages.add_pass()` | MASTER wizard command, not a coroutine. |

## A real hang in the original, reproduced by the port (needs a harness decision)

`conn()` picks a door square for a maze room with
`do { spos.x = ... + rnd(r_max.x - 2) + 1; } while (ISMAZE && !(flat(spos) & F_PASS))`.
This loop can never end, as follows:

- A maze in the top row has `r_pos.y == 1` and `r_max.y == 6`.
- Its cells go down to `y = 7`, one row below its box, because `dig()` allows
  `newy == Maxy`.
- Its "bottom wall" door row is `y = 6` (maze row offset 5). That row has `F_PASS` only
  where a vertical link joins cell rows 5 and 7.
- If every such link is at x offset 0 or 24, the `rnd(23) + 1` draw (offsets 1..23)
  never lands on one. The loop then spins forever.

The port hangs at exactly the same point.

- **Real oracle repro.** Run the MASTER oracle with seed 1659 and keys `4 4 4 4` (four
  `^D`). It hangs generating level 5 in `conn(5, 2)` at passages.c:178 (gdb backtrace
  taken).
  - `difftest.py one --master --arg "" --seed 1659 --keys "4 4 4 27"` is identical up to
    that point.
- **How common it is.** With 40 × `^D` in wizard mode, 7 of 3000 seeds hang: 1083, 1344,
  1438, 1457, 1632, 1659 and 1786.
- **Effect on testing.** Any test that generates many levels can hit it: the MASTER
  "`^D` to every depth" scenarios and the explorer bot. The oracle then times out
  (`run_oracle` uses 60 s), and so does the port.
- **Suggestion.** Treat "both time out" as a match, or skip those seeds. Otherwise, list it
  in FIDELITY.md as a known quirk kept on purpose.
  - Fixing it would be a deliberate deviation that the oracle patch would also need.

## UB / hazards found (not reachable in practice; no oracle change proposed)

- **`numpass()` writes `passages[pnum].r_exit[r_nexits++]` with no bound.**
  - The C would overrun the 12-entry `r_exit[]` into the next `struct room`.
  - The port would fail with an Array index error instead.
  - It needs one passage group with more than 12 doors or secret doors. A level has at
    most 8 + 4 corridors. The most I saw on one passage was 6 exits, over 1664 levels.
- **`leave_room()`: `proom = &passages[flat(y,x) & F_PNUM]`.** The index can be 0..15, but
  only `passages[0..12]` exists.
  - Passage numbers are at most 12, because there are at most 12 corridors.
  - Trap squares hold a trap type of 0..7 in the same bits.
  - So the C never reads past the array.
- **`conn()`'s "warning, connectivity problem on this level" `msg()` is translated, but
  appears unreachable.**
  - A room's bottom or right wall is at least 2 squares from the next row or column's
    rooms, so `distance >= 1`, and the turn always happens.
  - None of 1501 seeds × 30 levels triggered it.

## Notes

- **Recursion.** `numpass()` recurses once per numbered square, at most a few hundred deep
  even with mazes. `dig()` recurses at most 52 deep (one level per maze cell).
  - I measured this build's GDScript call-stack limit at about 2048 frames, so this is
    fine.
- **Verification done (in scratch copies; nothing from it is committed).**
  1. **Stub harness.**
     - Setup: I compiled the oracle-patched `rooms.c`, `passages.c`, `new_level.c`,
       `init.c`, `list.c` and `extern.c` with identical C and GDScript stubs for the
       other groups' functions, and real ncurses on the C side.
     - What was compared: the seed, the full `places[]`, rooms, passages, objects,
       monsters, stdscr cells and cursor.
     - When: after init and after every `new_level()`.
     - Runs, all with 0 diffs:
       - 51 seeds × (30 levels + 3 back up), with SEEMONST, ISBLIND and amulet variants
         (seed 42 hangs in both, as described above);
       - 41 seeds × 30 levels with `leave_room` + `enter_room` after each level;
       - 31 seeds × 30 levels lighting dark rooms and then leaving them (584 dark-room
         FLOOR blankings);
       - 26 seeds × 30 levels with `add_pass`.
     - Coverage: 689 maze rooms, 2465 gone rooms, about 4000 secret-door squares and
       about 5700 hidden-passage squares.
  2. **Real C oracle (`harness/difftest.py`).** These runs used the current working copy
     of every group's modules, in an isolated copy of the project.
     - `seeds`: 440 standard and 50 MASTER first screens, all identical.
     - `fuzz`: 30 standard and 20 MASTER games of 400 keys each, all identical.
