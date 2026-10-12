# Requests from translation group C

Foundation changes needed, UB found, and notes for the lead.

Files: `pack.gd`, `things.gd`, `weapons.gd`, `armor.gd`, `rings.gd` (pack.c, things.c,
weapons.c, armor.c, rings.c).

## Requests

1. **`RogueBase.sprintf`: `%c` with a NUL char should end the string.**
   - In C, the formatted text ends at the NUL. Every Rogue consumer reads the result as
     a C string (`strlen`/`strcat` in `doadd`, `waddstr` in `printw`, and so on).
   - In the port, `char(0)` is not empty. Godot 4.7 turns it into U+FFFD and prints
     "Unicode parsing error". So `sprintf("%c) %%s", [0])` gives U+FFFD followed by `") %s"`,
     where C gives `""`.
   - Suggested fix: in the `%c` branch, `if (v & 0xFF) == 0: return out`. Also make
     `chr(0)` return `""`.
   - It is reachable through the original's `add_pack()` empty-pack quirk. Floor objects
     that never got a pack letter (`o_packch` 0) end up in the pack list, and `i` then
     formats `"%c) %%s"` with 0. In C, `inv_temp` is `""` and the line is empty.
   - `Pack.inventory` has a local workaround marked `# REQUEST`. It can go once
     `sprintf` is fixed.
   - Not worked around (same quirk): `add_pack`'s `"%s (%c)"` after merging into such an
     object, and `picky_inven`'s `"%c) %s"` if the player types NUL.
2. **`RogueBase._things_lastarg` should be a `Variant` (String or null).**
   - C's `lastarg` can be NULL: `add_line(nothing(type), NULL)`.
   - `Things.add_line` stores `""` for NULL, marked `# REQUEST`. This is equivalent:
     `end_line()` reads lastfmt/lastarg only right after the list's single `add_line()`,
     and a NULL arg only ever comes with a format that has no conversion.
   - `_things_lastfmt` can stay a String, because it is only stored when fmt != NULL.
3. **Curses emulation: `touchwin(null)` and `leaveok(null)` crash. ncurses returns
   ERR.**
   - `add_line()`'s INV_OVER branch calls both on `tw = newwin(...)`. `tw` is NULL when
     `maxlen >= 78`: `begx = COLS - maxlen - 3` goes negative. That needs a listed line
     ending at column 78 or later, which only long typed names (`call`) can produce.
   - `wmove`, `waddch`, `waddstr`, `wrefresh`, `werase`, `mvwin`, `subwin` and `delwin`
     already return ERR for null.

## UB and original bugs found (port behavior)

