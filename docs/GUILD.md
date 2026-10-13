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
- **No backing out.** There is no Escape and no cancel; the only way out is down (`e`,
  then `y`).
- **Returns.** Until the descent, anything bought can be returned for its full price,
  except an identification.
- **Identifications.** Identifying a potion or a scroll names one random unknown kind
  for this run. Common kinds come up more often (weighted by dungeon frequency). No item
  comes with it, and it is final. The named kind is then for sale.
- **Stable draws.** The draws are fixed by the Hall of Fame. Closing the window, or
  quitting at once and starting again, names the same kinds in the same order. They
  change only when the Hall of Fame does.
- **Skills.** The ninth section sells skills: rules of the game changed for the run
  (section 6).
- **Prices.** Every price, the coffers formula and the amounts (hit points, charges,
  missiles per purchase, ...) are in a text file anyone can edit, `guild_prices.txt`
  (section 8). The Guild reads it each time it opens.

| Key | Action |
|---|---|
| `j` `k`, up/down | choose a line (PgUp/PgDn, Home/End, space pages down) |
| Enter (or `+`, `l`) | buy one more |
| Backspace (or `-`, `h`) | return one |
| `1`-`9`, left/right, Tab | section |
| `?` | the coffers formula with its numbers, the keys, the price file's path and the lines of it that can't be used |
| `e` | enter the dungeon (asks `[y/n]`) |

The screen has no explanatory text and no flavor lines: only the lists, their short
headings and prices. The bottom line stays empty unless a key was refused; it then
says why, in Rogue's message style ("you can't afford that", "there's no room in your
pack", "an identification can't be returned", ...). It also shows the first line of
the price file that can't be used, until a key is pressed (section 8). In the Skills
section, the full description of the skill under the cursor is under the list.

