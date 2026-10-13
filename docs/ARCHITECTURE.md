# Architecture of the Godot port

The port is a statement-by-statement translation of Rogue 5.4.4 (C, curses) into
GDScript for Godot 4.7. Given the same seed and keystrokes, it shows the same screens
(characters, standout, cursor) and consumes the same random numbers as the original.
This is checked against the original C program, built as a reference "oracle", at
every keyboard read.

## 1. Layout
| Path | What |
|---|---|
| `godot/project.godot`, `godot/main.tscn` | The Godot 4.7 project; the main scene is the playable game. |
| `godot/rogue/*.gd` | The game: one module per C file (`fight.c` → `fight.gd`, `class_name Fight`). |
| `godot/rogue/rogue_base.gd` | `RogueBase`: rogue.h/extern.h constants, macros, **all** mutable state, C helpers, curses wrappers, the RNG. Every module `extends RogueBase`. |
| `godot/rogue/types/*.gd` | `Thing`, `Coord`, `Room`, `Stats`, `Place`, `ObjInfo`, `Monster`, `DelayedAction`, ... (C structs as reference types). |
| `godot/curses/curses.gd` | `Curses`: an exact emulation of the ncurses 6.4 subset Rogue uses, plus the key queue and the stdout byte stream. |
| `godot/ui/` | `TerminalView` (draws the screen, maps keys), `main.gd` (runs games), `video_settings.gd` and `settings_screen.gd` (the video settings, F10). |
| `godot/guild/` | The Fighters' Guild, behind the switch `guild` (section 7): the shop before each new game, its catalog, and the loadout it applies (`docs/GUILD.md`). |
| `godot/tests/` | `replay.gd` (the step-log runner), `check_all.gd`, `curses_fuzz.gd`, `ui_screenshot.gd`, Phase 0 spikes. |
| `harness/oracle/` | Builds the original C with `oracle.patch` (fidelity fixes) and `hooks.c` (scripted input, step log, pinned environment); the `fixed` variants add `fixes.patch`, the bug fixes of the switch `fixes` (section 7). |
| `harness/difftest.py` | Oracle vs port on the same inputs; first differing step; screen and state diff. |
| `harness/bot.py`, `coverage.py`, `show.py`, `run_all.sh`, `corpus/`, `curses_fuzz/` | Test tools (section 9). |
| `tools/` | `callgraph.py` (blocking list, symbol table, audits), `lint_await.py`, `lint_names.py` (no Godot built-in names), `check.sh`, `gen_stubs.py`, `gen_godot_globals.py`, `setup_env.sh`. |
| `docs/` | `CONVENTIONS.md` (translation rules), `FIDELITY.md` (every deviation and undefined-behavior choice), `CHANGES.md` (deliberate gameplay changes), `FIXES.md` (the bug fixes), `GUILD.md` (the Fighters' Guild), `VERIFICATION.md`, `AUDIT.md` (call-graph audits), `PORT_PLAN.md`, `requests/` (translator notes). |

## 2. Modules and state
- **One static-function class per C file**, with the C function names, the C order and
  the C comments. Calls into other files are qualified (`Io.msg(...)`); same-file and
  `RogueBase` functions are not, so the code reads like the C.
- **All mutable state is static vars in `RogueBase`**: extern.c's globals and every C
  `static` (named `_<file>_<var>` or `_<function>_<var>`). `RogueBase.reset()`
  recreates all of it, including fresh copies of the "constant" tables that the C code
  mutates. A new game in the same process starts exactly like a new C process.
- **C semantics are kept explicitly**:
  - struct assignment is `copy_from` (never rebinding: pointers such as `t_dest` must see
    live updates);
  - pointers are references and pointer comparisons stay identity comparisons;
  - `char` is signed, `str_t` unsigned, and the RNG wraps at 32 bits;
  - lists keep `l_next`/`l_prev`, and `discard()` is a no-op.

  CONVENTIONS.md has the rules and worked examples.
- **Daemons and fuses** are `StringName` ids (`D_RUNNERS`, ...) dispatched by
  `Daemon._call`, so `d_list` can be saved and compared.

## 3. Blocking input: coroutines
C blocks inside `readchar()` up to ~140 calls deep, including in daemons (`msg()` waits
at `--More--`). In the port:
- **Every function that can block is a coroutine**, and every call to it is `await`ed.
  The key wait itself is `await` on a signal of the `Curses` object.
- **The set of coroutines is closed and computed, not guessed.** `tools/callgraph.py`
  walks the C call graph, including every function-pointer target, from the input
  primitives (`wgetch`, `wgetnstr`, `fgets`, `exit`). The result is
  `tools/blocking.json`.
  - A few functions are excluded with a recorded reason (`port_nonblocking`): paths that
    are unreachable, or that crash the C game.
- **Three safety nets:**
  1. `tools/lint_await.py` checks both directions: a C function contains `await` iff
     it is listed, and every call to a coroutine is awaited. Godot's
     `REDUNDANT_AWAIT` warning is an error too.
  2. A runtime tripwire: only one coroutine may wait for input.
  3. The differential tests.
- **`exit()` never returns.** It records the status, notifies the host, and suspends
  forever. The host then drops the game (`Curses.abandon()`), which frees the suspended
  coroutine chain.

## 4. Curses emulation
The game reads its own screen back (`mvinch`) into game state and the RNG (`t_oldch`,
monster names, hallucination), so the emulation must match ncurses exactly. It covers:
- windows of 32-bit chtype cells and subwindows;
- wrap and pending wrap, ERR paths, `unctrl`;
- `wnoutrefresh`'s dirty ranges, `curscr` as the physical screen with its cursor, and
  `leaveok`;
- the implicit refresh in `wgetch` (only when the window is touched or its cursor
  moved);
- `endwin` and resuming, and `halfdelay`.

`harness/curses_fuzz` runs random operation scripts on real ncurses and on the
emulation and compares every cell; 10,000 scripts out of 10,000 are identical.

Output the C program writes to stdout (the top-ten list after `endwin`, `mvcur` bytes,
`Hello ...`) goes to `Curses.stdout_bytes` and is compared byte for byte.

## 5. Save files and the score file
`save.gd` saves exactly the state that `state.c` saves, with the same losses:
- objects referenced by pack index;
- `t_dest` re-targeted to the hero unless it points at the hero, a monster, a level
  object or a room's gold;
- the map, and `stdscr` cell by cell.

The file keeps C's encrypted header; the body is the port's own encoding. The two save
bugs of 5.4.4 are fixed in both the port and the oracle (FIDELITY.md). The score file
has C's layout and encryption.

## 6. The playable game
- **`TerminalView`** draws `curscr` as 80×24 cells in DejaVu Sans Mono, with standout
  shown as inverse video and a blinking cursor. The font scales to the window.
  - After `endwin()` it shows the stdout stream, as a terminal shows the shell screen.
- **Keys** become the codes a curses program reads with `keypad()`: arrows, Home/End,
  PgUp/PgDn, the keypad, and Shift/Ctrl+arrows. The ported `md_readchar()` turns these
  into Rogue commands.
- **`main.gd`** sets up the real environment: user name, time and pid (the seed),
  `ROGUEOPTS`, and the user data folder as home.
  - The game is Meta-Rogue, with a data folder of its own (`project.godot`'s custom user
    dir: `%APPDATA%\Meta-Rogue`, `~/Library/Application Support/Meta-Rogue`,
    `~/.local/share/Meta-Rogue`). At startup `user_data.gd` copies the player's files
    from the folder of its earlier name (`.../godot/app_userdata/Rogue`) into a folder
    that has none yet.
  - A saved game is restored at startup, like `rogue -r`.
  - Closing the window auto-saves, as SIGHUP does in C.
  - When a game ends, Enter starts a new one.
- **Video settings** (`video_settings.gd`, `user://video.cfg`):
  - The first launch detects the screen and goes borderless fullscreen at its native
    resolution; the windowed size defaults to the largest preset in 90% of the usable
    area (1600x900 on 1920x1080).
  - F10 opens the OPTIONS - VIDEO screen (`settings_screen.gd`: display mode, window
    size, monitor, VSync) over whatever is shown; the game is simply not fed keys
    meanwhile. Alt+Enter toggles fullscreen. `--windowed`/`--fullscreen` override the
    mode for one run.
  - Changing monitor goes through windowed mode (Godot 4.7 on Linux ignores a screen
    change in exclusive fullscreen). Nothing is applied when the game runs embedded in
    the editor's Game view.
  - The project runs in low-processor mode: the screen is redrawn only when it changes,
    with the Compatibility renderer (OpenGL 3.3), which old and integrated graphics run.
- **Downloads:** `godot/export_presets.cfg` (Windows, universal macOS, Linux) and
  `tools/export.sh`, checked by `tools/check_export.py`; `.github/workflows/release.yml`
  publishes them as a GitHub release when the version changes (`godot/README.md`,
  "Exporting and releasing"; `INSTALL.md` for players).
  - Tests: `godot/tests/settings_test.gd` (headless) and `ui_video.gd` in a real window,
    run through `godot/tests/with_display.sh` (Xvfb with a minimal window manager,
    `mini_wm.py`, which grants fullscreen and can fake a taskbar or several monitors).

## 7. Gameplay switches
The port is the baseline for gameplay changes, and each change sits behind a switch:
a `RogueBase` static var that the host sets before `Main.main()` and `reset()` leaves
alone, like `MASTER`. The playable game turns the switches on; `godot/tests/replay.gd`
turns one on only when a test asks (`fixes=1`, `guild=1`), so the classic game stays
1:1 and `harness/run_all.sh` keeps guarding every rule nobody changed.
- **`fixes`** fixes the bugs of 5.4.4 that `docs/FIXES.md` lists. Each fix is an
  `if fixes:` branch at the bug site, and the same fix is in C, in
  `harness/oracle/fixes.patch` (the oracle variants `fixed` and `fixedmaster`; edit it
  with `harness/oracle/edit_fixes.sh`). So the fixed game is verified keystroke by
  keystroke like the classic one: `difftest.py --fixes`. The per-bug scripts in
  `harness/corpus/fixes/` also carry `# expect-classic:` / `# expect-fixed:` lines,
  which check the behavior itself on the port's screens.
- **`guild`** turns on the Fighters' Guild (`docs/GUILD.md`): a 20-entry Hall of
  Fame, the shop before each new game, and the loadout it buys (`RogueBase.loadout`,
  applied by `Main.main()`). Its prices and the coffers formula are read from
  `godot/guild_prices.txt` (`GuildPrices`, `GuildFormula`), which players may edit.
  Its skills change rules of the game for the run (`godot/rogue/skills.gd`, called
  where each rule is; `RogueBase.skill()` is 0 out of guild mode).
  The oracle cannot judge it; its own tests are `godot/tests/guild_test.gd`,
  `prices_test.gd`, `skills_test.gd` and replays with `--guild --loadout FILE`.
- **`menus`** makes item commands list the items that fit at once, as PC Rogue does
  (`Pack.get_item`); tested by `godot/tests/menus_test.gd`.
- **`exp_next`** adds the experience at which the next level starts to the status
  line (`Io.status`): `Exp: 2/15/20`; tested by `godot/tests/menus_test.gd`.
- Switches the oracle cannot judge also get smoke runs: `difftest.py smoke` plays
  random games on the port alone with any switches on and fails on a script error or a
  run that does not end.
- `--classic` on the game's command line turns them all off (with separate save and
  score files). `docs/CHANGES.md` lists every deliberate change and its switch.

