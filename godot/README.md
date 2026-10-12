# Meta-Rogue

Meta-Rogue is Rogue 5.4.4 (Michael Toy, Ken Arnold and Glenn Wichman, 1980–1999), ported
to Godot 4.7 in GDScript. The port is **1:1**: given the same seed and keystrokes, it shows exactly
the same screens and makes exactly the same random choices as the original C program.
This is verified step by step against the original (see `../docs/ARCHITECTURE.md`).

The playable game adds two things on top, each behind a switch (`../docs/CHANGES.md`):
fixes for the known bugs of 5.4.4 (`../docs/FIXES.md`), verified against a C build with
the same fixes, and the Fighters' Guild (`../docs/GUILD.md`). `--classic` plays the
untouched original.

## Playing
- **Run it:** download it for Windows, macOS or Linux from the
  [releases](https://github.com/mw32445/rogue/releases/latest)
  ([install instructions](../INSTALL.md)), or open `godot/project.godot` in Godot 4.7 or
  later and press **F5** (or *Project → Run*).
- **Keys:** the original commands, as on a terminal.
  - `h j k l y u b n` move; Shift+direction runs.
  - `?` lists all commands and `/` identifies a symbol.
  - Arrow keys, Home/End/PageUp/PageDown and the numeric keypad also move.
    Shift+arrows and Ctrl+arrows run.
  - Keypad 5 rests, like `.` (in `--classic` it acts like `u`, as 5.4.4 did on most
    terminals).
  - A command that needs an item (read, quaff, wield, wear, put on, zap, throw, eat,
    drop, ...) lists the items that fit at once, as PC Rogue does: type the item's
    letter, Escape cancels, space turns the page, `*` shows the whole pack (in
    `--classic` you press `*` for the list, as in 5.4.4).
- **Status line:** `Exp: 2/15/20` reads level 2, 15 experience, level 3 at 20 (in
  `--classic`, `Exp: 2/15` as in 5.4.4).
- **Options:** the `o` command, or the `ROGUEOPTS` environment variable, or
  `--rogueopts=...` on the command line (after `--`). For example:
  `ROGUEOPTS="terse,jump,inven=slow,fruit=kiwi"`.
- **Save:** `S` saves and exits.
  - Saved games and the score file live in the game's user data folder (its "home"):
    `%APPDATA%\Meta-Rogue` on Windows, `~/Library/Application Support/Meta-Rogue` on
    macOS, `~/.local/share/Meta-Rogue` on Linux (`application/config/use_custom_user_dir`).
    The first start copies the files of the folder the game used when it was a project
    named "Rogue" (`.../godot/app_userdata/Rogue`), and leaves that folder as it was
    (`ui/user_data.gd`).
  - The next start restores a saved game automatically and deletes the save, like
    `rogue -r`.
  - Closing the window during a game saves it, as the original does when its terminal
    hangs up.
- **Video:** the first launch detects the screen and goes borderless fullscreen at
  its own resolution (1920 x 1080 on a full HD screen).
  - **F10** opens *OPTIONS - VIDEO* over whatever is on screen (the game waits):
    display mode (windowed, fullscreen, exclusive fullscreen), window size (windowed;
    1280 x 720 to 3840 x 2160, as far as the screen holds), monitor (with several),
    and VSync. `j`/`k` or the arrows choose, `h`/`l`, the arrows or Enter change. A
    change applies at once and is saved. Esc or F10 closes it.
  - **Alt+Enter** switches between windowed and fullscreen, and is saved too.
  - The settings live in `video.cfg` in the user data folder (see *Save* above);
    delete it to detect the screen again. A new windowed size is the largest that
    fits in 90% of the screen (1600 x 900 on 1920 x 1080).
  - `--windowed` or `--fullscreen` on the command line (after `--`) choose the mode
    for one run, without saving it.
  - Run from the editor, the game is embedded in its Game view by default, and the
    editor sizes it: the settings are saved but not applied. Turn off *Embed Game on
    Next Play* in the Game view's menu to play in a window of its own.
- **The Fighters' Guild:** before every new game the Guild's Quartermaster spends the
  coffers of the Hall of Fame (now 20 entries) on your training and gear
  (`../docs/GUILD.md`).
- **The Guild's prices** (and its formulas, the coffers' too) are in
  `guild_prices.txt`, a plain text file that explains itself. Edit it with any text
  editor: the Guild reads it each time it opens, and shows any line it can't use. In a
  source download it is `godot/guild_prices.txt`, next to `project.godot`. An exported
  game on Windows or Linux reads it from next to its executable (the downloads ship it
  there) and writes it there if it is missing (in the user data folder if it can't); on
  macOS it lives in the user data folder. The export presets pack this file
  (`guild_prices.txt` in their non-resource filter) as the default; without it the game
  uses its built-in copy, the same text.
- **End of game:** when a game ends, you see the Hall of Fame and how much the Guild's
  coffers now hold. Enter opens the Guild for a new game; Esc quits.
- **Command line** (after `--`): `--rogueopts=OPTS`, `--master` (enables the wizard-mode
  code; the original's `MASTER` build), `--no-guild` (new games start without the
  Guild), `--classic` (the original 5.4.4: no Guild and no fixes, with its own save and
  score files in the `classic` folder), `--windowed` / `--fullscreen` (the display mode
  for this run), and the original arguments: `-s` (scores), `-d` (a death screen), or
  a save file name.

## Exporting and releasing
- **The presets** (`export_presets.cfg`): Windows (x86_64), macOS (universal: Intel and
  Apple Silicon, signed ad hoc by Godot, not notarized) and Linux (x86_64), each
  `Meta-Rogue` with its data embedded (in the `.app` on macOS), the icon (`icon.png`,
  drawn by `../tools/make_icon.py`) and `guild_prices.txt`; the tests are left out.
- **`../tools/export.sh --templates`** installs Godot's official export templates for
  its version (downloaded once, checksum checked) and makes the downloads in `../dist/`:
  `Meta-Rogue-VERSION-windows.zip`, `-macos.zip`, `-linux.zip` and `SHA256SUMS.txt`.
  Each zip holds the game, `README.txt` (`../INSTALL.md`), `LICENSES.txt` (Rogue's, the
  font's, and Godot's with its third-party notices) and, on Windows and Linux,
  `guild_prices.txt` next to the executable. Without `--templates` it uses the templates
  already installed.
- **`../tools/check_export.py [--run]`** checks them: the files, the executables'
  formats, the macOS bundle and signature, and each platform's game data (loaded by
  Godot: name, version, every script compiling, no tests). `--run` also plays the Linux
  build in a window on a virtual display: first launch, the Guild, the dungeon, save and
  restore, and the move of an old "Rogue" data folder.
