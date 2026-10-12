# Plan: Port Rogue 5.4.4 (C/curses) to Godot 4 — 1:1, verified against the original

> **Status: done.** All phases are complete. The port matches the original at every
> keystroke in 5,029 final test runs, with 0 divergences. The tests reach 91.1% of the
> original's game-logic lines (about 96% of the reachable ones). See `VERIFICATION.md`
> for the results, `FIDELITY.md` for the documented differences, and `ARCHITECTURE.md`
> for how it works. The plan below is kept as written.

## Context
The repo is a fork of the Rogue 5.4.4 archive: ~16.8K lines of C, of which ~10K is game logic
(the rest is portability glue, save serialization, and DES crypt for the wizard password). The user
wants a faithful 1:1 Godot port as the base for later **gameplay changes**, using ~$250 of cloud
credits, written in **GDScript**, run at **Max effort with parallel subagents**.

"1:1" is made measurable: **given the same seed and keystrokes, the Godot port must show the exact
same screen (characters, standout attribute, cursor) and the same RNG state as the original C game at
every input prompt.** We prove it by building the original C game as a reference oracle and
diff-testing step by step.

## Recommendations for the user (answering "effort level and anything else")
- **Effort: stay on Max** for this session. The expensive failure mode is subtle divergence (RNG call
  order, C integer and curses semantics), and Max pays off most in architecture and divergence
  debugging. Rough cost for the full port + verification: **~$130–220** of the $250 (Opus 5.5: $4/M
  in, $20/M out, $0.20/M cache reads). Divergence debugging is the main uncertainty. Every phase
  ends committed and pushed, so we can stop at any phase boundary with usable results. Tell me if you
  want a hard stop at some spend level.
- **Install Godot 4.7.x locally** (4.7.2-stable is the latest stable tag) to play the result — this
  container can't show you a window.
- **Network:** Godot's download hosts are blocked here. I'll build Godot from source (~45–90 min,
  runs in the background while I build the oracle). To save that hour in every future session, allow
  GitHub release downloads (or `downloads.godotengine.org`) in the environment's network settings and
  set `tools/setup_env.sh` (written in Phase 5) as the environment's **Setup script** (cloud
  environment menu → Edit).
- After the port lands, use a **fresh session per gameplay change**. The CLAUDE.md written in this
  work will brief future sessions on the architecture, the conventions, and the one-command test suite.

## Architecture decisions
1. **Coroutines for blocking input.** C blocks in `readchar()` up to ~140 functions deep, including
   in daemons, because `msg()` blocks on `--More--` whenever `mpos != 0`. Every function that can
   block becomes a GDScript coroutine, and every call to it is `await`ed. `wgetch()` awaits a key
   signal owned by a per-game `Session` object. C's deep `exit()` calls (death, quit, win, save, shell)
   become `my_exit()`, which emits `game_over`. The Session is then freed, so the suspended coroutine
   stack is dropped.
   - Single-threaded: no races, the UI can read game state at any time, and in-process restart is
     clean.
   - Rejected: a game-logic Thread. GDScript has no exceptions to unwind exits, threads would leak per
     game, and the renderer would race the game thread.
   - **Three safety nets against a missed `await`:**
     - **Closed blocking list.** The set of blocking functions comes from the C call graph, including
       every function-pointer target (daemons, fuses incl. `turn_see`, option get/put, `pa_daemon`).
     - **Two-way lint.** `tools/lint_await.py`: every call to a listed function is awaited, and no
       unlisted function contains `await`. `REDUNDANT_AWAIT` is an error. No awaits in lambdas,
       setters, `sort_custom` or `call_deferred`.
     - **Runtime tripwire.** `wgetch` asserts it is the only waiter, and the key feeder asserts there
       is exactly one waiter before each emit.
