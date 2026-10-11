# Fixes for bugs of Rogue 5.4.4 (`RogueBase.fixes`)

The port is a 1:1 translation of Rogue 5.4.4, bugs included. The switch `RogueBase.fixes`
turns on fixes for the known bugs listed here. It is set by the host like `MASTER` and
left alone by `reset()`; `godot/tests/replay.gd` turns it on only for runs that ask
(`--fixes`, or `fixes=1` in a batch line), so the classic game stays differential-tested
against the stock C.

**How a fix is written.** At the bug site, in the port:

```gdscript
if fixes:	# FIX <id>: <what>
	<fixed code>
else:
	<original code, unchanged>
```

or the smallest equivalent that leaves the original path exactly as it was.

**The fixed C.** The same fixes are in `harness/oracle/fixes.patch`, applied on top of
`oracle.patch` for the oracle variants `fixed` and `fixedmaster`
(`harness/oracle/build.sh`). The one fix in `hooks.c` (27) is under `#ifdef
ORACLE_FIXES`. Each C fix makes the same RNG calls in the same order as its GDScript
twin, so `difftest.py MODE --fixes` compares the fixed port with the fixed C step by
step, exactly as the classic port is compared with the stock C. To change the C side:
`harness/oracle/edit_fixes.sh DIR`, edit `DIR/b`, `harness/oracle/edit_fixes.sh --diff
DIR`, rebuild `fixed` and `fixedmaster`.

**Tests.**
- `harness/corpus/fixes/<id>-<slug>.keys`: one script per fix that reproduces the bug.
  It runs in both modes (`harness/run_all.sh` runs the corpus classic and `--fixes`).
  Its `# expect-classic:` lines show the bug where it is visible, its `# expect-fixed:`
  and `# expect-not-fixed:` lines show the fix (`# expect-not-classic:` lines are used
  where only the fixed game shows something). `difftest.py` checks them against every
  screen and the stdout of the port's run in that mode.
- `godot/tests/fixes_test.gd` checks what the scripts cannot: the keypad mapping (1),
  that every level of the seeds that made `conn()` hang is connected (8), and the
  standout of the wizard's map (N12).
- The fixed sweeps (`difftest.py seeds|fuzz|saves --fixes`) cover the fixes that random
  play reaches often (2, 3, 9, 11, 14, 26, N1, N2, N12, ...) and check that the port and
  the C implement them identically.
- `harness/show.py KEYFILE --step N --port --fixes` shows a step of the fixed game.

Ids are those of the review that found the bugs: numbers for the first list, `D1` from
`docs/requests/D.md`, `N…` for later finds. Line numbers are those of the original C
sources at the repository root.

