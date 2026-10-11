# The Fighters' Guild

A meta-progression for the playable game: before every new game the Guild outfits the
hero with gold from its coffers, which hold the loot of the heroes in the Hall of Fame.

> "The local guildmasters have sent you into the Dungeons of Doom ... you are allowed to
> keep all the loot you bring back." (the original manual)

Everything here sits behind the switch `RogueBase.guild`:
- the playable game (`godot/ui/main.gd`) turns it on, unless started with `--classic`;
- `godot/tests/replay.gd` keeps it off unless a run asks for it (`--guild`,
  `--loadout FILE.json`).

With the switch off the game is the classic one, byte for byte. `harness/run_all.sh`
keeps checking that against the C.

## 1. How it plays
Before every new game (the first one too) the Guild Quartermaster's stores open. They
do not open for a restored game, for `-s` or `-d`, or with `--no-guild`.

The stores:
- **Gold.** The coffers (section 2) are the student's to spend. The screen shows what
  is spent and what is left. Unspent gold is not kept: the next student gets the coffers
  afresh.
- **No backing out.** There is no Escape and no cancel; the only way out is down (`>`
  or Enter, then `y`).
- **Returns.** Until the descent, anything bought can be returned for its full price,
  except an identification.
- **Identifications.** Identifying a potion or a scroll names one random unknown kind
  for this run. Common kinds come up more often (weighted by dungeon frequency). No item
  comes with it, and it is final. The named kind is then for sale.
- **Stable draws.** The draws are fixed by the Hall of Fame. Closing the window, or
  quitting at once and starting again, names the same kinds in the same order. They
  change only when the Hall of Fame does.

| Key | Action |
|---|---|
| `j` `k`, up/down | choose a line (PgUp/PgDn, Home/End, space pages down) |
| `+` or `l` | buy one |
| `-` or `h` | return one |
| `1`-`8`, left/right, Tab | section |
| `?` | the rules, with the coffers formula and its numbers |
| `>` or Enter | descend (asks `[y/n]`) |

The bottom line is the Quartermaster's. It greets each section and says why a purchase
is refused (coffers, pack, a limit, an issued item, a final identification).

When a game ends, the end screen shows the 20-entry list and then one line:
`The Guild's coffers now hold N gold. [Enter: the Guild, Esc: quit]`.

## 2. The coffers
```
coffers = best / 2 + sum * (10 + n) / 400          (integer arithmetic)
```
- `n` is the number of Hall-of-Fame entries with a score above 0, and `sum` their total.
  Every death, quit and win counts.
- This is the formula `best/2 + (sum/20) * lerp(0.5, 1.5, n/20)`, since
  `lerp(0.5, 1.5, n/20) = (10 + n)/20`.

Worked example: 17 heroes, best 2400, total 9400. Then 2400/2 + 9400 * 27 / 400 =
1200 + 634 = **1834** gold. A first game, with no Hall of Fame, has 0 gold: only the free
swaps (a lighter weapon or armour) are possible.

## 3. The Hall of Fame: 20 entries
In guild mode:
- `Main.main()` sets `numscores = 20` ("Top Twenty Scores") before `open_score()`.
- `Save.rd_score` reads only the entries the file holds (file length / 1124). Without
  this, an older 10-entry file would yield copies of entry 10 in places 11-20: `encread`
  reads nothing past the end, and the static scoreline keeps the last line read. The
  missing places keep `score()`'s zero scores, and the file is written back with 20
  entries.
- The Guild reads the file with its own reader, `HallOfFame`. It uses only the pure
  helpers `Save.encread` and `Save._scan_scoreline`, touches no game state, and reads
  at most 20 entries.
- The end screen's list is about 27 lines. `TerminalView` shows the stdout console in a
  smaller font, up to 32 rows, instead of losing its top.

## 4. The price list
All prices are whole gold pieces. `k` is how many of that line were already bought:
the first costs the base price. Copies of a ring or wand cost `base * 4^k`. Potions and
scrolls cost `base * 2^k` once their kind is known.