2. **One module per C file, with C names kept.** `fight.c` → `godot/rogue/fight.gd`
   (`class_name Fight`), with the same function names and order and the original comments kept.
   Cross-module calls are written `Io.msg(...)`.
   - All modules `extends RogueBase`. RogueBase holds the rogue.h/extern.h constants, the macro
     helpers (`on`, `ce`, `ISRING`, `INDEX/chat/flat/moat`, `GOLDCALC`, `rnd`, `roll`, `CTRL`, `CCHAR`,
     `to_schar`) and **all mutable game state** as `static var`s: extern.c globals, plus file and
     function statics named `_<file>_<var>` / `_<func>_<var>`.
   - So module code reads `player`, `FLOOR` and `rnd(6)` unqualified, like C.
   - `reset()` is generated from a state table. It deep-copies pristine copies of the "constant"
     tables the C code mutates (`monsters['F'].s_dmg`, cumulative `oi_prob`, `oi_know`/`oi_guess`,
     `weap_info[FLAME].oi_name`) and restores non-zero static initializers (`s_pur=-1`, `maxlen=-1`).
   - Static funcs if the Phase 0 spike confirms static coroutines and inherited static vars work in
     4.7, otherwise autoload singletons. Call sites are identical either way.
3. **Data model with C semantics.**
   - RefCounted classes: `Coord`, `Thing`, `Room`, `Stats`, `Place`, `ObjInfo`, `Monster`,
     `DelayedAction`. `Thing` carries all union fields; `o_charges` and `o_goldval` are property
     aliases of `o_arm`.
   - **Struct assignment** → `dst.copy_from(src)`, which also copies `l_next`/`l_prev` (pack.c:212).
     Never rebind: `t_dest` points at `hero`, an object's `o_pos` or a room's `r_gold`, and must see
     live updates.
   - **Pointers** → references. **calloc** → zero-initialized fields.
   - **Chars are ints.** `p_flags` is a signed char (`F_PASS` is stored as -128). `str_t` is
     unsigned 32-bit. The RNG masks to 32 bits on every step.
   - **Lists** use explicit `l_next`/`l_prev` (`mlist = List._attach(mlist, tp)`). `discard()` is a
     no-op.
   - **Fixed storage:** the 9 rooms and 13 passages are allocated once and mutated in place.
     `places` is a flat 2560-entry array indexed `(x<<5)+y`.
   - **Daemon and fuse functions** are stable IDs dispatched through a table.
4. **Exact curses emulation** (`godot/curses/curses.gd`). The game reads its own screen back into
   game state and the RNG (`t_oldch`, `set_mname`, `seen_stairs`), so the emulation must match
   ncurses exactly:
   - **Cells:** windows of char + attribute cells.
   - **Cursor and refresh:** the ncurses `_HASMOVED` flag (set by every `wmove`, cleared by
     `wnoutrefresh`) and the exact implicit refresh in `wgetch`: refresh only if the window is touched
     or has moved.
   - **Writing:** wrap and pending-wrap at column 79; `\n` clears to end of line; `\t` to 8-column
     stops; `\b`; `unctrl`.
   - **ERR paths:** failed `mv*` calls skip their output; an out-of-range `mvinch` returns ERR (-1); at
     the bottom row, `\n` and the corner return ERR and abort the string.
   - **Attributes:** clear and clrtoeol fill with the window background, not the standout attribute.
   - **Windows:** `touchwin`, `clearok`, and `newwin/subwin/mvwin/delwin/werase/leaveok` for the
     overwrite-style inventory.
   - **Text helpers:** a post-`endwin` byte stream for the `printf`'d top-ten list, and a
     C-compatible `sprintf` (`%s %d %c %u %x %%`, widths, `-`, `*`).
5. **Presentation is a thin view.** `TerminalView` (a Control) draws `curscr` as 80×24 cells in
   bundled DejaVu Sans Mono, with standout as inverse video, a blinking cursor, and scaling with the
   window.
   - Godot key events become ncurses `KEY_*` codes, which go through a faithfully ported
     `md_readchar`.
   - Mapping: arrows/Home/End/PgUp/PgDn/keypad → `hjklyubn`; Shift/Ctrl+arrows → Ctrl-runs;
     Backspace → `^H`.
   - The original numpad-5 → `u` quirk is kept and listed as a candidate first fix.
   - Window resizes never inject keys.