| Id | Bug | Script |
|---|---|---|
| 1 | keypad 5 is `u` | (fixes_test.gd) |
| 2 | `F` leaves `kamikaze` set | `2-kamikaze-leak` |
| 3 | `relocate()` never calls `find_dest()` | `3-relocate-find-dest` |
| 4 | `find_dest()` reuses its parameter as a loop variable | (sweeps) |
| 5 | `add_pack()` into an empty pack leaves the object on the floor list | `5-pickup-empty-pack` |
| 7 | `save_game()` unlinks the old save name | `7-save-unlink-old-name` |
| 8 | `conn()` hangs on a maze with no passage where the door must go | `8-conn-maze-door` |
| 9 | "frozen by the the ice monster" | `9-frozen-by-the` |
| 10 | "was wearing ...(f)" | `10-ring-off-space` |
| 11 | a thrown non-weapon vanishes under a weapon's name | `11-fall-name` |
| 12, N6 | create monster on a disguised xeroc | `12-create-monster-on-xeroc` |
| 13 | wizard: `fight()` with no monster crashes | `13-fight-nothing` |
| 14 | raise level at experience level 21 drops to level 1 | `14-raise-level-21` |
| 22 | wizard gold is stored as a short | `22-wizard-gold-int` |
| 26 | venus flytrap damage | `26-flytrap-damage` |
| 27 | off-map squares searched as hidden passages | `27-search-off-map` |
| 28 | player text used as a format string | `28-player-text-format` |
| 29 | overwrite inventory draws nothing for wide lines | `29-inven-overwrite-wide` |
| 30 | monster detection fills the daemon slots | `30-monster-detection-fuse` |
| D1 | magic missile without a weapon always misses | `D1-magic-missile-no-weapon` |
| N1 | a wraith's drain gives the level back at the next kill | `N1-wraith-drain-exp` |
| N2 | the `amulet` flag survives throwing or theft | `N2-amulet-flag-thrown` |
| N3 | merging pickup leaves pursuers with a dangling target | `N3-merge-pickup-pursuer` |
| N4 | nymph theft from a stack | `N4-nymph-steals-from-stack` |
| N5 | a monster killed during `runners()` | `N5-dragon-kills-next` |
| N8 | treasure room object on an occupied square | `N8-treasure-room-full` |
| N10 | stairs left scrambled after hallucination | `N10-stairs-after-trip` |
| N11 | scroll titles with a trailing or doubled space | `N11-scroll-title-space` |
| N12 | wizard map mostly in standout | `N12-show-map-standout` (+ fixes_test.gd) |
| N13 | wizard ^I with a full pack wields/wears outside the pack | `N13-wizard-power-full-pack` |
| N14 | wizard: `wake_monster()` with no monster crashes | `N14-wake-nothing` |
| typos | seven misspelled messages | `typos-messages`, `typos-pack-turns`, `typos-capabilities` |