When a game ends, the end screen shows the 20-entry list and then one line:
`The Guild's coffers now hold N gold. [Enter: the Guild, Esc: quit]` (by the price
file's coffers formula).

## 2. The coffers
```
coffers = best / 2 + (sum / 20) * lerp(0.5, 1.5, n / 20)
```
- This is the `[coffers]` line of the price file (section 8), which can change it.
- `n` is the number of Hall-of-Fame entries with a score above 0, `sum` their total and
  `best` the best of them. Every death, quit and win counts.
- `lerp(0.5, 1.5, n / 20)` is `0.5 + n / 20`: it grows from 0.5 (no heroes) to 1.5
  (twenty).
- It is computed in floating point and rounded down once. Until the price file it was
  `best / 2 + sum * (10 + n) / 400` in integers, the same formula on paper (`lerp(0.5,
  1.5, n/20) = (10 + n)/20`) but rounding each term down: now the coffers can hold 1
  gold more than then, never less. For example best 2401, total 9401, 17 heroes: 1835,
  was 1834.

Worked example: 17 heroes, best 2400, total 9400. Then 2400 / 2 + (9400 / 20) * 1.35 =
1200 + 634.5 = **1834** gold. A first game, with no Hall of Fame, has 0 gold: only the
free swaps (a lighter weapon or armour) are possible.

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
These are the prices of the shipped `guild_prices.txt`, and the built-in ones (section
7). All prices are whole gold pieces. `k` is how many of that line were already
bought: the first costs the base price. Copies of a ring cost `base * 4^k`, of a wand
`base * 2^k`. Potions and scrolls cost `base * 2^k` once their kind is known.

| Section | What | Price |
|---|---|---|
| Training | +1 strength (16 to at most 31) | 100 * 2^k |
| | +2 max hit points (12 to start) | 60 * 2^k |
| Arms | your weapon, +1,+1: dagger, spear (free), mace (issued), long sword, two-handed sword | 0 / 0 / - / 190 / 540 (its price over the mace) |
| | spare weapon, +0,+0, known: spear, mace, long sword, two-handed sword | 40 / 60 / 250 / 600 |
| | enhance: +1 to the lower of hit and damage (damage first), per weapon, the bow too | 75 * 2^k |
| Armour | your armour, +1: leather, studded (free), ring mail (issued), scale, chain, splint, banded, plate | 0 / 0 / - / 140 / 340 / 640 / 640 / 1040 |
| | spare armour, +0, known | leather 20, ring mail 60, studded 60, scale 200, chain 400, splint 700, banded 700, plate 1100 |
| | enhance: -1 armour class, per suit | 100 * 2^k |
| Rings | known; protection, add strength, dexterity, increase damage come +1; teleportation and aggravate monster are cursed (as in the dungeon) | regeneration 800, slow digestion 625, stealth 550, increase damage 500, protection 450, add strength 450, dexterity 400, sustain strength 350, maintain armor 350, see invisible 275, searching 225, teleportation 175, aggravate monster 10, adornment free; copies * 4^k |
| | enhance: +1 to a bonus ring | 150 * 2^k |
| | polishing a ring of adornment: a total winner sells it for its worth (10 plus its stone's, learned in the dungeon) times 2^k (at most 7) | 5 * 2^k (half what it adds to a plain 10-gold ring) |
| Wands | wands and staves, known, 5 charges (light 15) | teleport away 300, slow monster 250, lightning/fire/cold 250, cancellation 200, drain life 150, polymorph 120, magic missile 80, teleport to 60, light 50, haste monster 5, invisibility 5, nothing 5; copies * 2^k |
| | recharging: +2 charges, per wand | 40 * 2^k |
| Potions | identify one (random, weighted, final, no item) | 40 |
| | a known kind | raise level 250, extra healing 200, gain strength 180, healing 120, haste self 100, restore strength 60, magic detection 50, see invisible 40, monster detection 30, levitation 20, confusion/hallucination/poison/blindness 5; * 2^k |
| Scrolls | identify one (random, weighted, final, no item) | 40 |
| | a known kind | enchant weapon 200, enchant armor 200, teleportation 160, scare monster 160, protect armor 120, magic mapping 100, hold monster 70, remove curse 50, identify ring/wand/staff 40, identify armor 30, identify potion 30, identify scroll 25, identify weapon 25, food detection 20, monster confusion 20, create monster 10, aggravate monsters 5, sleep 5; * 2^k |
| Stores | a food ration | 30 * 1.3^k (30, 39, 50, 65, 85, 111, ...) |
| | 10 arrows / 10 darts / 5 shuriken / 2 daggers | 10 / 8 / 25 / 30, flat |
| | a bigger pack: +1 slot, 23 up to 52 | 50 * 1.5^k (50, 75, 112, 168, 253, ...) |
| Skills | each bought once (section 6) | frost resistance 200, frost immunity 300 (after frost resistance), sure sight 100, high intellect 500, low-light vision 700, throw anything 200, safe pockets 300, serpentine cult free, advanced recovery 800 |
| | coin scrounger, by level: gold x2, x3, x4, ... | 1000 * (k + 1): 1000, 2000, 3000, ... (x4 costs 6000 in all) |

Notes:
- **Your weapon and armour.** They are the issued ones, changed in place. Switching
  pays (or refunds) the difference. Their enhancements stay with them. A price file
  that makes the issued one dearer than another makes that other a trade-in: choosing
  it gives the difference back, and going back to the issued one pays it again.
- **Food.** 13 rations cost 2,922 gold, less than the two rings of slow digestion they
  stand in for (625 + 2,500 = 3,125). The test asserts this.
- **Wands** cost more in 1.0.0 (teleport away 900, copies * 4^k, recharging 80 * 2^k).
  A student with about 2,000 gold could rarely afford one, and their charges run out. A
  bolt and teleport away now cost 550 together. Rings are about 10% cheaper than in 1.0.0.
- **Coin Scrounger's price.** Each level adds the same +1x of the gold found and costs
  1,000 more than the last, so the total for xm is 500 * m * (m - 1): x2 1,000, x3
  3,000, x4 6,000, x5 10,000.
  - A run finds about 100 + 19 * depth gold a level (about 2,000 by depth 10).
  - With a full Hall of Fame, the coffers hold about twice a typical score.

  So the next level pays back when a run finds about as much gold as it costs. A
  middling player settles around x3 or x4 while still buying gear; a deep player goes
  higher.
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
  make them: `init_weapon`, `fix_stick` (charges then set to the loadout's: as
  shipped, 5, light 15, +2 per recharge), and `Pack.add_pack(obj, true)`. Potions,
  scrolls and food go in one at a time and merge.
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
  `[worth N]`, and `total_winner()` sells it for its worth (10 plus its stone's value,
  `ring_info[R_NOP].oi_worth`) times `2^polishes`, with the usual halving when
  unknown. An unpolished one sells as before. The stone is random per game, so the
  shop prices a polish as if the ring were plain (10 gold): part of the gamble.
- **Long inventories.** Past 23 lines Rogue pages them, but it touches `stdscr` after
  every page, so the `getch()` that waits on the next page repaints the map over it. This
  is a bug of the original; classic lists rarely get that long. In guild mode
  `add_line()` touches `stdscr` after the last page only, so every page is seen (the
  same change is bug fix 31 of the switch `fixes`, docs/FIXES.md).

A dagger, a wand or a staff draws on the RNG, so a loadout changes the dungeon of a
seed. This is fine in guild mode.

## 6. Skills
The ninth section sells skills: rules of the game changed for the run.
- **Buying.** Each skill is bought once, except Coin Scrounger, whose levels are bought
  one at a time. A skill is returned for its full price, like everything else.
- **Frost Immunity** needs Frost Resistance, and Frost Resistance can't be returned
  while Frost Immunity is held.
- **On the screen**, each line shows the skill's short effect (Coin Scrounger: `gold x1
  -> x3`, `next x4`). The skill under the cursor has its full description under the list.

| Skill | Price | In the game |
|---|---|---|
| Frost Resistance | 200 | The ice monster's touch never kills by hypothermia. Its freezes still add up, so the hero can stay frozen while it, or anything else, keeps hitting; another monster or hunger ends it. |
| Frost Immunity | 300, needs Frost Resistance | The ice monster freezes nothing ("you feel a brief chill"). |
| Sure Sight | 100 | The potion of blindness, the game's only blindness, doesn't blind; it is identified. |
| High Intellect | 500 | No confusion from the potion of confusion (identified) or from the medusa's gaze ("the medusa's gaze has no effect on you"). |
| Low-Light Vision | 700 | In a dark room (not a corridor or a maze), the hero sees the room's squares 2 away like the adjacent ones: floor, walls, doors, objects, monsters. Only the adjacent squares wake monsters or stop a run, as before. |
| Throw Anything | 200 | Thrown items have effects (below). |
| Coin Scrounger | 1000 * (k + 1) | Gold picked up is multiplied by the level + 1 (x2, x3, x4, ...); the message shows what was gained. |
| Safe Pockets | 300 | Leprechauns and nymphs don't steal (or vanish): they fight on and hit for 1x8, the zombie's damage. |
| Serpentine Cult | free | Below. |
| Advanced Recovery | 800 | The hero regenerates as at one level higher. |

**Throw Anything.**
- **The command.** It lists every item and throws any, except the amulet: "Not even
  this can be thrown." (no time passes). As in 5.4.4, worn armour is taken off first (it
  takes a turn) and a ring comes off its finger.
- **A hit** uses the item up, whatever it is, as 5.4.4 does with a weapon. A miss lands
  as before. A monster that the hit kills gets no effect.
- **Armour** hits for 1x4, plus the hero's strength bonus.
- **A potion** works on the monster as if it drank it. It is identified when the effect
  is seen:

  | Potion | The monster |
  |---|---|
  | confusion, blindness | confused: it moves at random until it shakes it off |
  | healing, extra healing | heals as the hero would (its level in d4 or d8; past its maximum, the maximum grows) |
  | raise level | +1 level, +1d8 hit points |
  | haste self | hasted; one already hasted faints from exhaustion (falls asleep) |
  | poison | -1 to -3 strength (none if it wears sustain strength) |
  | gain strength, restore strength | +1 strength; back to its kind's |
  | the detections, see invisible, levitation, hallucination | nothing |
- **A scroll** works as if the monster read it:

  | Scroll | The monster |
  |---|---|
  | monster confusion | confused |
  | sleep | falls asleep |
  | hold monster | it and the running monsters within 2 of it are held |
  | teleportation | teleported away |
  | create monster | a monster appears next to it |
  | aggravate monsters | the level's other monsters wake and go to it |
  | enchant armor, enchant weapon | its armour class -1; its damage +1 |
  | the others | nothing |
- **A ring** is used up, and the monster keeps its effect: the ring stays in its pack
  and goes with it when it dies (it is not dropped):

  | Ring | The monster |
  |---|---|
  | teleportation | teleported now and then (1 turn in 50, as the hero) |
  | aggravate monster | the level's other monsters wake and go to it |
  | protection, add strength, dexterity, increase damage | its armour, strength, to-hit or damage by the ring's bonus |
  | regeneration | +1 hit point a turn |
  | sustain strength | its strength can't be lowered (poison) |
  | the others | nothing |
- **A wand or staff** spends one last charge on the monster, even an empty one, then is
  gone:
  - slow and haste monster, invisibility, polymorph, cancellation, teleport away and
    teleport to act on it as when zapped;
  - lightning, fire and cold do their bolt's damage to it alone (6x6, unless it saves;
    the flame bounces off a dragon);
  - magic missile does its 1x4 + 1;
  - light and drain life act as when zapped: the hero's room is lit; drain life drains
    around the hero;
  - nothing does nothing.
- **A venus flytrap** holding the hero lets go when a thrown wand acts on it, as when
  zapped, or when a thrown scroll or ring teleports it.

**The Serpentine Cult.**
- **Sleeping snakes.** Rattlesnakes and snakes start asleep, wandering ones too, and
  the hero coming near never wakes them (5.4.4 wakes a "mean" monster next to the
  hero 2 times in 3). Being attacked, aggravation and the like still wake them.
- **Bites.** A rattlesnake's bite never weakens the hero. One bite in 4 gives +1
  strength ("the snake's bite makes you stronger"), at most once per snake.
- **Confirmation.** A hostile action against a snake is asked first. The first is
  stopped ("snakes are sacred to the cult: do it again to attack") and no time passes.
  The same or another hostile action right after it goes ahead, and that snake is
  never asked about again. Once time passes, the warning is forgotten. This covers:
  - melee: moving into it, `F`;
  - a throw whose path meets it first;
  - a zap whose first target it is (drain life: any snake it would drain).
- **Banishment.** Killing a snake, by any means, banishes the hero ("you are banished
  from the Serpentine Cult!"). The benefits end, and snakes hit 50% harder for the rest
  of the run.

**In the code.**
- `RogueBase.skills` (name -> level) is set by `Loadout.apply` from the loadout's
  `"skills"`. `RogueBase.skill(name)` reads it and is 0 out of guild mode, so the
  classic and fixed games, which the differential tests check, are untouched.
- The save keeps `skills` and `cult_banished`. A snake that made the hero stronger is
  flagged `GAVESTR` in its `t_flags`, saved with it.
- `godot/rogue/skills.gd` (`Skills`) holds the new rules. The game's functions call it
  where a rule changes:
  - `Fight`: `attack` (the ice monster, the rattlesnake, the leprechaun, the nymph),
    `roll_em` (thrown armour, a monster's rings, Safe Pockets' damage, the banished's
    50%), `fight` (the cult's question, a thrown item's effect), `killed`
    (banishment), `remove_mon` (what was used up on a monster goes with it);
  - `Potions.quaff`; `Monsters.wake_monster`, `wanderer`;
  - `Misc.look`, `erase_lamp`; `Chase.cansee`, `see_monst`, `set_oldch`;
  - `Chase.runners` (a monster's rings, each turn), `relocate`, `do_chase` (a monster
    drawn by aggravation);
  - `Weapons.missile`, `Sticks.do_zap`, `Pack.money`, `Daemons.doctor`;
  - `Command.command` (the cult's warning expires when time passes).
- **What a monster was hit with.** A ring or a scroll of enchant weapon stays in the
  monster's pack, flagged `ISMONWORN` in its `o_flags`. It works there, and is
  discarded, not dropped, when the monster dies.
- **Aggravation on a monster.** The level's other monsters wake and set their
  destination (`t_dest`) to it. When it goes, they go after the hero again. One that
  comes within 2 of the hero on its way goes after the hero instead: C's `chase()`
  would step onto the hero.

## 7. The loadout
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
"rings": [{"which", "enh"}]      bonus rings +1+enh; adornment polished enh times (20 at most)
"sticks": [{"which", "enh", "charges"}]   "charges" charges; without it 5 (light 15) + 2*enh
"potions", "scrolls": [{"which", "count"}]
"food": n                    rations added
"know_potions", "know_scrolls": [which, ...]   identified for the run
"skills": {name: level}      the skills (section 6), by their price-file names
```
`which` is the game's `o_which`, the order of the tables in `rogue_base.gd` and
`catalog.gd`. The shop's loadout carries every count the price file sets (hit points,
arrows, missiles, charges), so applying one needs no price file; a loadout without
"charges" gets the built-in counts. Example: `{"maxpack": 30, "weapon": {"which": 1,
"enh": 1}, "rings": [{"which": 5, "enh": 3}]}` gives 30 slots, a +1,+2 long sword and a
ring of adornment worth 80 to a winner.

## 8. The price file: `guild_prices.txt`
Every price, the coffers formula and the amounts are in a plain text file that anyone
can edit after downloading the game, formulas included. The Guild reads it each time
it opens (so an edit counts from the next new game), and so does the end-of-game
coffers line.

**Where.** The game reads the first of:
1. `guild_prices.txt` next to the game's executable: an exported game on Windows or
   Linux (the downloads ship it there);
2. `guild_prices.txt` in the user data folder (`user://`: `%APPDATA%\Meta-Rogue`,
   `~/Library/Application Support/Meta-Rogue`, `~/.local/share/Meta-Rogue`);
3. `godot/guild_prices.txt` in the project, next to `project.godot`: what a source
   download shows first, and what the editor reads.

An exported game that finds neither 1 nor 2 writes the default file to 1 (to 2 if the
executable's folder is not writable), for the player to edit. On macOS it skips 1 and
writes 2: next to the `.app` would litter /Applications, and an app opened from
Downloads runs from a read-only copy in a random place (App Translocation). It writes
the shipped file if the export holds it (the presets put `guild_prices.txt` in their
non-resource filter), else the built-in copy, `GuildCatalog.PRICES`, which is the same
text. The `?` page shows the
file's full path.

**Syntax.**
```
# a comment: the rest of the line is not read (also after a value)
[training]                  a heading: the section the lines below belong to
strength = 100 * 2^k        a name, "=", a number or a formula
```
- The name is everything before the first `=`: it may hold spaces and commas
  (`identify ring, wand or staff`). Names and headings may be in any case and spacing.
- A section line that the file leaves out keeps its original value; so a file may hold
  only the lines it changes.
- Numbers: `40`, `1.3`, `.5`, `1e6`.
- `+ - * /` (`/` is exact: `7 / 2` is 3.5), `( )`, and `^`, "to the power of" (`**`
  too): right to left, `2^3^2` = `2^9`, and above a sign, `-2^2` = -4; `2^-1` = 0.5.
- Functions: `floor ceil round min max pow sqrt abs clamp lerp`: `min(a, b, ...)`,
  `max(a, b, ...)`, `pow(a, b)`, `clamp(x, low, high)`, `lerp(a, b, t)` =
  `a + (b - a) * t`.
- Names, by line:

  | Line | Names |
  |---|---|
  | `coffers` | `best`, `sum`, `n` (section 2) |
  | a price | `k`: how many of that line were bought already (0 for the first; for an enhancement, of that one item; for your weapon or armour, always 0) |
  | `price` in `[rings]`, `[wands]`, `[potions]`, `[scrolls]` | `k`, and `base`: the kind's own number, from its line in the section |
  | an amount (`... per purchase`, `charges`, `light charges`, `polish max`) | none |

- Arithmetic is in floating point. A price is rounded down to whole gold pieces, from 0
  to 10^15: a formula that falls below 0 for some `k` makes that one free. A hair
  (10^-9 plus 10^-13 of the value) is added before rounding down, so that a value whole
  on paper but a hair below it in floating point (`0.29 * 100` is 28.999999999999996)
  is not one short. Amounts are whole numbers too: 1 to 1000; `polish max` 0 to 20
  (`GuildCatalog.POLISH_LIMIT`).
- A formula has at most 200 numbers, names, operators and brackets.

**Lines that can't be used.** A line with a syntax error, an unknown name, a name its
section does not have, an unknown section, a value out of range, a name set twice (the
second), or a formula that fails at `k = 0` (a division by zero, the square root of a
negative number, ...) is not used: its original value is. The Guild says so on its
bottom line until a key is pressed, the first one, with how many there are; the `?`
page lists them all:
```
guild_prices.txt line 12: unknown name 'kk' (using 100 * 2^k)
guild_prices.txt line 30: there is no 'strength' in [stores] (it is in [training])
guild_prices.txt line 41: polish max must be from 0 to 20 (not 25) (using 7)
```
A formula that fails only for a later `k` (or, for the coffers, for some Hall of Fame)
is reported when it first does (`division by zero when k = 3`), and the original value
is used whenever it fails.

**Examples.**
```
[coffers]
coffers = best + sum / 10           # a richer Guild

[training]
strength = 50 * 2^k                 # cheaper strength
hit points = 60 + 40 * k            # each purchase 40 dearer, not twice as dear
hit points per purchase = 3

[rings]
price = base * 2^k                  # copies of a ring twice as dear, not four times
protection = 300

[enhancing]
polish max = 12

[stores]
food = min(30 * 1.3^k, 200)         # never more than 200 a ration
darts per purchase = 20
```

**Not in the file**, being facts of the game or limits of the engine: what each kind
is, its name and its dungeon frequency, which kinds and lines are on offer and their
order, strength 31 at most, 52 pack slots at most (the pack letters), the 20 places of
the Hall of Fame, the issued kit, and what an enhancement does. They are in
`godot/guild/catalog.gd`. The section headings on the screen are in
`GuildShop.offers()`, the refusal messages in `GuildScreen._refused()`.

**For developers.** `GuildCatalog.PRICES` is the built-in copy of
`godot/guild_prices.txt`: the fallback for a line that can't be used. The two must be
the same text (copy one onto the other); `godot/tests/prices_test.gd` checks that, and
that both give, for every line and `k` = 0 to 12, exactly the prices the Guild had
before the file (exact integers, as `GuildCatalog.grow()` computed them). `GuildFormula`
(`formula.gd`) is a small parser and evaluator of its own, not Godot's `Expression`:
there `^` is exclusive or, and an `Expression` can call methods of engine objects,
which a downloaded file must not. After a change, run `tools/check.sh`,
`godot/tests/prices_test.gd` and `godot/tests/guild_test.gd`. The food-versus-rings
invariant and the price schedules are asserted there.

## 9. Files
| File | What |
|---|---|
| `godot/guild_prices.txt` | The price file, as shipped (section 8). |
| `godot/guild/catalog.gd` | `GuildCatalog`: what the Guild sells (names, frequencies, orders, limits); `PRICES`, the built-in copy of the price file. |
| `godot/guild/formula.gd` | `GuildFormula`: a formula of the price file, parsed once, computed for its names. |
| `godot/guild/prices.gd` | `GuildPrices`: reads the price file (where the game looks; the built-in values for the lines it can't use, and why); a line's price for `k`, the amounts, the coffers. |
| `godot/guild/hall_of_fame.gd` | `HallOfFame`: reads the score file; the coffers (by a price list); the hash that seeds the draws. |
| `godot/guild/shop.gd` | `GuildShop`: the rules (no UI), at a price list's prices: buy/refund, limits, identifications, the offers of each section, the loadout. |
| `godot/guild/guild_screen.gd` | `GuildScreen`: the 80x24 screen on its own `Curses`; keys come from `ui/main.gd`. It reads the price file when it opens. |
| `godot/guild/loadout.gd` | `Loadout.apply()`: the purchases into a new game; the schema. |
| `godot/rogue/` | Guild-mode branches: `main.gd` (20 entries, 52 letters, apply), `pack.gd` (maxpack, letters), `save.gd` (rd_score, maxpack, skills), `rip.gd` and `things.gd` (adornment worth; inventory pages), `rogue_base.gd` (`maxpack`, `skills`, `skill()`); the skills' hooks (section 6). |
| `godot/rogue/skills.gd` | `Skills`: the skills' rules in the game (section 6). |
| `godot/ui/main.gd` | Runs the Guild before new games; `--classic`, `--no-guild`; the end prompt (the coffers by the price file); `skip_guild` for UI tests. |
| `godot/ui/terminal_view.gd` | A new `cs` resets the caches; long consoles in a smaller font. |
| `godot/tests/guild_test.gd` | Unit and whole-game tests (below). |
| `godot/tests/prices_test.gd` | The price file's tests (below). |
| `godot/tests/skills_test.gd` | The skills in the game (below). |

## 10. Testing
- **Classic stays 1:1.** `harness/run_all.sh` (or `difftest.py corpus`, `seeds`, `fuzz`,
  `fuzz --wizard`, `saves`, and the same with `--fixes`) runs with the switch off. The
  oracle cannot judge the Guild.
- **`godot --headless --path godot --script res://tests/guild_test.gd`** (PASS/FAIL per
  check, exit status 1 on a failure) covers, with the built-in price list (never the
  player's file):
  - the coffers on sample Halls of Fame, against the float formula;
  - the price schedules, and the coffers and pack limits;
  - final identifications versus full refunds, and stable, weighted draws;
  - 10-to-20 score-file migration without phantom entries;
  - the catalog against the game's tables;
  - loadouts applied to new games, and the shop's pack count equal to the game's;
  - letters past `z`;
  - a won game selling a ring polished 3 times for 8 times its worth;
  - a 30-slot wizard game: both inventory pages, drop and pick up, save and restore;
  - a shop with an edited price list: its prices, the built-in ones elsewhere, its
    amounts in the loadout, a trade-in, polish max, every purchase returned in full;
  - the skills in the shop (prices, once each, Frost Immunity's requirement and the
    return guard, Coin Scrounger's 1000 / 2000 / 3000), in the loadout and in a game,
    and the Skills tab (nine tabs in 79 columns, the description under the list).
- **`godot --headless --path godot --script res://tests/skills_test.gd`** (FAIL lines
  and a summary, exit status 1 on a failure) plays games in guild mode with the fixes
  on, a key at a time; between keys it places a monster or an item and reads the state
  and the screen. Each skill is tried with it and without it:
  - Frost Resistance (frozen past the hypothermia limit until the hero starves) and Frost
    Immunity (never frozen);
  - Sure Sight and High Intellect (the potions; the medusa's gaze);
  - Low-Light Vision (the floor and a monster 2 away; `cansee`, `see_monst`; no waking;
    the old squares dark again after a step);
  - Throw Anything (the menu; the amulet; armour's 1x4; potions, scrolls, rings and
    wands on a monster; an empty wand; worn armour and rings; a miss lands; a ring
    goes with a dead monster);
  - Coin Scrounger (x1, x2, x4), Safe Pockets (no theft; 1x8);
  - the Serpentine Cult (sleeping snakes, bites, +1 strength once per snake, the
    confirmation for melee, `F`, throws and zaps, banishment and the 50%);
  - Advanced Recovery (heals 2 turns sooner at level 1);
  - a save and a restore keep the skills, the banishment and the snakes' flags.
- **Smoke.** `difftest.py smoke --guild` draws random loadouts with random skills (Coin
  Scrounger 0-3): no script error, no hang.
- **`godot --headless --path godot --script res://tests/prices_test.gd`** (FAIL lines
  and a summary, exit status 1 on a failure; it never reads or writes the player's
  file, except that `read()` may read it) covers:
  - formulas: precedence and associativity, the functions and their arguments, every
    error message, the length limit;
  - the file: comments, spacing, case, commas in names, every kind of line that can't
    be used (with its line number and the value used instead), later failures, the
    lists' price formulas;
  - the shipped file: the same text as `GuildCatalog.PRICES`, read without an error,
    setting every line, and both giving the old prices exactly for `k` = 0 to 12;
  - the coffers: the samples, and 3,000 random Halls of Fame against the old integer
    formula (the exact rational value rounded down; 1 more or the same);
  - files that change a price, an amount and the coffers; where the game looks and the
    file it writes; a whole shop asking for no line the list lacks;
  - the screen: the first error on the bottom line until a key, two lines for a long
    one, the `?` page (path, errors, the formula used with its numbers).
- **A loadout by hand.**
  `godot --headless --path godot --script res://tests/replay.gd -- --guild --loadout F.json --keys K --dump D --full 1`
  writes every screen to the dump.
- **Screenshots.**
  `xvfb-run -s "-screen 0 1280x800x24" godot --path godot --script res://tests/ui_screenshot.gd -- --out=/tmp/g --guild --sample-hof=17 --keys="..."`.
  `--sample-hof=N` replaces the score file in the user data folder.