| Section | What | Price |
|---|---|---|
| Training | +1 strength (16 to at most 31) | 100 * 2^k |
| | +2 max hit points (12 to start) | 60 * 2^k |
| Arms | your weapon, +1,+1: dagger, spear (free), mace (issued), long sword, two-handed sword | 0 / 0 / - / 190 / 540 (its price over the mace) |
| | spare weapon, +0,+0, known: spear, mace, long sword, two-handed sword | 40 / 60 / 250 / 600 |
| | smithing: +1 to the lower of hit and damage (damage first), per weapon, the bow too | 75 * 2^k |
| Armour | your armour, +1: leather, studded (free), ring mail (issued), scale, chain, splint, banded, plate | 0 / 0 / - / 140 / 340 / 640 / 640 / 1040 |
| | spare armour, +0, known | leather 20, ring mail 60, studded 60, scale 200, chain 400, splint 700, banded 700, plate 1100 |
| | the armourer: -1 armour class, per suit | 100 * 2^k |
| Rings | known; protection, add strength, dexterity, increase damage come +1; teleportation and aggravate monster are cursed (as in the dungeon) | regeneration 900, slow digestion 700, stealth 600, increase damage 550, protection 500, add strength 500, dexterity 450, sustain strength 400, maintain armor 400, see invisible 300, searching 250, teleportation 200, aggravate monster 10, adornment free; copies * 4^k |
| | the enchanter: +1 to a bonus ring | 150 * 2^k |
| | polishing a ring of adornment: a total winner sells it for 10 * 2^k (10, 20, ... 1280; at most 7) | 5 * 2^k (half what it adds) |
| Wands | wands and staves, known, 5 charges (light 15) | teleport away 900, slow monster 650, lightning/fire/cold 600, cancellation 500, drain life 400, polymorph 300, magic missile 250, teleport to 150, light 120, haste monster 5, invisibility 5, nothing 5; copies * 4^k |
| | recharging: +2 charges, per wand | 80 * 2^k |
| Potions | identify one (random, weighted, final, no item) | 40 |
| | a known kind | raise level 250, extra healing 200, gain strength 180, healing 120, haste self 100, restore strength 60, magic detection 50, see invisible 40, monster detection 30, levitation 20, confusion/hallucination/poison/blindness 5; * 2^k |
| Scrolls | identify one (random, weighted, final, no item) | 40 |
| | a known kind | enchant weapon 200, enchant armor 200, teleportation 160, scare monster 160, protect armor 120, magic mapping 100, hold monster 70, remove curse 50, identify ring/wand/staff 40, identify armor 30, identify potion 30, identify scroll 25, identify weapon 25, food detection 20, monster confusion 20, create monster 10, aggravate monsters 5, sleep 5; * 2^k |
| Stores | a food ration | 30 * 1.3^k (30, 39, 50, 65, 85, 111, ...) |
| | 10 arrows / 10 darts / 5 shuriken / 2 daggers | 10 / 8 / 25 / 30, flat |
| | a bigger pack: +1 slot, 23 up to 52 | 50 * 1.5^k (50, 75, 112, 168, 253, ...) |

Notes:
- **Your weapon and armour.** They are the issued ones, changed in place. Switching
  pays (or refunds) the difference. Their enhancements stay with them.
- **Food.** 13 rations cost 2,922 gold, less than the two rings of slow digestion they
  stand in for (700 + 2,800 = 3,500). The test asserts this.
- **Missiles.** Extra arrows go onto the issued stack and need no slot. Darts, shuriken
  and daggers make one stack per kind, which takes one slot.
- **Pack slots.** The pack is counted the way `Pack.pack_room()` counts:
  - one slot per potion, scroll and ration (stacks too);
  - one per other item;
  - one per missile stack.

  The issued kit takes 5. A slot can be returned only while the purchases still fit.

## 5. In the game
`Loadout.apply()` (`godot/guild/loadout.gd`) puts the purchases into the starting pack.
`Main.main()` awaits it right after `Init.init_materials()`, once (it then clears
`RogueBase.loadout`):
- **Strength and hit points.** `Misc.chg_str` raises strength and `max_stats`. Hit
  points raise `s_hpt` and `s_maxhp`.
- **The issued items, changed in place.** The weapon is re-made by
  `Weapons.init_weapon`, then +1,+1 plus its enhancements; a dagger in hand is one
  dagger. The armour gets its `o_which` and `o_arm = a_class - 1 - enhancements`.
  Arrows join the stack, and the bow gets its enhancements.
- **New objects** start as `Things.new_thing()` starts them. Then the game's helpers
  make them: `init_weapon`, `fix_stick` (charges then set to 5, light 15, +2 per
  recharge), and `Pack.add_pack(obj, true)`. Potions, scrolls and food go in one at a
  time and merge.
- **Knowledge.** Every weapon, armour, ring and stick is known (`ISKNOW`). Every kind
  bought or identified is known for the run (`oi_know`).
- **The pack's size.** `RogueBase.maxpack` (reset to `MAXPACK`, 23) replaces `MAXPACK`
  in `pack_room()` in guild mode.
  - Past `z` the pack letters go on with `A`-`Z`; `pack_used` has 52 entries in guild
    mode, and `Pack._pack_index` / `_pack_letter` map between letters and slots.
  - In classic mode C's arithmetic is unchanged, out-of-range writes included.
  - `apply()` never lets `add_pack()` refuse, since that would stop for a message.
- **Saves.** `maxpack` is saved at the end of the port's save state; restoring a save
  without it gives 23. All 52 `pack_used` entries are restored.
