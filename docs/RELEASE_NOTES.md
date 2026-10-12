Meta-Rogue is **Rogue 5.4.4**, the 1980 dungeon crawler that named the roguelike genre, ported screen for screen to the Godot engine, with a meta-progression layer on top.

### New in 1.1.0
- **Skills.** The Guild has a ninth section, Skills, bought for one hero like everything else:
  - Frost Resistance and Frost Immunity;
  - Sure Sight and High Intellect;
  - Low-Light Vision;
  - Throw Anything: thrown potions, scrolls, rings and wands work on the monster they hit;
  - Coin Scrounger: the gold you find x2, x3, ...;
  - Safe Pockets, the Serpentine Cult and Advanced Recovery.

  The line under the list says what each one does.
- **Cheaper wands and rings.** Wands cost about a third of what they did: teleport away is 300, and a second wand of a kind costs twice as much, not four times. Rings cost about 10% less. If you never edited `guild_prices.txt`, the game replaces it with the new list. An edited one is kept, and the skills' prices come from the game.

### What's in it
- **The original game, 1:1.** It has the same dungeons, monsters and rules, checked keystroke by keystroke against the C program. `--classic` plays it untouched.
- **The Fighters' Guild.** Before each new game, the gold of your Hall of Fame (20 heroes) buys training, arms, armour, rings, wands, potions, scrolls, supplies and skills. Every price and formula is in `guild_prices.txt`, a text file you can edit.
- **The known bugs of 5.4.4, fixed.**
- **Item menus as in PC Rogue.** Read, quaff, wield and the rest list the items that fit, at once.
- **The next level on the status line:** `Exp: 2/15/20` means level 2, 15 points, level 3 at 20.
- **Any screen:** fullscreen at your resolution. F10 opens the video settings and Alt+Enter toggles fullscreen.

### Download (under *Assets*, below)
| Your computer | File |
|---|---|
| Windows 10 or 11, 64-bit | `Meta-Rogue-@VERSION@-windows.zip` |
| macOS 11+ on Intel, macOS 13+ on Apple Silicon | `Meta-Rogue-@VERSION@-macos.zip` |
| Linux, 64-bit (glibc 2.28+: Ubuntu 20.04, Debian 10, Fedora 29 or newer) | `Meta-Rogue-@VERSION@-linux.zip` |

### Install
- **Windows:** extract the zip and run `Meta-Rogue.exe` in the `Meta-Rogue` folder. The program isn't signed, so SmartScreen may warn you: click *More info*, then *Run anyway*.
- **macOS:** unzip it and drag `Meta-Rogue.app` to Applications. The app isn't notarized, so the first time it is blocked: go to *System Settings → Privacy & Security* and click *Open Anyway*.
- **Linux:** unzip it and run `Meta-Rogue/Meta-Rogue.x86_64`.

Your saves, Hall of Fame and settings are kept in `%APPDATA%\Meta-Rogue`, `~/Library/Application Support/Meta-Rogue` or `~/.local/share/Meta-Rogue`.

The full instructions are in `README.txt` in each zip, and in [INSTALL.md](https://github.com/mw32445/meta-rogue/blob/v@VERSION@/INSTALL.md).
