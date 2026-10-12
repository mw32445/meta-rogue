# C → GDScript translation conventions (Rogue 5.4.4 → Godot)

The port is **1:1**. The C program and the GDScript program are fed the same seed and
keys. They must call `rnd()` in the same order with the same arguments and produce the
same screen at every keyboard read. `harness/difftest.py` checks this step by step
against the original C game.

So do **not** refactor, simplify, fix bugs or "improve" anything. Translate statement by
statement, keeping the C names, the C function order and the C comments. Where C is
undefined, follow `docs/FIDELITY.md`. Anything new you find there goes in your
`docs/requests/<group>.md`.

Read these before starting:
- `godot/rogue/rogue_base.gd`: constants, macros, global state, C helpers, curses.
- `godot/rogue/types/*.gd`.
- The finished modules `list.gd`, `io.gd` and `daemon.gd`, which are worked examples.

## 1. Files, classes and names
- **One file per C file.** `foo.c` becomes `godot/rogue/foo.gd`.
  - Each file declares `class_name Foo` and `extends RogueBase`.
  - The class-name table is `MODULES` in `tools/gen_stubs.py`. For example:
    `new_level.c` → `NewLevel`, `mach_dep.c` → `MachDep`, `mdport.c` → `Mdport`.
- **Every C function becomes a `static func` with the same name.**
  - The only exception is a name that clashes with a Godot name (below): add a
    trailing underscore, `call()` → `call_()`, `sign()` → `sign_()`.
- **Parameters, locals and globals keep their C names.** Names that are GDScript
  keywords or builtins get a trailing `_`: `range_`, `str_`, `len_`, `char_`, `in_`,
  `type_`, `max_`, `min_`, `pass_`, `match_`, `exp_`, `seed_` (the RNG state).
- **No declared name may be a Godot name.** This covers every built-in or @GDScript
  function, engine singleton, class and built-in type, and every member of the
  script's native base class (`tr`, `name`, ...).
  - Why: Godot resolves an unqualified call `f()` to a built-in function *before* a
    class member, so a module function named `sign` is silently bypassed by `sign(x)`.
    A variable named like a built-in shadows it.
  - Enforcement: `tools/lint_names.py`, run by `tools/check.sh`, and the engine
    warning `shadowed_global_identifier`, set to an error in `project.godot`.
  - Exception: Godot's global *constants* are not checked. `OK` and the curses
    `KEY_*` constants keep their C/ncurses names. A class member resolves before a
    Godot global, so `OK` means ours in every `RogueBase` module and `KEY_DOWN` means
    ours inside `Curses`. Everywhere else, write `Curses.KEY_DOWN`; a bare `KEY_DOWN`
    there is Godot's key code (`terminal_view.gd` uses those on purpose).
  - After a Godot upgrade, regenerate the name table: `godot --headless --doctool DIR`,
    then `tools/gen_godot_globals.py DIR`.
- **Keep the same parameter count and order.** Other modules call your functions,
  and their translators work from the C signature.
- **Function-pointer daemons take one int argument:**
  `static func doctor(_arg: int = 0) -> void`. This applies to every function passed
  to `start_daemon`/`fuse`. The exception is `turn_see(turn_off: bool)`.
- **Same-file calls are unqualified.** Calls into other files are qualified:
  `Io.msg(...)`, `Pack.get_item(...)`.
  - `tools/symbols.json` says which C file defines each function.
  - `rnd` and `roll` live in `RogueBase`, so call them unqualified.
- **Header comments.** Put the C header comment above each function as `##` doc
  comments. Keep the original inline comments as `#` comments where they still fit.

