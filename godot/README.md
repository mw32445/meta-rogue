# Rogue for Godot

Rogue 5.4.4 (Michael Toy, Ken Arnold and Glenn Wichman, 1980–1999), ported to Godot 4.7
in GDScript. The port is **1:1**: given the same seed and keystrokes, it shows exactly
the same screens and makes exactly the same random choices as the original C program.
This is verified step by step against the original (see `../docs/ARCHITECTURE.md`).

## Playing
- **Run it:** open `godot/project.godot` in Godot 4.7 or later and press **F5** (or
  *Project → Run*). You can also export it like any Godot project.
- **Keys:** the original commands, as on a terminal.
  - `h j k l y u b n` move; Shift+direction runs.
  - `?` lists all commands and `/` identifies a symbol.
  - Arrow keys, Home/End/PageUp/PageDown and the numeric keypad also move.
    Shift+arrows and Ctrl+arrows run.
  - Keypad 5 does what it did in 5.4.4 on most terminals: it acts like `u` (a known
    quirk, kept).
- **Options:** the `o` command, or the `ROGUEOPTS` environment variable, or
  `--rogueopts=...` on the command line (after `--`). For example:
  `ROGUEOPTS="terse,jump,inven=slow,fruit=kiwi"`.
- **Save:** `S` saves and exits.
  - Saved games and the score file live in Godot's user data folder (the game's "home"),
    e.g. `~/.local/share/godot/app_userdata/Rogue/` on Linux.
  - The next start restores a saved game automatically and deletes the save, like
    `rogue -r`.
  - Closing the window during a game saves it, as the original does when its terminal
    hangs up.
- **End of game:** when a game ends, you see the top-ten list. Enter starts a new
  game; Esc quits.
- **Command line** (after `--`): `--rogueopts=OPTS`, `--master` (enables the wizard-mode
  code; the original's `MASTER` build), and the original arguments: `-s` (scores),
  `-d` (a death screen), or a save file name.

## For developers
- `rogue/`: the game, one GDScript module per C file. `rogue_base.gd` holds the
  constants, macros and all game state.
- `curses/curses.gd`: an exact emulation of the ncurses subset Rogue uses.
- `ui/`: the terminal view and the scene controller. `main.tscn` is the main scene.
- `tests/`:
  - `replay.gd`: replays key scripts and writes step logs for the differential tests;
  - `check_all.gd`: compiles every script;
  - `curses_fuzz.gd`: the curses emulation side of the fuzzer;
  - `ui_screenshot.gd`: a UI smoke test.

See `../CLAUDE.md` for commands and rules, and `../docs/` for the design, the
translation conventions and the fidelity policy.

The bundled font is DejaVu Sans Mono (license in `fonts/DejaVuSansMono-LICENSE.txt`).