- **A polished ring of adornment.** It keeps its polishes in its otherwise unused
  `o_arm` (11, `new_thing()`'s default, plus the polishes). Its name shows
  `[worth N]`, and `total_winner()` sells it for `10 * 2^polishes`, with the usual
  halving when unknown. An unpolished one sells as before, for 10 plus its stone's
  value.
- **Long inventories.** Past 23 lines Rogue pages them, but it touches `stdscr` after
  every page, so the `getch()` that waits on the next page repaints the map over it. This
  is a bug of the original; classic lists rarely get that long. In guild mode
  `add_line()` touches `stdscr` after the last page only, so every page is seen.

A dagger, a wand or a staff draws on the RNG, so a loadout changes the dungeon of a
seed. This is fine in guild mode.

## 6. The loadout
`GuildShop.loadout()` makes it; `replay.gd --loadout FILE.json` reads one (JSON numbers
may be floats). Every key is optional:

```
"maxpack": 23..52            pack slots
"str": n                     strength points to add
"hp": n                      max hit points to add
"weapon": {"which", "enh"}   the student's weapon (o_which), +1,+1 plus enh
"bow": {"enh"}               enhancements of the issued +1,+0 bow
"armor": {"which", "enh"}    the student's armour, +1 plus enh
"arrows": n                  arrows added to the issued stack
"weapons": [{"which", "enh"}]    spare weapons, +0,+0 plus enh
"armors": [{"which", "enh"}]     spare armour, +0 plus enh
"missiles": [{"which", "count"}] a stack each of darts, shuriken or daggers
"rings": [{"which", "enh"}]      bonus rings +1+enh; adornment polished enh times
"sticks": [{"which", "enh"}]     5 charges (light 15) + 2*enh
"potions", "scrolls": [{"which", "count"}]
"food": n                    rations added
"know_potions", "know_scrolls": [which, ...]   identified for the run
```
`which` is the game's `o_which`, the order of the tables in `rogue_base.gd` and
`catalog.gd`. Example: `{"maxpack": 30, "weapon": {"which": 1, "enh": 1}, "rings":
[{"which": 5, "enh": 3}]}` gives 30 slots, a +1,+2 long sword and a ring of adornment
worth 80 to a winner.

## 7. Tuning
- **Prices.** Every price, kind and limit is in `godot/guild/catalog.gd` (the screen
  sorts the lists by price), together with the game's names and dungeon frequencies,
  which the test checks against the game's tables.
- **Growth.** `GuildCatalog.grow(base, num, den, k)` is `floor(base * (num/den)^k)`,
  in exact integers.
- **Text.** The Quartermaster's lines are in `guild_screen.gd`; the section texts are in
  `GuildShop.offers()`.

After a change, run `tools/check.sh` and `godot/tests/guild_test.gd`. The food-versus-
rings invariant and the price schedules are asserted there.

## 8. Files
| File | What |
|---|---|
| `godot/guild/catalog.gd` | `GuildCatalog`: the price list (data, growth rules). |
| `godot/guild/hall_of_fame.gd` | `HallOfFame`: reads the score file; the coffers; the hash that seeds the draws. |
| `godot/guild/shop.gd` | `GuildShop`: the rules (no UI): buy/refund, limits, identifications, the offers of each section, the loadout. |
| `godot/guild/guild_screen.gd` | `GuildScreen`: the 80x24 screen on its own `Curses`; keys come from `ui/main.gd`. |
| `godot/guild/loadout.gd` | `Loadout.apply()`: the purchases into a new game; the schema. |
| `godot/rogue/` | Guild-mode branches: `main.gd` (20 entries, 52 letters, apply), `pack.gd` (maxpack, letters), `save.gd` (rd_score, maxpack), `rip.gd` and `things.gd` (adornment worth; inventory pages), `rogue_base.gd` (`maxpack`). |
| `godot/ui/main.gd` | Runs the Guild before new games; `--classic`, `--no-guild`; the end prompt; `skip_guild` for UI tests. |
| `godot/ui/terminal_view.gd` | A new `cs` resets the caches; long consoles in a smaller font. |
| `godot/tests/guild_test.gd` | Unit and whole-game tests (below). |

## 9. Testing
- **Classic stays 1:1.** `harness/run_all.sh` (or `difftest.py corpus`, `seeds`, `fuzz`,
  `fuzz --wizard`, `saves`, and the same with `--fixes`) runs with the switch off. The
  oracle cannot judge the Guild.
- **`godot --headless --path godot --script res://tests/guild_test.gd`** (PASS/FAIL per
  check, exit status 1 on a failure) covers:
  - the coffers on sample Halls of Fame, against the float formula;
  - the price schedules, and the coffers and pack limits;
  - final identifications versus full refunds, and stable, weighted draws;
  - 10-to-20 score-file migration without phantom entries;
  - the catalog against the game's tables;
  - loadouts applied to new games, and the shop's pack count equal to the game's;
  - letters past `z`;
  - a won game selling a polished ring for 80;
  - a 30-slot wizard game: both inventory pages, drop and pick up, save and restore.
- **A loadout by hand.**
  `godot --headless --path godot --script res://tests/replay.gd -- --guild --loadout F.json --keys K --dump D --full 1`
  writes every screen to the dump.
- **Screenshots.**
  `xvfb-run -s "-screen 0 1280x800x24" godot --path godot --script res://tests/ui_screenshot.gd -- --out=/tmp/g --guild --sample-hof=17 --keys="..."`.
  `--sample-hof=N` replaces the score file in the user data folder.