## 8. Fidelity policy
The original has undefined behavior: uninitialized reads, reads and writes out of
bounds, use after free, unsequenced RNG calls, and two hangs. For each case one
deterministic behavior was chosen and applied identically in the oracle and in the port.
`docs/FIDELITY.md` lists every case, every pinned environment value, and the few
deliberate port-only deviations.

## 9. Verification
- **The oracle** is the original C plus `oracle.patch`, with `hooks.c` linked through
  `-Wl,--wrap`. The hooks provide:
  - scripted keys, `fgets` and `wgetnstr`;
  - a pinned environment: time, pid, user, home, tty characters, baud rate;
  - `free()` as a no-op, crash signals logged as an exit status, and a file sandbox;
  - an interactive mode for the bot.
- **The step log** (`harness/DUMP_FORMAT.md`) has one line per keyboard read: the key,
  the RNG state, the physical cursor, a hash of the screen, and a hash of a game-state
  digest. A divergence is located at the exact keystroke. `--full` adds the screens and
  the digest text.
- **`harness/difftest.py` modes:**
  - `seeds`: level generation;
  - `fuzz`: random weighted key scripts; `--wizard` adds the MASTER wizard commands
    and object creation;
  - `saves`: save/restore chains;
  - `corpus`: regression scripts in `harness/corpus`;
  - `one`;
  - `--fixes` with any mode: the port with the bug fixes on, against the fixed C.