- **A release:** raise `application/config/version` in `project.godot` and push.
  `../.github/workflows/release.yml` builds the downloads with the same script and, when
  the tag `vVERSION` doesn't exist yet, publishes them as the GitHub release `vVERSION`,
  with `../docs/RELEASE_NOTES.md` as its text (`@VERSION@` becomes the version). Pushes
  that keep the version only build.

## For developers
- `rogue/`: the game, one GDScript module per C file. `rogue_base.gd` holds the
  constants, macros and all game state.
- `curses/curses.gd`: an exact emulation of the ncurses subset Rogue uses.
- `guild/`: the Fighters' Guild (`RogueBase.guild`, `../docs/GUILD.md`).
- `ui/`: the terminal view and the scene controller. `main.tscn` is the main scene.
  `video_settings.gd` (detection, `video.cfg`, applying them to the window) and
  `settings_screen.gd` (*OPTIONS - VIDEO*) are the video settings; `user_data.gd` moves
  the files of the game's earlier name.
- `tests/`:
  - `replay.gd`: replays key scripts and writes step logs for the differential tests;
  - `check_all.gd`: compiles every script;
  - `curses_fuzz.gd`: the curses emulation side of the fuzzer;
  - `guild_test.gd`: the Guild's tests; `prices_test.gd`: its price file's;
  - `settings_test.gd`: the video settings (made-up screens, the file, the menu's
    keys, F10 and Alt+Enter in the main scene), headless;
  - `user_data_test.gd`: the user data folder and the move of the old one;
  - `ui_screenshot.gd`: a UI smoke test (`--video-cfg=FILE` applies video settings;
    `\f` in `--keys` is F10, `\a` Alt+Enter);
  - `ui_video.gd`: the video settings in a real window (first launch, the menu,
    windowed and fullscreen, monitors);
  - `with_display.sh`: runs a UI test on a virtual display (Xvfb) with a small window
    manager that does fullscreen (`mini_wm.py`), one or more monitors, and an empty
    user data folder, e.g.
    `tests/with_display.sh --screen=1920x1080 -- godot --path . --script res://tests/ui_video.gd`.

See `../CLAUDE.md` for commands and rules, and `../docs/` for the design, the
translation conventions and the fidelity policy.

The bundled font is DejaVu Sans Mono (license in `fonts/DejaVuSansMono-LICENSE.txt`).
