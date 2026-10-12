# Requests from translation group F

Foundation changes needed, UB found, and notes for the lead.

Group F translated `command.c` → `godot/rogue/command.gd` (class `Command`) and `misc.c` →
`godot/rogue/misc.gd` (class `Misc`).

## Foundation changes
None needed. There are no `# REQUEST` temporaries and no module `static var`s. The function
statics live in RogueBase: `_command_countch`, `_command_direction`, `_command_newcount` and
`_get_dir_last_delt`. The constant tables are module `const`s:
- `Command.IDENT_LIST_CH` / `IDENT_LIST_DESC` (identify's `ident_list`, kept with its `'\0'`
  terminator);
- `Misc.THING_LIST` (rnd_thing's `thing_list`);
- `Command.CTRL_TILDE` (`CTRL('~')` = 0x1E, used by the MASTER charge-stick command; RogueBase only
  has `CTRL_A`..`CTRL_Z`).

## Signatures other groups rely on
- `Misc.add_str(sp: int, amt: int) -> int` (the coordinator's contract). It returns the new `*sp`.
  It computes `(sp + amt) & 0xFFFFFFFF` (str_t is unsigned) and then clamps to 3..31, so
  `add_str(3, -5)` is 31, as in C.
- `Misc.call_it(info: ObjInfo)`. C passes `&pot_info[i]`; the port passes the ObjInfo itself
  (`Misc.call_it(pot_info[obj.o_which])`). potions.gd and scrolls.gd already do this.
- `get_str` is called per the contract:
  `var r: Array = await Options.get_str(prbuf, stdscr); prbuf = r[1]; if r[0] == NORM: ...`.
  The call sites are `Command.call_()` and `Misc.call_it()`. The screen depends on prbuf's old
  contents, because get_str echoes `opt` when nothing is typed. So every C writer of the global
  `prbuf` must keep assigning it.
- `Misc.find_obj(y, x) -> Thing` is not a coroutine. On its MASTER "Non-object" path it assigns
  `prbuf` (C's `sprintf(prbuf, ...)`) and then calls `push_error(prbuf)` instead of `msg(prbuf)`.
  This is the documented FIDELITY deviation.
- `Misc.sign(nm)` is `Misc.sign_(nm)` in the port: an unqualified `sign()` call reaches GDScript's
  global `sign()` first (CONVENTIONS.md §1).
- `Misc.erase_lamp(pos: Coord, rp: Room)`, `Misc.trip_ch(y, x, ch) -> int`,
  `Misc.show_floor() -> bool`, `Misc.vowelstr(str_: String) -> String`,
  `Misc.choose_str(ts: String, ns: String) -> String`, `Misc.rnd_thing() -> int` and
  `Misc.spread(nm: int) -> int` are plain functions. `Misc.aggravate()` and `Misc.chg_str(amt)` are
  also plain, since runto is non-blocking.
- `Command.current(cur: Thing, how: String, where: Variant)`. `where` is null for C's NULL. It is
  only called from command.c.

## Places where the port is not literal C (behavior is unchanged)
- **`command()`**
  - `goto over` (4 sites) is `while true: match ch:`, with `continue` to re-dispatch and a
    trailing `break`. C's `break` inside `case 'f'` becomes `break`, which leaves the loop.
  - The real fallthrough from `'F'` into `'f'` is one branch with `if ch == ord("F"): kamikaze =
    true`. `kamikaze` stays set when get_dir fails, as in C.
  - `CTRL('D')`/`CTRL('A')` in the count list exist only `#ifdef MASTER`. Ported as their own
    branch that does `count = 0` when `not MASTER`.
  - The MASTER-only `'+'` case cannot be left out of a `match`. With `not MASTER` it runs C's
    non-MASTER `otherwise:` body (`after = false; illcom(ch)`).
  - The wizard sub-switch is `if MASTER and wizard: match ch: ... else: illcom(ch)`. This matches
    C's `#ifdef MASTER if (wizard) switch ... else #endif illcom(ch);`.
  - `exit(1)` (the anti-tamper check) is `await exit(1)` followed by `return`.
  - `noscore = TRUE` is written `noscore = 1`, because noscore is an `int` in RogueBase.
  - `wizard = passwd();` is written `wizard = bool(await Wizard.passwd())`. This works whether
    group E types passwd as int or bool.
  - `pick_up((char)obj->o_type)` is written `Pack.pick_up(to_schar(obj.o_type))`.
- **`search()`**: `goto foundone` uses a `foundone` state flag. The label's code runs after the
  `match`. The `'|'`/`'-'` case reaches it by falling in; FLOOR and `' '` reach it by goto.
- **`call()`** → `call_()`
  - `goto norm` uses a `norm` flag.
  - `char **guess` is `guess_op` (an ObjInfo, for `&op->oi_guess`) or null (for `&obj->o_label`).
  - `bool *know` is `know_op`.
  - C's pointer comparison `elsewise == *guess` keeps its identity meaning through a flag that is
    set exactly where elsewise is loaded from `*guess`. A content comparison would give the same
    result here, because `oi_guess` is always its own malloc'd copy.
- **`help()`**: walks `helpstr` (RogueBase) with `for strp: HList in helpstr` and stops at the
  `h_desc == null` terminator.
- **`look()`**: `char *fp = &pp->p_flags` is the Place `fp` itself. The `#ifdef DEBUG` guard is
  compiled out in C (`#undef DEBUG`), so it is not ported.

## Undefined behavior
Nothing new. The only out-of-range accesses in these files are the `x == -1` squares that FIDELITY
already covers:
- `search()` with the hero at x == 0 in a left-column maze;
- `^`, `f` and `F` with a direction toward x == -1.

The dummy square reads as `' '` with flags 0. So `search()` draws `rnd(3 + probinc)` for each of the
3 dummy squares. A draw of 0 sets `found` and clears `count` and `running` (the write of PASSAGE is
discarded), and then `look(FALSE)` runs. The oracle's dummy must also read `' '` for this to match.
FIDELITY says it does.

## Tooling note
`GODOT=/root/bin/godot tools/check.sh --quick godot/rogue/command.gd godot/rogue/misc.gd` currently
prints `check: compile FAILED`. The cause is not in these files:
- the isolated copy restores `rogue_base.gd` from HEAD;
- but the untracked `godot/tests/replay.gd` uses `RogueBase.env_cwd`, which exists only in the
  uncommitted working-tree `rogue_base.gd`.

The output shows `checked 50 scripts, 0 failed` and the only error is `res://tests/replay.gd:77`.
Adding `godot/rogue/rogue_base.gd` to the file list gives `compile: OK`. The lint reports
0 problems in both files.
