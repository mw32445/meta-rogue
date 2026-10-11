# Verification record

How the port was shown to be 1:1 with Rogue 5.4.4, and what the tests do and do not
reach. `docs/ARCHITECTURE.md` §8 describes the tools; `harness/run_all.sh` reruns the
standard suite.

## Method
- **The reference is the original C code**, built with `oracle.patch`, which applies
  the documented fixes for undefined behavior (`docs/FIDELITY.md`). It is linked with
  hooks that script the keyboard and pin the environment.
- **Both programs get the same seed and keys.** Both write a step log at every keyboard
  read: the key, the RNG state, the cursor, a hash of all 1,920 screen cells, and a hash
  of a game-state digest (player, pack, monsters, objects, daemons).
- **Stdout is compared byte for byte** (the top-ten list, `Hello ...`, `mvcur`
  bytes), as is the exit status.
- **One run is a whole game, or a chain of games** (save, then restore with `-r`).
- **Every batch runs dozens of games in one Godot process**, so every batch also checks
  that `RogueBase.reset()` starts each game from a clean state.

## Final sweep (at the final code)
SWEEP_TABLE

Before the final sweep, the same generators had run several thousand games during
development. The divergences they found were fixed in the port, or, for undefined C
behavior, decided in `docs/FIDELITY.md`. Each now has a script in `harness/corpus/`:
- wizard-created objects of an unknown kind or type;
- an attack on an empty square (a C crash);
- the `conn()` hang;
- the circular object list.

The curses emulation was checked separately against real ncurses: 10,000 out of 10,000
random scripts were identical.

## Coverage of the original C
Line coverage measured with gcov, from the standard and wizard (MASTER) builds
together. The inputs were the corpus, the random games, the save chains, the bot games
and the group D item scenarios (`harness/coverage.py`).

COVERAGE_TABLE

### The lines no test reaches (reviewed by hand)
**Unreachable by construction** (about 60% of the uncovered lines):
- **Signal handlers and terminal handling.** These need signals the tests do not send:
  - `main.c`: `endit`, `fatal`, `tstp`, `leave`;
  - `save.c`: `auto_save` (in the port, the window-close handler calls it, and
    `godot/tests/ui_autosave.gd` tests that).
- **Environment checks that the pinned environment never triggers:**
  - the screen-size check;
  - the slow-terminal defaults (baud rate ≤ 1200);
  - the `SEED` variable;
  - failure to open the score file;
  - the score-lock contention loop in `lock_sc`.
- **Consistency checks that never fire:**
  - `badcheck`, the `pick_one` and `new_thing` errors;
  - "ran out of memory" and "Ran out of fuse slots";
  - "in some bizarre place";
  - "what a puzzling scroll" and "what a bizarre schtick" for nonexistent kinds.
- **`add_pass` (wizard `^C`):** `readchar()` turns `^C` into the quit prompt before the
  command dispatcher sees it.
- **Code for `allscore` off:** the configure script defines `ALLSCORES`.
- **`state.c` paths that never run:**
  - read and write error returns;
  - the byte swapping for big-endian machines;
  - helper functions the save format never calls (`rs_write_shorts`, `rs_read_ushort`,
    `rs_read_string(s)`, `rs_*_thing_references`);
  - the `t_dest` encoding for a monster chasing a monster (monsters only target the hero,
    objects and room gold).
- **Restore failures:** a save file from another version, another screen size, a linked
  file, a dead hero.

**Crash paths** (C dereferences NULL right after the message): `runto`'s "couldn't
find monster" and `find_obj`'s "Non-object". The tests reach the one through `fight()`
(see FIDELITY).

**Reachable but rare**, and not reached by the tests. Each is a short branch next to
code the tests run:
- thrown objects that finish a pending hit message;
- a few trap and monster-attack variants: an arrow trap killing the hero, a dart trap
  without sustain strength, a vampire draining the last level;
- removing a worn ring of add-strength or see-invisible by dropping it;
- `inven=~/path` in ROGUEOPTS;
- the "s" plural of a create-monster scroll that makes no monster;
- a stick used when too weak;
- a wizard teleport while held by a flytrap.
