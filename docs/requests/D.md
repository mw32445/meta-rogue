# Requests from translation group D

Foundation changes needed, UB found, and notes for the lead.

Files: `potions.gd`, `scrolls.gd`, `sticks.gd`, `daemons.gd` (potions.c, scrolls.c,
sticks.c, daemons.c).

## Foundation changes needed

None. Every piece of state these files use already exists in RogueBase:
`_read_scroll_mp`, `_do_zap_bolt`, `_fire_bolt_pos`, `_fire_bolt_spotpos`, `between`,
`prbuf`, `seenstairs`, `fruit` and the `*_info` tables. There are no `# REQUEST`
temporaries in group D's files.

## How C statics and tables were mapped

- **potions.c `static PACT p_actions[]`** is a module `const` (an `Array[Dictionary]`).
  - `pa_daemon` holds a `D_*` id, or `&""` for NULL.
  - The P_SEEINVIS entry's `pa_high` and `pa_straight` point at the global `prbuf` in C.
    `quaff()` writes `prbuf` just before calling `do_pot()`. The port stores the marker
    `PA_PRBUF` there instead, and `_pa_str()` dereferences it when `do_pot` builds its
    `msg()` argument, after `look(FALSE)`, which is when C reads it too.
- **scrolls.c `static char id_type[]`** is a local `const` inside its case.
- **sticks.c `static THING *drainee[40]`** is a local `Array[Thing]`. It is filled before it
  is read on every call, and the NULL terminator becomes the array's end.
- **sticks.c `static char buf[20]` in `charge_str`**: the function returns the String.
- **sticks.c `static coord pos`, `static coord spotpos[BOLT_LENGTH]`, and do_zap's
  `static THING bolt`** use the RogueBase objects.
  - Because do_zap's bolt is persistent, its `o_launch` from an earlier zap is kept.
  - Its zero `o_damage` is kept too: magic missile with no weapon always misses.
- **`THING bolt` in `fire_bolt`** is zero-filled with `o_launch = -1`, per FIDELITY.md.

## Undefined behavior found (not yet in docs/FIDELITY.md)

1. **scrolls.c `read_scroll()` S_CREATE, `find_obj(y, x)->o_which`.**
   - Suppose a xeroc disguised as a scroll (`t_disguise == '?'`) is next to the hero.
     `winat()` returns `'?'`, but there is no object on that square.
   - `find_obj()` then returns NULL, and C dereferences it. The program crashes; the MASTER
     build prints "Non-object y,x" first.
   - The port is literal: `Misc.find_obj()` returns null and `.o_which` raises a GDScript
     error at the same point (scrolls.gd:93).
   - You may want a FIDELITY entry, or the test generator should avoid this case.
2. **sticks.c `drain()`: `drainee[40]` can overflow.**
   - With 40 or more monsters in the hero's room or passage, `*dp++ = mp` and `*dp = NULL`
     write past the static array.
   - The port's array has no limit, so it does not overflow.
   - This is practically unreachable.
3. **sticks.c `fire_bolt()`: a pointer before the array.**
   - If the bolt bounces on its very first step, `c1--` points before `spotpos[0]`.
   - This is UB pointer arithmetic, but it is never dereferenced: the loop's `c1++`
     restores it.
   - The port uses an index (-1, then 0). There is no behavioral difference.
4. **Not UB but worth knowing: raise level at s_lvl 21.**
   - `potions.c raise_level()` reads `e_levels[s_lvl-1]`. `check_level()` caps `s_lvl` at
     21, so the read is always in bounds.
   - At level 21, `e_levels[20] == 0`, so `s_exp` becomes 1 and `check_level()` drops the
     hero to level 1.
   - This is kept literally.

The unsequenced `ring_eat(LEFT) + ring_eat(RIGHT)` in `stomach()` is already in
FIDELITY.md. The port evaluates LEFT, then RIGHT, into two temporaries
(daemons.gd:122-124). I verified this against the oracle with a search ring on the left
and a see-invisible ring on the right; both draw RNG in `ring_eat`.

## Interfaces (for other groups)

Functions marked coroutine are awaited by callers; all others are plain functions.

- **Potions**
  - `quaff()` (coroutine)
  - `is_magic(obj: Thing) -> bool`
  - `invis_on()`
  - `turn_see(turn_off: bool) -> bool`
  - `seen_stairs() -> bool`
  - `raise_level()` (coroutine)
  - `do_pot(type_: int, knowit: bool)` (coroutine)
- **Scrolls**
  - `read_scroll()` (coroutine)
  - `uncurse(obj: Thing)`
- **Sticks**
  - `fix_stick(cur: Thing)`
  - `do_zap()` (coroutine)
  - `drain()` (coroutine)
  - `fire_bolt(start: Coord, dir: Coord, name: String)` (coroutine)
    - `dir` is negated in place on bounces, so pass the global `delta`.
    - `start` is compared by identity with `hero`, so pass `hero` or `th.t_pos`, never a
      copy.
  - `charge_str(obj: Thing) -> String`
- **Daemons**: every function is `(_arg: int = 0) -> void`.
  - Coroutines: `rollwand`, `unconfuse`, `sight`, `nohaste`, `stomach`, `come_down`,
    `land`.
  - Plain functions: `doctor`, `swander`, `unsee`, `visuals`.

Calls into other modules assume these signatures, all of which match the current tree:
- `Misc.add_str(sp: int, amt: int) -> int` (the coordinator's contract).
- `Misc.call_it(info: ObjInfo)`.
- `Rooms.find_floor(rp, cp, limit: int, monst: bool)`. C's `FALSE` limit is passed as `0`.

## Verification done

**Compile and lint.** `tools/check.sh --quick` reports compile OK and lint 0 problems.
The files also compile against the whole current working tree: 50+ scripts, 0 failed.

**Differential tests against the C oracle.** These ran the MASTER build with wizard-mode
key scripts. The port ran from an isolated copy of the tree, never from the shared
project. Results: **188 targeted runs, 179,625 steps, all identical.** They covered:
- every potion, scroll and wand type
- potion combinations:
  - the `lengthen` paths
  - LSD with monster detection
  - restore with add-strength rings on both hands
  - extra healing at full HP
- hunger with two regeneration rings, through fainting and starvation
- 850-turn fuses (`come_down`, `sight`, `unsee`, `land`)
- magic mapping on levels 3-23 (secret doors, hidden corridors, traps, `goto def/pass`)
- run-to-door followed by zaps, which reaches the `goto def` door bounce
- dragons at level 28+:
  - dragon breath is `fire_bolt` from a monster
  - "the flame bounces off the dragon"
- terse mode

**Random fuzz.** I also ran `difftest` fuzz: 60 standard runs and 40 MASTER runs. All
were identical except one, which diverged in the save path while save.gd was still a stub.

**Line coverage.** I measured it with a private MASTER+gcov oracle:

| File | Lines covered |
|---|---|
| potions.c | 175/188 |
| scrolls.c | 165/174 |
| sticks.c | 232/249 |
| daemons.c | 122/132 |

The rest are:
- terse, error and MASTER-default messages
- the `find_obj` NULL path
- `unsee` and `come_down` with invisible monsters in view
- `seen_stairs`' monster-on-the-stairs cases

**Reproducing.** The key-script generators (`gen3.py`..`gen7.py`) and the wrapper `dt.py`,
which runs `harness/difftest.py` against an isolated project copy, are in the session
scratchpad under `groupD_dt/`.
