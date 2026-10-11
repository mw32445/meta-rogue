# Rogue 5.4.4 → Godot 4.7 (GDScript), a verified 1:1 port

- **Repository root:** the original C game (Rogue 5.4.4). It is not modified; it is
  built as the test oracle.
- **`godot/`:** the port and the playable game.
- **`harness/`:** differential testing against the C.
- **`tools/`:** checks.

Read `docs/ARCHITECTURE.md` first. `docs/CONVENTIONS.md` has the translation rules;
`docs/FIDELITY.md` lists every place where the port or the oracle deliberately differs
from the stock C build.

## Setup
`tools/setup_env.sh` installs Godot 4.7.2 at `/root/bin/godot` (it downloads it, or
builds it from source) and builds the oracle. It is idempotent. The scripts use `$GODOT`,
then `godot` on PATH, then `/root/bin/godot`.

## Commands
| What | Command |
|---|---|
| Compile every script + the await lint (run after any GDScript change) | `tools/check.sh` |
| Same for a few modules, isolated from half-edited others | `tools/check.sh --quick godot/rogue/fight.gd` |
| Everything (oracle builds, curses fuzz, corpus, seeds, fuzz) | `harness/run_all.sh` (about 1 h) or `harness/run_all.sh --quick` |
| Random games vs the C | `python3 harness/difftest.py fuzz --count 50 [--len 800] [--opts ROGUEOPTS] [--wizard]` |
| Level generation, save/restore, regression scripts | `python3 harness/difftest.py seeds --count 200` / `saves --count 50` / `corpus` |
| Look at a divergence | `python3 harness/show.py KEYFILE --step N --port [--digest]` |
| Which C lines the tests reach | `python3 harness/coverage.py --reset DIR...` |
| Play | Open `godot/project.godot` in Godot 4.7 and press F5. Headless replay: `godot --headless --path godot --script res://tests/replay.gd -- --keys K --dump D` |

A divergence report gives the first differing keystroke, both screens, and the digest
fields that differ (`harness/DUMP_FORMAT.md`). Add a script that reproduced a fixed bug
to `harness/corpus/`, with a comment line saying what it covers.

## Rules for game code (`godot/rogue/`)
1. **Coroutines.** A function that can wait for a key is a coroutine, and every call to
   it is `await`ed, transitively. `tools/lint_await.py` (run by `check.sh`) enforces
   this in both directions.
   - If a change makes a C function block that did not before (for example by adding a
     `msg()` call), add it to `port_blocking` in `tools/blocking.json`, with the reason,
     and await it at every call site.
   - Never call a coroutine from a lambda, setter, `sort_custom` or `call_deferred`.
2. **State lives in `RogueBase` static vars.** New state needs:
   - an initial value in `reset()`;
   - entries in `Save._save_state`/`_restore_state` if it must survive a save. C saves
     exactly what `state.c` saves.
3. **C semantics.** Structs are reference types. Assigning a whole struct is
   `copy_from()`, never rebinding, because pointers such as `t_dest` must see the
   change. Lists use `l_next`/`l_prev`. `char` is signed. See CONVENTIONS.md.
4. **Same-file calls are unqualified; other modules are qualified** (`Io.msg`).
   `rnd()`/`roll()` live in RogueBase. The order of RNG calls is what the tests check.

## Gameplay changes and the 1:1 baseline
The differential tests compare against the original. An intentional gameplay change
makes them fail wherever behavior changes. Recommended approach:
- Put changes behind a switch: a `RogueBase` flag or an option.
  - The playable game turns it on.
  - `godot/tests/replay.gd` keeps it off.

  `harness/run_all.sh` then keeps guarding every rule you did not change.
- Test new behavior with your own scripts and expectations; the oracle cannot judge
  it.
- Record deliberate changes in `docs/CHANGES.md`.

## Gotchas
- **GDScript:**
  - There are no octal literals.
  - `char(0)` is U+FFFD; use `RogueBase.chr()`, which returns "" for 0.
  - `await` binds tighter than comparison operators.
  - A compile error in one file makes every dependent file fail with "Failed to compile
    depended scripts". `check.sh --quick` isolates it.
- **Processes:** never `pkill -f` a pattern that also matches your own shell command.
- **Tests:**
  - `harness/out/` is scratch space (gitignored).
  - The oracle runs as root, so test runs are sandboxed to their directory (file names
    with `/` are refused in both programs).