- **Other tools:**
  - `harness/bot.py` plays the oracle reactively to record long games.
  - `harness/coverage.py` measures gcov line coverage of the C by any set of scripts.
  - `harness/show.py` prints the screens around a step.
  - `harness/run_all.sh` runs everything.

## 10. Phase 0 spike results (Godot 4.7.2)
| Question | Result |
|---|---|
| Static-function coroutines across a 3-file class cycle, with inherited static vars | Work. Calls resume through every level and static state is shared. |
| `await Callable(Class, static coroutine).call()` | Works. |
| `await` inside `and`/`or` | Short-circuits correctly. Note: `await` binds tighter than comparison operators. |
| An abandoned coroutine (its signal never emitted, the emitter dropped) | Never resumes. |
| `match` with `ord()` patterns and constants | Works. |
| Integer `/` and `%` | Truncate toward zero; `%` takes the sign of the dividend (C semantics). |
| `>>`/`<<` on negative values | Arithmetic at runtime. A negative *constant* shift (`-8 >> 1`) is a parse error. |
| 32-bit wrapping RNG | `(seed * 11109 + 13849) & 0xFFFFFFFF` matches C with `-fwrapv`. |
| Speed | About 10^7 static calls/s; awaiting a non-suspending coroutine costs about 0.1 µs. |

GDScript traps met during the port:
- There are no octal literals.
- `Window` and `Object.call` are taken (hence `CWindow` and `call_()`).
- `char(0)` is U+FFFD, not an empty string.
- `load()` returns a script even when its dependencies failed to compile, and a compile
  error in one file makes every dependent file fail.
- The GDScript call stack is limited to about 2,000 frames. The deepest recursion,
  `numpass()`, stays far below that.
