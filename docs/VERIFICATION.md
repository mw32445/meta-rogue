# Verification record

How the port was shown to be 1:1 with Rogue 5.4.4, and what the tests do and do not
reach. `docs/ARCHITECTURE.md` §9 describes the tools; `harness/run_all.sh` reruns the
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
**5,029 runs, 0 divergences.** About 4.3 million keystrokes were compared, each with its
screen, cursor, RNG state and game-state digest; stdout and exit status were compared
for every run.

| Batch | Runs | Keys per run | Result |
|---|---|---|---|
| Regression corpus: fixed bugs, wins, deaths, score files, rings, full/empty pack, `-s`, `-d`, hangs | 29 | 2–6,000 | 29/29 identical |
| Level generation (first screen of each seed) | 1,000 | 1 | 1,000/1,000 |
| Random games, default options | 1,700 | 1,000 | 1,700/1,700 |
| Random games, wizard mode (MASTER build: `^D`/`^A` levels, creating every kind of object, `^I`, teleport, maps, ...) | 1,000 | 1,500 | 1,000/1,000 |
| Save/restore chains (play, save, restore with `-r`, play, save, restore, play) | 500 | 3 × up to 500 | 500/500 |
| Wizard save/restore chains (a potion of each kind first, so every daemon and fuse goes through save/restore, then deeper levels) | 300 | 3 × up to 600 | 300/300 |
| ROGUEOPTS matrix: `terse,jump,flush,passgo` / `noseefloor,notombstone,inven=overwrite` / `inven=slow,name=Gandalf,fruit=kiwi` / `inven=clear,terse,noseefloor,nojump` / `passgo,jump,inven=slow,notombstone` | 5 × 100 | 700 | 500/500 |

The explorer bot's long games (normal play; wizard play up to level 25, including wins)
were also compared and were identical.

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

| File | Lines | Covered | | File | Lines | Covered |
|---|---|---|---|---|---|---|
| armor.c | 43 | 97.7% | | new_level.c | 105 | 99.0% |
| chase.c | 249 | 94.4% | | options.c | 225 | 96.9% |
| command.c | 508 | 97.6% | | pack.c | 248 | 93.1% |
| daemon.c | 57 | 93.0% | | passages.c | 199 | 87.9% |
| daemons.c | 132 | 93.9% | | potions.c | 188 | 95.7% |
| fight.c | 357 | 90.8% | | rings.c | 93 | 92.5% |
| init.c | 129 | 93.8% | | rip.c | 253 | 94.1% |
| io.c | 111 | 100.0% | | rooms.c | 225 | 96.4% |
| list.c | 39 | 97.4% | | save.c | 190 | 82.1% |
| main.c | 181 | 71.8% | | scrolls.c | 174 | 96.0% |
| mach_dep.c | 82 | 62.2% | | state.c | 1,211 | 81.7% |
| misc.c | 300 | 95.3% | | sticks.c | 249 | 95.6% |
| monsters.c | 118 | 94.9% | | things.c | 415 | 95.7% |
| move.c | 229 | 95.2% | | weapons.c | 110 | 96.4% |
| | | | | wizard.c | 139 | 92.8% |

**Game logic in total: 5,972 of 6,559 lines (91.1%).** Of the 587 lines not run, about
350 cannot run under any input the game accepts (listed below). Coverage of the
reachable lines is therefore about 96%. `mdport.c` (portability) and `xcrypt.c` (the
wizard password's DES) are not counted.

Reproduce with `python3 harness/coverage.py --reset harness/corpus <key dirs>`; use
`--uncovered FILE` to list a file's lines.

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