## 2. Types and pointers
| C | GDScript |
|---|---|
| `int`, `short`, `long`, `unsigned`, `char` (a value) | `int` |
| `bool` | `bool` (use `int(b)` where C does arithmetic on it) |
| `char *`, `char buf[N]` | `String` |
| `char *` that can be NULL (`oi_name`, `oi_guess`, `o_label`, `h_desc`, some returns) | `Variant` holding `null` or a `String` |
| `coord` / `coord *` | `Coord` (a reference type) |
| `THING *` | `Thing` (`null` for NULL) |
| `struct room *` | `Room`: always one of `rooms[i]` / `passages[i]` |
| `struct stats` | `Stats` |
| `PLACE *` | `Place` (from `INDEX(y, x)`) |
| `struct obj_info *` | `ObjInfo`. An `obj_info info[]` parameter is an `Array` of `ObjInfo`, passed with an index when C passes `&info[i]`. |

**Coordinates and structs (the most important rule).** C structs are values. Our types
are references, because the C code keeps pointers to them: `t_dest = &hero`,
`&obj->o_pos`, `&rp->r_gold`.
- **Struct assignment.** `a = b;` (two struct values) is `a.copy_from(b)`. Never rebind
  a struct field or a global struct that something might point at.
  - `hero = nh;` → `hero.copy_from(nh)`. Assigning `hero = x` does not even compile.
  - `*cp = pos;` → `cp.copy_from(pos)`.
  - `tp->t_pos = *cp;` → `tp.t_pos.copy_from(cp)`.
  - `*nobj = *obj;` → `nobj.copy_from(obj)`. This copies everything, including
    `l_next`/`l_prev`, exactly as C does.
- **Pointer assignment.** `p = q;` (two pointers) is plain reference assignment.
  - `tp->t_dest = &hero;` → `tp.t_dest = hero` (`hero` is a property returning
    `player.t_pos`).
  - `cp = &tp->t_pos;` → `cp = tp.t_pos`.
- **A local struct.** `coord c;` → `var c := Coord.new()`. Passing `&c` passes `c`.
  `coord c = *cp;` → `var c := cp.dup()`.
- **Persistent statics.** A `static coord` / `static THING` local in C is a persistent
  object listed in RogueBase (`_wanderer_cp`, `_do_zap_bolt`, …). Use that object; do
  not create a new one per call.
- **Pointer comparisons stay identity comparisons.** `tp->t_dest == &hero` →
  `tp.t_dest == hero`. `rp == proom` → `rp == proom`.
- **Room indexing and iteration.** `rp - rooms` → `rooms.find(rp)`. `&rooms[i]` →
  `rooms[i]`.
  - `for (rp = rooms; rp < &rooms[MAXROOMS]; rp++)` → `for rp in rooms:`, unless the
    body needs the index.
- **The map.** `INDEX(y, x)` returns the `Place`. Read with `chat(y,x)`, `flat(y,x)`
  and `moat(y,x)`. Write with:
  - `INDEX(y, x).p_ch = c`
  - `INDEX(y, x).p_flags |= F_SEEN`
  - `INDEX(y, x).p_monst = tp`

  `PLACE *pp = INDEX(y,x)` → `var pp := INDEX(y, x)`. `char *fp = &pp->p_flags` → use
  `pp.p_flags` directly.
  - Out-of-range coordinates return a blank dummy square, matching the oracle (see
    `docs/FIDELITY.md`).
  - Never compute `(x << 5) + y` yourself.
- **Lists.** C passes `THING **`; GDScript has no pointer to the list head, so the
  functions return the new head:
  - `attach(mlist, tp)` → `mlist = List._attach(mlist, tp)`
  - `detach(pack, obj)` → `pack = List._detach(pack, obj)`. `pack` is a property and
    its setter updates `player.t_pack`.
  - `detach(tp->t_pack, obj)` → `tp.t_pack = List._detach(tp.t_pack, obj)`
  - `free_list(lvl_obj)` → `lvl_obj = List._free_list(lvl_obj)`
  - `next(tp)` → `tp.l_next`. `prev(tp)` → `tp.l_prev`.
  - `discard(item)` is a no-op (a freed object stays intact, see FIDELITY). Never null
    out its fields.
- **Field aliases.** `o_charges` and `o_goldval` are property aliases of `o_arm`. Use
  whichever name the C code uses.