## 1. Keypad 5 is "u"
- **Player saw:** the keypad's center key moved the hero up and right instead of resting.
- **Cause:** `mdport.c:1229-1230` maps `KEY_B2` to `'u'` ("next should be '.', but for
  problem with putty/linux"); `TerminalView` turns `KEY_KP_5` into `KEY_B2`.
- **Port:** UI only: `TerminalView.key_code()` returns `'.'` for `KEY_KP_5` when
  `fixes` is on. `md_readchar()` is unchanged.
- **C:** none (the oracle reads key codes, not a terminal).
- **Test:** `godot/tests/fixes_test.gd` (keypad 5 is `KEY_B2` without the fixes, `'.'`
  with them).

## 2. `F` leaves `kamikaze` set
- **Player saw:** after an `F` that found no monster (or ended without a death), a
  later `f` ("fight till death or near death") fought to the death.
- **Cause:** `command.c:214-233`: `case 'F': kamikaze = TRUE; /* FALLTHROUGH */ case
  'f':`; nothing clears `kamikaze` after "no monster there", a failed `diag_ok()` or a
  fight interrupted by `runners()`, confusion, hunger or the quit prompt. Its reader is
  `fight.c:179`.
- **Port:** `command.gd`, F/f case: `kamikaze = ch == ord("F")`.
- **C:** `command.c`: `kamikaze = (ch == 'F');` at the top of the merged case.
- **Script:** `2-kamikaze-leak`: level 5, `F` at an empty square, then `f` at a
  hobgoblin: classic fights on to "You have defeated the hobgoblin"; fixed stops near
  death and the hobgoblin goes on hitting.

## 3. `relocate()` never calls `find_dest()`
- **Player saw:** nothing obvious: a monster that wants objects (`m_carry`) and walks
  into another room never looks for objects there; it goes on chasing the hero.
- **Cause:** `chase.c:89-95`: `oroom = th->t_room` is read after `t_room` was updated,
  so `if (oroom != th->t_room) th->t_dest = find_dest(th);` never runs.
- **Port:** `Chase.relocate()`: with the fixes `oroom` is taken before the update
  (`set_oldch()` still runs after it).
- **C:** `chase.c` `relocate()`: `oroom = th->t_room;` moved before the update.
- **Script:** `3-relocate-find-dest`: wizard, level 13, a nymph (which wants any
  object) zapped with teleport away into another room: classic goes on chasing the
  hero; fixed goes for the food ration of its new room and takes it (the wizard map
  shows the ration gone). `find_dest()` draws `rnd(100)`, so the fix changes the course
  of many games: about 1 in 1000 random scripts and about 45% of the explorer bot's deep
  wizard games, all compared step by step with the fixed C by the sweeps.

## 4. `find_dest()` reuses its parameter as a loop variable
- **Player saw:** nothing obvious: a monster could pick its target by another monster's
  room.
- **Cause:** `chase.c:509-515`: `for (tp = mlist; ...) if (tp->t_dest == &obj->o_pos)
  break;` overwrites `tp`, the monster looking for a destination; for the next objects
  `roomin(&obj->o_pos) == tp->t_room` uses the room of the monster that wanted the last
  object.
- **Port:** `Chase.find_dest()`: a separate loop variable `mp`.
- **C:** `chase.c` `find_dest()`: `register THING *mp;` for the inner loop.
- **Script:** none: the result differs only when a monster that already wants an object
  of this room stands in another room and more objects follow in `lvl_obj`. In 1,300
  explorer-bot deep wizard games and 3,000 random wizard scripts, run on a C build that
  computes both versions side by side, the inner loop found a pursuer in 17 games and the
  two versions never differed. Covered by review and the sweeps.

## 5. `add_pack()` into an empty pack
- **Player saw:** with an empty pack, the item picked up stayed on the map and in the
  level's object list: the inventory listed floor items too, dropping it again made
  the list circular (the game hung), picking it up again duplicated it, `m` onto it
  crashed.
- **Cause:** `pack.c:53-58`: `if (pack == NULL) { pack = obj; obj->o_packch =
  pack_char(); inpack++; }` skips `pack_room()`, which detaches the object from
  `lvl_obj` and repaints the floor.
- **Port:** `Pack.add_pack()`: `if not await pack_room(from_floor, obj): return`, then
  `pack = obj; obj.o_packch = pack_char()` (`pack_room()` counts the item; it cannot
  fail with an empty pack; `init_player()` passes `from_floor` false; no RNG). The
  classic guards (`List._attach()`, `Curses.doomed`) stay for classic mode.
- **C:** the same in `pack.c` `add_pack()`.
- **Script:** `5-pickup-empty-pack`: drop all five items, pick the arrows up again: the
  classic inventory lists the floor items ("d) A +1,+0 short bow"); fixed only the
  arrows.

## 7. `save_game()` unlinks the old save name
- **Player saw:** saving over an existing file of another name deleted the previous
  save file (`rogue.save`).
- **Cause:** `save.c:104`: `msg("file name: %s", buf); md_unlink(file_name);` removes
  `file_name` (the previous name), not `buf`. (In C the existing target is mode 0400,
  so `fopen()` then fails unless running as root; the port's `md_chmod()` is a no-op.)
- **Port:** `Save.save_game()`: `Mdport.md_unlink(buf)`.
- **C:** `save.c`: `md_unlink(buf);`.
- **Script:** `7-save-unlink-old-name` (a chain): game 1 saves to `./rogue.save`, game 2
  to `foo`, game 3 overwrites `foo`; `rogue -r` then fails in classic (exit 1) and
  restores game 1 with the fixes (`v` shows the version).

## 8. `conn()` hangs on a maze room
- **Player saw:** the game froze while making a level (the port and the oracle end it
  after 10,000 tries: "the level generator is stuck", exit 1).
- **Cause:** `passages.c:174-178` (and the three sibling loops): the door-picking
  `do { ... } while ((r_flags & ISMAZE) && !(flat(...) & F_PASS))` waits for a passage
  square among squares 1..r_max-2 of the room's bottom row (right column, ...). Maze
  cells are at even offsets (`rooms.c:230-293`); a maze on the top row is shortened
  (`rooms.c:101-105`), so its bottom row `r_max.y - 1` is a row between two rows of
  cells, with passage squares only where the maze links them, and possibly none in
  range.
- **Port:** `Passages.conn()`: before each of the four loops, `_maze_door(room, y, x,
  dy, dx, n)`: if the room is a maze and none of the n squares has `F_PASS`, `putpass()`
  one at the even offset `2 * (rnd(n / 2) + 1)` (an even offset links two cells; an odd
  one would touch none and disconnect the level). Then the original loop runs.
- **C:** `passages.c`: the same `maze_door()` and the same four calls.
- **Script:** `8-conn-maze-door`: MASTER seed 1659, four `^D`: classic stops ("the
  level generator is stuck"); fixed makes level 5 and shows its map.
  `godot/tests/fixes_test.gd` checks that every level of the 7 seeds below 3000 whose
  `^D` descents hang (1083, 1344, 1438, 1457, 1632, 1659, 1786) and of seeds 1-20 is
  connected (stairs and every room reachable from the hero, through secret doors and
  passages), 41 levels each.

## 9. "frozen by the the ice monster"
- **Player saw:** "You are frozen by the the ice monster".
- **Cause:** `fight.c:204`: `addmsg(" by the %s", mname)` but `set_mname()`
  (`fight.c:353-369`) already returns "the <name>" (or "something"/"it").
- **Port / C:** `" by %s"` (`Fight.attack()`, `fight.c` `attack()`).
- **Script:** `9-frozen-by-the` (a random wizard script cut after the message).

## 10. "was wearing ...(f)"
- **Player saw:** "Was wearing a germanium ring(f)".
- **Cause:** `rings.c:122`: `"was wearing %s(%c)"`.
- **Port / C:** `"was wearing %s (%c)"` (`Rings.ring_off()`, `rings.c`).
- **Script:** `10-ring-off-space`.

## 11. A thrown object vanishes under a weapon's name
- **Player saw:** throwing a potion where it cannot land said "The arrow vanishes as it
  hits the ground"; a ring "The (null) vanishes"; a scroll a scroll name.
- **Cause:** `weapons.c:149-150`: `weap_info[obj->o_which].oi_name` for any object
  (`missile()` throws anything); past the table the std/master builds read
  `scr_info[]` (docs/FIDELITY.md).
- **Port:** `Weapons.fall()`: `_fall_name(obj)`: weapons and armor by their table
  name, "potion", "scroll", "ring", the stick's `ws_type` ("wand"/"staff"), the fruit
  name or "food", "Amulet of Yendor" ("object" for anything else, e.g. wizard gold).
- **C:** `weapons.c`: `fall_name()`, the same.
- **Script:** `11-fall-name`: six objects thrown diagonally into a room corner.

## 12 (and N6). Create monster on a disguised xeroc
- **Player saw:** reading create monster next to a xeroc disguised as an object could
  put the new monster on the xeroc's square, orphaning the xeroc (it stays in the
  monster list but no longer on the map); with a `?` disguise the game crashed.
- **Cause:** `scrolls.c:128-144`: `else if (step_ok(ch = winat(y, x)))`: `winat()`
  returns the disguise; with `'?'`, `find_obj(y, x)` returns NULL and is dereferenced.
- **Port:** `Scrolls.read_scroll()` S_CREATE: with the fixes a square holding a monster
  is skipped (`moat(y, x) != null`), and a NULL `find_obj()` is not dereferenced.
- **C:** `scrolls.c`: `else if (moat(y, x) == NULL && step_ok(ch = winat(y, x)))` and
  `(sobj = find_obj(y, x)) != NULL && sobj->o_which == S_SCARE`.
- **Script:** `12-create-monster-on-xeroc`: a recorded explorer-bot game (level 16)
  with a xeroc disguised as `*` next to the hero: classic creates a quagga on it,
  fixed a centaur elsewhere. (The crash case needs a `?` disguise; none came up.)

## 13. Wizard: `fight()` with no monster
- **Player saw (wizard):** walking into an object whose type is a monster letter
  (`C F 0`): "Fight what @ y,x", then the game crashed.
- **Cause:** `fight.c:73-90`: `tp` is NULL; `runto()` (`chase.c:293-304`) and the rest
  dereference it.
- **Port:** `Fight.fight()`: with the fixes it returns false after the MASTER
  message; classic keeps the crash (exit 139, docs/FIDELITY.md).
- **C:** `fight.c`: `if (tp == NULL) return FALSE;`.
- **Script:** `13-fight-nothing`.

## 14. Raise level at experience level 21
- **Player saw:** a potion of raise level (or the wizard's `^I`) at level 21 dropped the
  hero to level 1.
- **Cause:** `potions.c:346` with `e_levels[]` (20 entries and a 0): at level 21
  `s_exp = e_levels[20] + 1 = 1`, and `check_level()` (`misc.c:327-332`) sets level 1.
- **Port / C:** `raise_level()` returns at the top level (`e_levels[s_lvl-1] == 0`);
  the potion's message is unchanged.
- **Script:** `14-raise-level-21`: three `^I`: classic ends at level 7, fixed at 21.

## 22. Wizard gold stored as a short
- **Player saw (wizard):** creating 100000 gold gave 34464.
- **Cause:** `options.c:381,386`: `get_num()` writes `(short) atoi(buf)` through a
  `short *` into the int `o_goldval` (`wizard.c:188`).
- **Port:** `Options.get_num()`: the whole int (`_to_int32(atoi(buf))`).
- **C:** `options.c`: `int *opt = (int *) vp; *opt = atoi(buf);`.
- **Script:** `22-wizard-gold-int`.

## 26. Venus flytrap damage
- **Player saw:** a flytrap's hits did 1 HP however long it held the hero, its misses
  did more and more, and later flytraps started stronger.
- **Cause:** `fight.c:270`: `sprintf(monsters['F'-'A'].m_stats.s_dmg, "%dx1", ++vf_hit)`
  escalates the template, but each monster has its own copy of `s_dmg`
  (`monsters.c:79`); misses do `pstats.s_hpt -= vf_hit` (`fight.c:326-331`); `vf_hit`
  is not reset when the hold ends on a new level (`new_level.c:30`) or by zapping the
  flytrap (`sticks.c:118-119`). (`killed()` and the wizard's teleport already reset it.)
- **Port:** `Fight.attack()`: `mp.t_stats.s_dmg = sprintf("%dx1", [vf_hit])`;
  `NewLevel.new_level()` and `Sticks.do_zap()` reset `vf_hit`. No new saved state
  (monster stats and `vf_hit` are already saved).
- **C:** the same in `fight.c`, `new_level.c`, `sticks.c`.
- **Script:** `26-flytrap-damage`: held, the hero searches 6 turns: classic HP 63 to 57,
  fixed 63 to 36.

## 27. Off-map squares searched as hidden passages
- **Player saw:** at x = 0 (left-column mazes), a counted search could stop early.
- **Cause:** `rogue.h:74-77`: `INDEX(y, -1)` (oracle and port: a dummy square, flags 0,
  docs/FIDELITY.md); `search()` (`command.c:492-527`) takes a square without `F_REAL`
  for a hidden passage and rolls `rnd()` on it.
- **Port:** `RogueBase.INDEX()`: the dummy has `F_REAL` with the fixes.
- **C:** `harness/oracle/hooks.c` `oracle_place()`: `dummy.p_flags = F_REAL` under
  `#ifdef ORACLE_FIXES`.
- **Script:** `27-search-off-map`: a recorded explorer-bot game with the hero at (1,0):
  `20s`, then the wizard's food counter: classic 769 (one turn), fixed 750.

## 28. Player text used as a format string
- **Player saw:** a `%` in a fruit name (ROGUEOPTS `fruit=`) or in a name the player gave
  was interpreted by `printf` (missing arguments: garbage in C).
- **Cause:** `potions.c:167+374` (the see-invisible message built with the fruit is
  passed as the format of `msg()`), `wizard.c:72` (`msg(inv_name(...))`),
  `command.c:287` (`^P`: `msg(huh)`).
- **Port / C:** `msg("%s", s)` at the three sites.
- **Script:** `28-player-text-format`: `fruit=a%%%%b` (so that classic stays defined):
  classic shows "a%%b", fixed "a%%%%b".

## 29. Overwrite inventory with a wide line
- **Player saw:** with `inven=overwrite`, an inventory whose widest line ended at column
  78 or 79 showed nothing and waited for space.
- **Cause:** `things.c:503-525`: `newwin(..., COLS - maxlen - 3)` with a negative column
  returns NULL; every following call fails.
- **Port:** `Things.add_line()`: with the fixes the overwrite window is used only if
  `COLS - maxlen - 3 >= 0`; otherwise the list is shown a page at a time.
- **C:** `things.c`: the same condition.
- **Script:** `29-inven-overwrite-wide`: a ring called with a 45-character name.

## 30. Monster detection fills the daemon slots
- **Player saw:** overlapping potions of monster detection ended with the first one;
  about 15 overlapping potions crashed the game.
- **Cause:** `potions.c:114`: each potion adds a new `turn_see` fuse
  (`daemon.c:33-43,125`); with all 20 slots in use `d_slot()` returns NULL and `fuse()`
  dereferences it.
- **Port:** `Potions.quaff()` P_MFIND: if the fuse is burning, `lengthen()` it by
  HUHDURATION (as other potions do); else `fuse()` as before.
- **C:** `potions.c`: `find_slot()` / `lengthen()`.
- **Script:** `30-monster-detection-fuse`: three potions, 30 turns later classic shows no
  monsters (its first 20-turn fuse ended the detection), fixed still does (one 60-turn
  fuse). The crash itself is not scripted: the port reports `d_slot()`'s failure with
  `push_error` (blocking.json `port_nonblocking`), unlike C.

## D1. Magic missile without a weapon
- **Player saw:** zapping magic missile with no wielded weapon never hit ("You missed").
- **Cause:** `sticks.c:182-183` (WS_MISSILE): the `static THING bolt` gets `o_launch`
  only `if (cur_weapon != NULL)`; otherwise it keeps an older launcher (or 0), so
  `roll_em()` uses the empty `o_damage` instead of `o_hurldmg` "1x4".
- **Port / C:** `else bolt.o_launch = -1;`.
- **Script:** `D1-magic-missile-no-weapon`: the mace dropped, a kestrel zapped: classic
  "You missed the kestrel", fixed "You have defeated the kestrel".

## N1. A wraith's drain gives the level back
- **Player saw:** after a wraith drained a level, the next kill showed "Welcome to level
  N" and restored it.
- **Cause:** `fight.c:246-252`: after `--s_lvl`, `s_exp = e_levels[s_lvl-1] + 1`, the
  experience of the old level (level L needs `e_levels[L-2]`).
- **Port / C:** `s_exp = s_lvl >= 2 ? e_levels[s_lvl-2] + 1 : 1` (the `s_lvl == 0`
  branch is unchanged).
- **Script:** `N1-wraith-drain-exp`: drained 10 to 9 to 8, the hero kills the wraith:
  classic "Exp: 9/1359" (level 9 again), fixed "Exp: 8/699".

## N2. The `amulet` flag survives throwing or theft
- **Player saw:** after throwing the Amulet (or a nymph stealing it) the hero could
  still climb out and win, hunger nearly stopped, no new Amulet appeared below level 26.
- **Cause:** only `drop()` (`things.c:166-167`) clears `amulet`; throwing
  (`weapons.c:56`) and theft (`fight.c:301-312`) go through `leave_pack()` too.
- **Port / C:** `leave_pack()`'s remove branch clears `amulet` when the object is the
  Amulet (it covers every path: drop, throw, theft).
- **Script:** `N2-amulet-flag-thrown`: the Amulet thrown away on level 1, then `<` on
  the stairs: classic wins, fixed "Your way is magically blocked".

## N3. Merging pickup leaves pursuers with a dangling target
- **Player saw:** a monster heading for an item the hero picked up (when the item merged
  into a pack stack) walked to the empty square and stopped there.
- **Cause:** `pack.c:83-87` discards the floor object and goes on with the pack stack;
  the redirect loop (`pack.c:143-145`) then tests the stack's `o_pos`.
- **Port / C:** `add_pack()` at `dump_it`: monsters whose `t_dest` is the floor object's
  `o_pos` are sent after the hero before it is discarded.
- **Script:** `N3-merge-pickup-pursuer`: a nymph goes for a food ration; the hero takes
  it back (it merges); classic nymph stops by the door, fixed nymph comes for the hero.

## N4. Nymph theft from a stack
- **Player saw:** "She stole 2 potions" when one of three was taken (C: the stack was
  then freed while still in the pack).
- **Cause:** `fight.c:310-312`: `leave_pack(steal, FALSE, FALSE)` decrements the stack
  and returns it; it is named and `discard()`ed.
- **Port / C:** `steal = leave_pack(steal, TRUE, FALSE)`: one item, as its own object,
  named and discarded.
- **Script:** `N4-nymph-steals-from-stack`.

## N5. A monster killed during `runners()`
- **Player saw:** rarely, a monster killed by a dragon's flame moved or attacked once
  more and was left on the map as a killable ghost; monsters after it lost their turn.
- **Cause:** `chase.c:33-51`: the loop saves `next` before moving a monster; a flame
  (`chase.c:177`, `sticks.c:373`) can kill that `next` monster, whose links are then
  cleared; the dead monster is moved (and put back on the map by `relocate()`).
- **Port:** `Chase.runners()`: if `next` is no longer on `mlist`, go on with
  `tp.l_next` (the monster now after `tp`), which skips exactly the monsters removed
  during the pass and keeps the order. `relocate()`, `find_dest()` and the loop stay
  non-blocking.
- **C:** `chase.c` `runners()`: the same check (`on_mlist()`).
- **Script:** `N5-dragon-kills-next`: wizard, level 5, in a corridor (only two squares
  touch the hero): a bat is created first, then a monster on the other side, which a
  wand of polymorph turns into a dragon (polymorph re-attaches it at the head of
  `mlist`, so the bat follows it); aggravate monsters, wait: the flame passes the hero
  and kills the bat; then the classic monsters lose their turn (the emu stays on the
  door), the fixed ones move. (Random play never reached this: 40,000 random scripts and
  1,300 explorer-bot deep wizard games.)

## N8. Treasure room object on an occupied square
- **Player saw:** two objects on one square of a treasure room; the one underneath
  could not be picked up normally.
- **Cause:** `new_level.c:202-206`: the result of `find_floor()` is ignored; when 20
  tries find no free floor, the object goes on the last square tried.
- **Port / C:** the object is skipped when `find_floor()` fails (`new_thing()` is not
  called, so the RNG stream changes from there on, identically in both).
- **Script:** `N8-treasure-room-full`: a 3x3 treasure room; the wizard map shows a
  scroll hiding the room's gold in classic.

## N10. Stairs left scrambled after hallucination
- **Player saw:** after a hallucination ended, the stairs could still show as an object.
- **Cause:** `visuals()` (`daemons.c:259-260`) shows the stairs as a random object while
  they have not been seen (`seenstairs`); `come_down()` (`daemons.c:194-235`) restores
  objects and monsters but not the stairs. Confirmed (script below).
- **Port / C:** `come_down()` redraws `STAIRS` under the same condition as `visuals()`
  (`!seenstairs && cansee(stairs)`), unless the hero stands there.
- **Script:** `N10-stairs-after-trip`: classic still shows `!` on the stairs after
  "Everything looks SO boring now."; fixed shows `%`.

## N11. Scroll titles with a trailing or doubled space
- **Player saw:** rarely, a scroll titled 'zantargdalf tursstaprok nelgkliswhon ' (5 seeds
  in the first 50 million).
- **Cause:** `init.c:279-286`: a word the 40-character limit leaves empty still gets its
  space.
- **Port / C:** after the loops (whose RNG calls are unchanged), doubled and trailing
  spaces are removed from the name in `prbuf`.
- **Script:** `N11-scroll-title-space` (seed 17690789, scroll kind 0).

## N12. Wizard map mostly in standout
- **Player saw (wizard):** `^F` showed most of the map inverse after the first hidden
  square.
- **Cause:** `wizard.c:275-280`: standout is turned on for each hidden square but off
  only for a square whose flags are all 0.
- **Port / C:** `if (!(real & F_REAL)) wstandend(hw)`.
- **Script:** `N12-show-map-standout` (text is the same; the oracle diff checks the
  attributes) and `godot/tests/fixes_test.gd` (with the fixes exactly the hidden
  squares stand out, without them hundreds more).

## N13. Wizard `^I` with a full pack
- **Player saw (wizard):** with a full pack, `^I` made the hero wield the two-handed
  sword and wear the plate mail although neither fit in the pack.
- **Cause:** `command.c:400-417`: `add_pack()`'s failure is not checked.
- **Port / C:** the weapon and armor are taken only if they are in the pack after
  `add_pack()`.
- **Script:** `N13-wizard-power-full-pack`.

## N14. Wizard: `wake_monster()` with no monster
- **Player saw (wizard):** leaving a lit room with an object of a monster-letter type in
  it: "Can't find monster in wake_monster", then a crash.
- **Cause:** `monsters.c:157-165`: the MASTER branch prints the message and goes on with
  the NULL monster (`door_open()` wakes every monster letter it sees).
- **Port:** with the fixes `wake_monster()` returns null after the message. Classic: the
  port now exits 139 there like the C (before, a GDScript error; see docs/FIDELITY.md).
- **C:** `monsters.c`: `return NULL;` after the message.
- **Script:** `N14-wake-nothing`.

## Typos in messages
| C | Classic | Fixed | Script |
|---|---|---|---|
| `move.c:299` | you pack turns red! | your pack turns red! | `typos-pack-turns` |
| `daemons.c:168` | ...motor capabilites | ...motor capabilities | `typos-capabilities` |
| `potions.c:28` | what a tripy feeling! | what a trippy feeling! | `typos-messages` |
| `potions.c:204` | It make you feel warm all over | It makes you feel ... | `typos-messages` |
| `scrolls.c:285` | the Universal Onenes | the Universal Oneness | `typos-messages` |
| `sticks.c:189,191` | missle vanishes | missile vanishes | `typos-messages` |
| `init.c:173` | cinnibar (a staff) | cinnabar | `typos-messages` |

In the port the corrected strings are chosen at the use site (`p_actions` is a
constant table: `Potions._pa_str()`; the wood name in `Init.init_materials()`); the
message lengths change, so `--More--` can fall differently, identically in both
programs.

## Kept as is
These are not fixed (with or without the switch):

| Id | What | Why |
|---|---|---|
| 6 | maze rooms are never dark (`r_flags = ISMAZE`) | they already behave as dark corridors |
| 19 | `do_move()` takes `proom` from the old square | a naive fix breaks `leave_room()` |
| 15 | `drain()`'s 40-entry `drainee` array | the port has no limit; unreachable in practice |
| 16 | `pack_used[]` indexed out of range | unreachable once 5 is fixed |
| 17 | `inv_name()` and a stale `prbuf` | harmless |
| 18 | merge order of groups in the pack | harmless |
| 20, 21 | `parse_opts()` edge cases | pinned in docs/FIDELITY.md; only reachable through odd ROGUEOPTS |
| 23 | wizard `create_obj()` with a bad kind | already guarded (docs/FIDELITY.md) |
| 24 | `-d`: `dnum` wraps | harmless (the port restores the seed directly) |
| 25 | the save bugs | already fixed in both programs (docs/FIDELITY.md) |
| N15 | arrow and dart traps hit against the base armor class | probably intended; the same in 3.6 |
| N16 | `f`/`F` toward a blocked diagonal | harmless |