- **`fall()` reads past `weap_info[]` (reachable in normal play; please pin it in
  oracle.patch).**
  - `missile()` throws any pack object (get_item's type only filters the `*` list).
    When the thrown object finds no FLOOR/PASSAGE square to land on, fall() prints
    `"the %s vanishes as it hits the ground"` with `weap_info[obj->o_which].oi_name`.
  - For a potion, scroll, ring or stick with `o_which >= MAXWEAPONS + 1` (10..17), that
    reads past the table.
  - In the std and master oracle builds (gcc -O2, checked with `nm -n`), `scr_info[]`
    directly follows `weap_info[]`. So C prints `scr_info[o_which - 10].oi_name`, for
    example "The monster confusion vanishes as it hits the ground".
  - The **cov** build lays the arrays out differently: `ws_info[]` follows
    `weap_info[]`. It would print a wand name instead.
  - The port mirrors the std/master layout explicitly
    (`Weapons._weap_info_name()`, `# UB:`).
  - Suggested oracle.patch line in fall():
    `obj->o_which <= MAXWEAPONS ? weap_info[obj->o_which].oi_name :
    scr_info[obj->o_which - (MAXWEAPONS + 1)].oi_name`.
  - Found by my scenario tests: a thrown scroll with `o_which` 10 or 11 in a room corner.
  - `weap_info[FLAME]` (9) stays in range. Its name is NULL until a dragon breathes,
    giving "(null)", as glibc prints it.
- **Wizard `create_obj()` can make objects with `o_which` past their tables** (any key
  'a'..'z' gives 10..35). `inv_name`/`nameit` then read past `p_colors[]`,
  `pot_info[]`, `arm_info[]`, `a_class[]` and so on, and `ring_eat` reads past
  `uses[]`. The port gets GDScript index errors there. MASTER only, not guarded.
- **`add_pack()` empty-pack quirk can make `lvl_obj` cyclic (FIDELITY "kept on
  purpose").**
  - `pack = obj` leaves obj linked in `lvl_obj`. If obj is `lvl_obj`'s head and is then
    dropped or thrown, `leave_pack()` detaches it from `pack` while `lvl_obj` still
    points at it. `attach(lvl_obj, obj)` then sets `obj->l_next = obj`.
  - Every later `lvl_obj` walk loops forever, in C and in the port alike: `find_obj`,
    `find_dest`, and the step-log digests (`hooks.c digest()`, `replay.gd`). Neither
    digest bounds its walks.
  - The oracle is therefore killed by difftest's timeout. Real play reaches this with
    "drop everything, pick up the last dropped item, drop or throw it again".
  - Please decide how difftest should score "both hang".
- **`leave_pack()`: `pack_used[obj->o_packch - 'a'] = FALSE` with `o_packch` 0** (same
  quirk; also a nymph stealing such an object). C writes 97 bytes before
  `pack_used[]`. The port drops the write (`# UB:` in `Pack.leave_pack`).
- **`pack_char()` with all 26 letters in use** (only through the same quirk). C reads
  and writes past `pack_used[]`. The port treats the slot past the end as free, drops
  the write and returns `'{'` (`# UB:` in `Pack.pack_char`).
- **`init_weapon()` with `which` outside 0..8.** Only the wizard's `create_obj()` can
  pass it (`'9'`, letters, other keys). C reads past `init_dam[]`, and
  `inv_name()`/`weap_info[]` follow. The port gets a GDScript index error. It is marked
  `# UB:` and not guarded.
- Kept as in C:
  - `add_pack()`'s group merge adds `o_count` before calling `pack_room()`.
  - `inv_name()`'s non-MASTER default case leaves `prbuf` stale.
  - `delwin(tw)` fails because the subwindow `sw` is never deleted. The emulation fails
    the same way.
  - `ring_off()` prints `"was wearing %s(%c)"` with no space.

## Deviations from literal C (all behavior-preserving)

- **nameit()'s `prfunc`** (`nullstr`, `ring_num` or `charge_str`) is a StringName id
  (`Things.PRF_*`), called through `Things._prfunc()`. Only things.c passes it.
- **MASTER debug paths use `push_error` instead of `msg`** (blocking.json
  port_nonblocking): `inv_name` ("Picked up something funny"), `new_thing` ("Picked a
  bad kind of object" + `wait_for`, unreachable) and `pick_one` ("bad pick_one",
  unreachable). `pick_up`'s MASTER `debug()` is a real `await debug(...)`, then the C
  fallthrough into `add_pack`.
- **Static scratch buffers become locals.** Each is rewritten before every read:
  `inventory`'s `inv_temp`, `print_disc`'s `order[]`, `num`'s `numbuf`, `ring_num`'s
  `buf`. The AUDIT found no aliasing.
- **Persistent statics use RogueBase:** `_print_disc_obj`, `_fall_fpos`,
  `_hit_monster_mp`, `_things_*`, `_add_line_maxlen`, `group`.
- **goto rewrites.** `add_pack`'s `goto dump_it` / `goto out` duplicate the 3-line
  dump_it tail and then `break`. `wield`'s `goto bad` duplicates `after = false;
  return`.
- **Unreachable return.** `gethand()` has a `return -1` after its `for (;;)` loop.

## Signatures other groups call (C types kept)

- `Things.inv_name(obj, drop) -> String` (sets and returns `prbuf`, not a coroutine).
- `Pack.get_item(purpose, type_) -> Thing`, `Pack.add_pack(obj, silent)` and
  `Pack.inventory(list, type_) -> bool` are coroutines.
- `Pack.leave_pack(obj, newobj, all) -> Thing`, `Pack.floor_ch()/floor_at() -> int` and
  `Things.new_thing() -> Thing` are not coroutines.
- `Weapons.hit_monster(y, x, obj) -> int` is a coroutine. It returns
  `Fight.fight(...)`.
- `Weapons.fallpos(pos: Coord, newpos: Coord) -> bool` writes into `newpos`, for
  example `tp.t_room.r_gold`.
- `Weapons.do_motion(obj, ydelta, xdelta)` and `Weapons.init_weapon(weap, which)` are
  not coroutines.
- `Rings.ring_eat(hand) -> int`, `Rings.ring_num(obj) -> String` and
  `Weapons.num(n1, n2, type_) -> String` are not coroutines.
- `Armor.waste_time()` is a coroutine.

## Verification done (scratchpad only, nothing committed)

- **C test vectors from the oracle objects**, replayed through the port: 88k checks
  identical for `num`, `nothing`, `set_order`, `pick_one`, `init_weapon`, `ring_eat`,
  `ring_num`, `fallpos`, `new_thing` (fields and seed), `inv_name` (all types,
  know/guess/label/terse/describe/worn flags, drop) and `pack_char`.
- **About 250 scenario tests, linked against the oracle objects.** Screens, cursor and
  seed were identical at every key, and pack, level and globals after every op.
  - The scenarios mix `add_pack`/`pick_up`, merges and groups, a full pack, scare
    scrolls, gold, the amulet, `inventory` in all 3 styles, `get_item` (with `*`, ESC
    and `again`), `drop`, `leave_pack`, `discovered`, `picky_inven`,
    `wear`/`take_off`/`wield`, `ring_on`/`ring_off`/`gethand`, and `missile`/`fall` in
    a walled room.
  - A MASTER variant adds `pr_list`/`pr_spec`.
  - These tests found the `fall()` UB above.
- **Full game:** `harness/difftest.py` with HEAD plus these 5 files. All runs were
  identical:
  - 334 fuzz runs: default options, `inven=overwrite`, `inven=slow,terse`,
    `inven=overwrite,terse`, and the MASTER build;
  - 16 recorded explorer-bot games.