## 3. Integers
- GDScript `int` is 64-bit. `/` truncates toward zero and `%` takes the sign of the
  dividend, the same as C. Do not use `posmod`, `floori`, `snapped` or float math.
- **No octal literals in GDScript.** C `0040000` must be written as hex: `0x4000`.
- **Shifts.** `<<` and `>>` on a negative *variable* behave like C at runtime. A
  constant expression such as `-8 >> 1` is a parse error, but Rogue never writes one.
- **`char` is signed.** Use `to_schar(v)` where C stores a wider value into a `char`
  and the value can exceed 127. `CCHAR(x)` already returns the signed char.
- **`short` fields** (`t_flags`, `r_flags`, `m_flags`) hold 0..0xffff. Bit operations
  work unchanged.
- **`str_t` (`s_str`) is unsigned.** Follow the C code: `add_str` clamps.
- **The RNG.** Only the RNG relies on 32-bit wraparound, and `rnd()` handles that.
  - Assign the seed as `seed_ = dnum & 0xFFFFFFFF` (C's `seed`; see §1).
  - The raw `RN` macro is `RN()`.

## 4. Evaluation order: the RNG must be consumed identically
- **Keep the exact order of every call with side effects,** above all
  `rnd`/`roll`/`spread`/`GOLDCALC`, plus anything that draws, moves or prints.
  GDScript evaluates left to right. The few unsequenced C expressions are pinned in
  `docs/AUDIT.md`.
- **`&&` and `||` short-circuit in GDScript (`and`/`or`) as in C.** Keep the operand
  order exactly. `a ? b : c` → `(b if a else c)`; only one branch is evaluated in both
  languages.
- **Macros that are calls stay calls.** `GOLDCALC`, `BEFORE`, `AFTER`, `WANDERTIME`,
  `BEARTIME`, `SLEEPTIME` and `HOLDTIME` become `GOLDCALC()`, `BEFORE()`, … at exactly
  the place C uses them. Never hoist or cache them; `WANDERTIME()` consumes RNG.
- **Assignment inside a condition.** Split it, keeping the order:
  ```
  if ((tp = moat(y, x)) != NULL && ...)     →   tp = moat(y, x)
                                                if tp != null and ...:
  while ((ch = readchar()) != ESCAPE) {..}  →   while true:
                                                    ch = await Io.readchar()
                                                    if ch == ESCAPE: break
                                                    ..
  ```
- **`++`/`--` and the comma operator inside expressions** become separate statements,
  in C's order. `x = y++` is `x = y; y += 1`, and `x = ++y` is `y += 1; x = y`.
- **`for` loops with `continue`.** C's `for` runs the increment on `continue`;
  GDScript's `while` does not.
  - Use `for i in range(a, b):` only when the body doesn't change `i` and `i` isn't
    needed after the loop.
  - Otherwise use `while`, and put the increment before every `continue`.
- **`do { … } while (c);`** → `while true:` … `if not (c): break`.

## 5. switch, when/otherwise, goto
- **`switch` → `match`.** Stacked labels `case 'a': case 'b':` become `ord("a"),
  ord("b"):`.
  - Rogue's `when X:` means `break; case X:`, and `otherwise:` means `break; default:`.
  - `match` has no fallthrough. A *real* C fallthrough (code, then no break) needs
    if/elif or duplicated code, with a `# C falls through` comment.
  - In `match` patterns, `ord("x")` and constants (`FLOOR`, `CTRL_H`, `ESCAPE`) work.
    Function calls such as `CTRL(x)` do not.
- **`goto`** (30 sites in the C). Restructure, preserving behavior exactly:
  - *A backward jump to re-dispatch* (`over:` before a switch, then `goto over` after
    changing `ch`): wrap the `match` in `while true:` and use `continue` to re-dispatch
    or `break` to finish.
  - *A forward jump to a shared tail* (`goto move_stuff`, `goto norm`, `goto bad`):
    move the tail into a local helper `static func _foo_tail(...)` and call it, or use
    a state variable.
  - *A jump into another `case`* (scrolls.c/sticks.c `goto def`, `goto pass`): use a
    small state machine (`var _label := ""`), or factor the target into a helper.
  - Put a `# C: goto <label>` comment where the jump was.

## 6. Strings and formatting
- **Formatting.** `sprintf(buf, fmt, a, b)` → `buf = sprintf(fmt, [a, b])` (C semantics,
  see RogueBase).
  - `printw(fmt, a)` → `printw(fmt, [a])`. `mvprintw(y, x, fmt, a)` →
    `mvprintw(y, x, fmt, [a])`.
  - `msg(fmt, a)` → `await Io.msg(fmt, [a])`. `addmsg(fmt, a)` →
    `await Io.addmsg(fmt, [a])`.
  - C code that passes a variable as the format string (`msg(huh)`, `msg(prbuf)`)
    stays that way: `await Io.msg(huh)`.
- **Building strings.**
  - `strcpy(d, s)` → `d = s`
  - `strcat(d, s)` → `d += s`
  - `strncpy(d, s, n)` → `d = s.substr(0, n)` (check the C intent)
  - `strlen(s)` → `s.length()`
  - `strcmp(a, b) == 0` → `a == b`
  - `strchr(s, c)` → `strchr(s, c)` (an index, or -1 for NULL)
  - `index(s, c)` is the same as `strchr`
  - `atoi(s)` → `atoi(s)`
- **Characters.**
  - `s[i]` / `*s` → `cat(s, i)` / `cat(s, 0)`. `cat` returns 0 past the end, like the
    NUL.
  - `isupper`, `islower`, `isalpha`, `isdigit`, `isprint`, `isspace`, `toupper` and
    `tolower` take and return ints.
  - `chr(c)` makes a one-character String from a code.
  - `unctrl(c)` is curses'.
- **Writing a character into the middle of a buffer** (`buf[i] = c`): rebuild the
  string, e.g. `s = s.substr(0, i) + chr(c) + s.substr(i + 1)`, or keep a
  PackedByteArray while you edit.
- **Static buffers.** Functions that return a C static buffer (`inv_name` → `prbuf`,
  `killname`, `nothing`, `num`, `ring_num`, `charge_str`, `set_mname`) return the String.
  - If C writes the *global* `prbuf`, assign `prbuf` too, because other code reads
    `prbuf` later.
  - `pb = &prbuf[strlen(prbuf)]; sprintf(pb, …)` means "append to `prbuf`".
- **Pointer identity on strings.** If C compares string pointers (`elsewise == *guess`),
  keep the identity semantics; ask in your requests file if unsure.

## 7. Blocking calls and `await` (CRITICAL)
- **The closed list.** `tools/blocking.json` → `"blocking"` lists every function that
  can wait for a key, directly or indirectly, or end the program.
- **A function on the list is a coroutine.**
  - Every call to it must be `await`ed: `await Io.msg("...")`, `ch = await
    Io.readchar()`, `var obj = await Pack.get_item("eat", FOOD)`.
  - A missed `await` silently corrupts the game: the caller runs on while the callee
    waits for a key.
- **A function not on the list must not contain `await`.** Calls to it must not be
  awaited; Godot reports `REDUNDANT_AWAIT` as an error.
  - The exceptions are justified in `blocking.json` → `"port_nonblocking"`: `roomin`,
    `find_obj`, `new_item`, `d_slot`, `inv_name`, `pick_one`, `runto`, `new_thing` and
    `badcheck`.
  - These are not coroutines. Their unreachable or crashing message paths use
    `push_error(...)` instead of `msg`.
- **Primitives that are coroutines** (in RogueBase): `getch()`, `wgetch(win)`,
  `wgetnstr(win, n)`, `fgets_stdin(n)`, `exit(status)`, `abort()` and
  `debug(fmt, args)`.
- **`await` inside conditions keeps C's short-circuit.** `if a and await Misc.get_dir():`
  only calls `get_dir` when `a` is true. A loop condition with a blocking call becomes
  `while true:` plus `break`, as in section 4.
- **No `await` in lambdas, setters, `sort_custom` or `call_deferred`.** A
  function-pointer call becomes a `match` dispatch on an id (see `Daemon._call`).
- **Program exit.** `exit(n)` / `my_exit(n)` → `await Main.my_exit(n)` or
  `await exit(n)`. Execution never continues past it; add a `return` afterwards for
  clarity.

## 8. Global state
- **All mutable state lives in RogueBase.** Use those vars. **Never add `static var`
  to your module.**
  - C file statics are named `_<file>_<name>`; C function statics are named
    `_<function>_<name>` (see the list at the end of `rogue_base.gd`).
- **A function static missing from RogueBase** is one of two things:
  - a constant table → a `const` in your module (arrays of ints or strings), or a
    table of small objects created once;
  - a scratch buffer that is written before it is read on every call → a local
    variable.

  If one *does* need to persist, use a temporary module `static var` marked
  `# REQUEST`, and add it to `docs/requests/<group>.md`.
- **Tables the C code modifies at run time** must live in RogueBase and be rebuilt in
  `reset()`. That covers `monsters`, `*_info` and `helpstr`. If you find another one,
  file a request.

## 9. Curses
- **Use the C names on RogueBase:**
  - stdscr output: `move`, `addch`, `mvaddch`, `addstr`, `mvaddstr`, `printw`,
    `mvprintw`, `clrtoeol`, `clear`, `refresh`, `standout`, `standend`
  - reading the screen: `inch`, `mvinch`
  - window output: `wmove`, `waddch`, `mvwaddch`, `waddstr`, `mvwaddstr`, `wprintw`,
    `mvwprintw`, `wclrtoeol`, `wclear`, `werase`, `wrefresh`, `touchwin`
  - window settings: `clearok`, `leaveok`, `idlok`, `keypad`
  - window management: `newwin`, `subwin`, `delwin`, `mvwin`, `winch`, `mvwinch`,
    `wstandout`, `wstandend`
  - terminal: `endwin`, `isendwin`, `flushinp`, `raw`, `noecho`, `nocbreak`,
    `halfdelay`, `baudrate`, `erasechar`, `killchar`, `unctrl`, `mvcur`
- **Windows and sizes.** `stdscr`, `curscr` and `hw` are available. `LINES` is 24 and
  `COLS` is 80.
- **`getyx(win, y, x)`** → `y = getcury(win)` and `x = getcurx(win)`.
- **Return values.** `inch()`/`mvinch()` return a chtype that includes attribute bits.
  `CCHAR(inch())` gives the character. Comparisons such as `inch() == FLOOR` compare
  the full chtype, exactly like C.
- **stdout.** `printf(fmt, [args])` and `putchar(c)` write the program's stdout stream
  (BEL characters, the post-`endwin` score list). `fgets(buf, n, stdin)` →
  `buf = await fgets_stdin(n)`.

## 10. MASTER (wizard) code
- Port every `#ifdef MASTER` block as `if MASTER:`, and any `#else` branch as `else:`.
  `MASTER` is a runtime flag; the default build has it false.
- `debug(fmt, a)` → `await debug(fmt, [a])`. It only prints when `wizard` is set.

## 11. Undefined behavior
Follow `docs/FIDELITY.md`. If you meet other UB, write the most sensible deterministic
code, mark it `# UB:` with an explanation, and list it in your requests file so the
lead can align the oracle.

## 12. Style and checking
- **Code style.** Use typed GDScript (`var x: int`, typed parameters and return types)
  and tab indentation. Keep functions in C file order, one blank line + `##` comment
  above each.
- **Before you finish, run `tools/check.sh`.** It compiles every script (any parse
  error fails) and runs `tools/lint_await.py`. Both must be clean.
- **Scope.** Only edit your own module files. Write anything you need from foundation
  files into `docs/requests/<group>.md`.