## Fidelity policy for undefined/environment-dependent behavior (identical in oracle and port)
| Original behavior | Policy |
|---|---|
| `fire_bolt`'s uninitialized `THING bolt` (sticks.c:308), read by `roll_em` | Initialize as clearly intended: zeroed with `o_launch = -1`, so bolts use `o_hurldmg` "6x6" |
| Use-after-free: discarded `t_dest` targets, nymph stealing from a stack, stale `last_pick`, monsters freed mid-`runners` | Freed objects stay intact (`free` is a no-op in the oracle; GDScript keeps them alive). The stock binary differs: glibc tcache clobbers `l_next`/`l_prev`. This is documented. |
| `INDEX(y,x)` with x = -1 in left-column mazes | An out-of-range index returns a dummy blank PLACE |
| Unsequenced multi-RNG expressions: `ring_eat(LEFT)+ring_eat(RIGHT)` (daemons.c:163), and any argument lists found by the call-graph audit | Pin the stock gcc order (from objdump), make it explicit in the oracle patch, and mirror it in the port |
| Signed overflow in the RNG; `%ld` used for an `int` (io.c:223) | `-fwrapv` / a 32-bit mask in the port; change `%ld` to `%d` |
| ESC followed by a fast key merging (timing-dependent) | ESC is always standalone: `getch` in halfdelay mode returns ERR without consuming a key |
| `!` shell escape | Same screen and prompt sequence, but no shell is spawned |
| `msgbuf[143]` overflow on huge messages; `%` in player-typed names | The port uses dynamic strings; the fuzzer keeps typed names short and `%`-free |
| Save bugs: 4 daemon IDs missing (crash on restore), corridor room saved as `&rooms[-1]` | Fixed in the port's save format (documented deviation) |
| Seed (time+pid), tombstone year, name, uid, HOME, erase/kill chars, baud rate, terminal | Pinned in tests; real values in normal play |

Everything else is reproduced exactly, including deterministic original bugs:
- `relocate` never calls `find_dest`.
- `find_dest` reuses its parameter.
- `add_pack` does not detach from `lvl_obj`.
- `F` leaves `kamikaze` set.

`docs/FIDELITY.md` lists every deviation.

## Repo layout (branch `claude/intelligent-ride-8m0rgk`; the original C stays untouched at repo root)
- `godot/`: the Godot 4.7 project.
  - `project.godot`, `main.tscn`
  - `rogue/*.gd`: game modules, `rogue_base.gd`, types
  - `curses/`: emulation, sprintf, post-endwin stream
  - `ui/terminal_view.gd`
  - `tests/`: replay runner and unit tests
  - `fonts/DejaVuSansMono.ttf` plus its license
- `harness/`:
  - `oracle/`: patch, `hooks.c`, `build.sh`
  - `curses_fuzz/`, `keygen.py`, `difftest.py`, `bot.py`, `coverage.sh`, `run_all.sh`, `corpus/`
- `tools/`: `lint_await.py`, `callgraph.py` (→ `blocking.json`, `symbols.json`), `setup_env.sh`
- `docs/`: `CONVENTIONS.md`, `FIDELITY.md`, `ARCHITECTURE.md`; `CLAUDE.md` at the repo root

## Phases
Each phase ends with a commit and a push. The verification gate is in **bold**.

### Phase 0: environment and spikes (lead)
- Start the Godot 4.7.2 **editor** build in the background: shallow clone plus
  `scons platform=linuxbsd target=editor`. An editor build is needed for `--import` and the
  `class_name` cache. First spend one minute checking whether `add_repo godotengine/godot` unlocks the
  official release zip.
- Spike in 4.7:
  - A 3-file cycle of static-func coroutines with inherited static vars.
  - `await` through `Callable.call()`, and `await` inside `and`/`or`.
  - Freeing the Session emitter drops pending awaits.
  - `match` with `ord()` or constants.
  - Integer `/ % >>` semantics.
  - Headless args, file I/O, exit codes, call throughput.

**Gate: spike results are recorded in ARCHITECTURE.md, and the module style is fixed.**

### Phase 1: oracle and C analysis (lead, runs while Godot builds)
- **Build.** `harness/oracle/build.sh` copies the C sources into a build directory, applies the
  documented patch, and compiles with `-O2 -g -fwrapv -ftrivial-auto-var-init=zero`.
- **Hooks.** `hooks.c` is compiled with ncurses internals visible and linked through `--wrap`:
  - **`wgetch`:**
    - Evaluate the exact implicit-refresh condition and refresh.
    - Dump `curscr` cells (char + standout) read through the struct, so curscr's cursor is not
      disturbed (`quit()` reads it).
    - Also dump the cursor, `seed`, and a state digest (hp, food, `d_list`, mlist/lvl_obj positions
      and flags).
    - Return the next scripted key, or ERR in halfdelay mode without consuming one.
    - At the end of the script, dump and exit.
  - **Mode tracking:** `halfdelay`, `raw` and `nocbreak`.
  - **`free`:** no-op.
  - **`initscr`:** becomes `newterm`, with output to /dev/null and input from /dev/null.
  - **Pinned values:** `baudrate`, `erasechar`/`killchar`, `getuid`, `time`, `getpid`.
  - **Scripted input:** `wgetnstr` and `fgets(stdin)`.
  - **Shell:** no-op.
  - Pinned env: `ROGUEOPTS`, `HOME`, `TERM=xterm`, 24×80, and a fresh score file per run.
- **Variants:** MASTER (wizard) and `--coverage`.
- **Call-graph analysis.** `tools/callgraph.py` uses clang AST or cflow and produces:
  - the closed blocking list and `symbols.json` (function → module, statics and their initial values);
  - an audit of unsequenced multi-RNG expressions;
  - a static-buffer aliasing audit (call sites that hold two `prbuf`/`tbuf` results at once).

**Gate: the same seed and script twice give byte-identical dumps, and the audits are written up.**

### Phase 2: foundation (lead)
- **Curses.** `curses.gd`, `sprintf` and the post-endwin stream, plus a **randomized curses
  differential fuzzer**: real ncurses vs the emulation, over exactly the API subset the game uses,
  biased toward edge coordinates.
- **Game core.** `rogue_base.gd` (rogue.h, extern.h, extern.c, the generated `reset()`), the types,
  and these modules: `list`, `io`, `misc` (screen readers: `look`, `set_oldch`-style code), `main`
  (rnd/roll, main/playit/quit/my_exit), `daemon`, and `md_readchar`.
- **Stubs** for every other C function, generated from `symbols.json`. Stubs of blocking functions
  contain an `await`, so the project parses and the lint works from day one.
- **Test tooling.** A replay runner (`--seed --keys --opts --dump`, plus a batch mode with a fresh
  Session per game), `difftest.py` (step-hash compare, full dumps only on mismatch), and the lint.
- **CONVENTIONS.md**, with worked examples for:
  - the 30 `goto`s: backward re-dispatch → loop; forward jumps to a shared tail → helper or state
    variable; jumps between cases in scrolls.c/sticks.c → explicit dispatch;
  - `switch` fall-through → if/elif;
  - `++`, comma operators and assignment-in-condition;
  - short-circuit RNG order;
  - struct copy vs pointer;
  - `await` rules: assign awaited results to locals, keep evaluation order;
  - never pre-evaluating macros (`WANDERTIME` consumes RNG, `BEFORE`/`AFTER` don't);
  - never snapshotting `d_list` or lists while iterating;
  - char and integer helpers.

**Gate: the curses fuzzer runs clean over 10k sequences, the unit tests pass, the stub game parses,
and the lint is clean.**

### Phase 3: parallel translation (5 subagents, Max)
Each translator gets CONVENTIONS.md, `symbols.json`, `blocking.json`, the foundation code and its C
files. Each must pass Godot's parser and the lint before returning. Translators own only their own
files: they file foundation changes as requests in `docs/requests/<group>.md` and do not commit.

| Group | C files |
|---|---|
| A | rooms, passages, new_level, init |
| B | monsters, chase, fight, move (these share `t_dest`, `runto` and `relocate`) |
| C | pack, things, weapons, armor, rings (these share `inv_name`, `get_item` and `inventory`) |
| D | potions, scrolls, sticks, daemons |
| E | rip, options, wizard, with every `#ifdef MASTER` block as a runtime flag |

The lead then does `command.c` (the dispatcher touches everything) and save/restore. Save/restore is
a new serializer: object graph by indices, daemons by ID, stdscr included, and the two C save bugs
fixed.

**Gate: the whole project parses, the lint is clean, and a game boots to the first prompt headless
and matches the oracle's first screen.**

### Phase 4: differential testing to zero divergences (lead, plus targeted helper agents)
Test order:
1. The first screen and RNG state across 1,000 seeds (level generation).
2. Random weighted key scripts × many seeds. Weight toward ESC, ^C, `\r`/`\n`, DEL, `S`, `Q`, counts,
   runs, and every item command with random letters and directions. Also include `--More--`, `o`,
   `D`, `/`, `?`, `^P` and `^R`.
3. A **ROGUEOPTS matrix**: inven=overwrite/slow/clear, terse, jump, flush, passgo, seefloor and
   tombstone, each on and off.
4. MASTER-mode scenarios against the MASTER oracle:
   - create and use every potion, scroll, wand, ring, weapon and armor;
   - `^D` to every depth to meet all 26 monsters;
   - the amulet, then the ascent to the winner screen.
5. An explorer bot that drives the oracle reactively to record deep games, which are then replayed on
   the port.
6. Save/restore round trips.
7. All exit paths: post-death, quit, win, save and shell. Compare stdout as raw bytes.
8. An A-then-B batch test that proves `reset()` is clean.

For each divergence: find the first differing step (the seed and digest show it immediately), fix the
port (or the oracle policy if the cause is UB), and add a regression script to `harness/corpus/`.

**Gate: 0 divergences across the full corpus (target at least 5,000 runs, including deep games), and
gcov line coverage of reachable game-logic C at 90% or more, with the uncovered lines reviewed by
hand.**

### Phase 5: playable Godot shell and docs (lead)
- **Playability:** window, scaling and cursor polish; key mapping.
- **Startup restore:** if a save exists, restore it and delete the save, as the original does.
- **Game end:** `game_over` leads to a "play again / quit" screen.
- **Paths and options:** saves and scores live under `user://`; `ROGUEOPTS` is read from the
  environment or `--rogueopts=`.
- **Docs:** the Godot README, CLAUDE.md, ARCHITECTURE.md, FIDELITY.md and `tools/setup_env.sh`.

**Gate: the full suite is green from a clean checkout with one command
(`harness/run_all.sh`). Optional: a screenshot through xvfb if it is available.**

## Risks & mitigations
| Risk | Mitigation |
|---|---|
| Godot binary build is slow (45–90 min) and lost on container restart | Build in the background during Phase 1. Commit and push after every phase, since restarts wipe uncommitted work. |
| A missed `await` silently corrupts state | Closed blocking list, the two-way lint, and the runtime tripwire. |
| Curses semantics drift (the screen feeds the RNG) | The randomized curses differential fuzzer, run before fan-out. |
| Divergences only surface many turns late | `seed` plus a state digest in every dump pinpoint the exact step. |
| Parallel translators diverge in style | CONVENTIONS.md, stubs and the symbol table up front, plus the parser and lint gate. Diff-testing catches semantic slips. |
| Coverage blind spots | The ROGUEOPTS matrix, MASTER scenarios, the explorer bot, and a gcov-driven gap list. |
| Budget overrun | Phase gates are natural stop points; I'll report progress at each gate. |

## Verification (end-to-end)
- **`harness/run_all.sh`** runs everything in one command:
  - builds the oracle;
  - runs the Godot unit tests, the lint and the curses fuzzer;
  - runs the differential corpus in 4 parallel Godot processes;
  - prints the divergence count and a coverage summary.
- **Divergence reports** show the step, the key, both screens, a cell diff and the digest diff. A
  minimizer trims the script.
- **Manual check:** open `godot/project.godot` in Godot 4.7 and press Play; the game should be
  playable with the keyboard.
