# Meta-Rogue: download, install, play

Meta-Rogue is Rogue 5.4.4, the 1980 dungeon crawler that named the roguelike
genre, ported screen for screen to the Godot engine, with a few things on top:
the known bugs fixed, item menus, and the Fighters' Guild, where the gold of your
Hall of Fame outfits each new hero.

It needs no installer and no other software: unzip it and run it.


## 1. Download

Get the zip for your computer from the Releases page:

    https://github.com/mw32445/meta-rogue/releases/latest

    Windows 10 or 11, 64-bit              Meta-Rogue-VERSION-windows.zip
    macOS 11 or later on Intel,           Meta-Rogue-VERSION-macos.zip
      macOS 13 or later on Apple Silicon
    Linux, 64-bit, from 2019 or later     Meta-Rogue-VERSION-linux.zip
      (glibc 2.28: Ubuntu 20.04, Debian 10, Fedora 29 or newer)

Any graphics from the last ten years will do (OpenGL 3.3). The game takes under
200 MB on disk. SHA256SUMS.txt, next to the zips, lists their checksums.


## 2. Install

### Windows

1. Right-click the zip and choose "Extract All...". Extract it to a folder you
   can write to, such as Documents or a Games folder (not Program Files: the
   Guild's price list next to the game should stay editable).
2. Open the Meta-Rogue folder and double-click Meta-Rogue.exe.
3. The first time, Windows SmartScreen may say "Windows protected your PC",
   because the program is not signed. Click "More info", then "Run anyway".

For a desktop shortcut: right-click Meta-Rogue.exe, then "Show more options",
"Send to", "Desktop (create shortcut)".

### macOS

1. Double-click the zip to unpack it (Safari may already have done it).
2. Drag Meta-Rogue.app into your Applications folder.
3. The first time you open it, macOS says it cannot verify the app, because it is
   not notarized by Apple. Click "Done", then open System Settings, Privacy &
   Security, scroll down to the message about Meta-Rogue, click "Open Anyway" and
   confirm. (On macOS 14 and earlier you can instead Control-click the app, choose
   "Open", then "Open" again.)

   Or, in Terminal:   xattr -dr com.apple.quarantine /Applications/Meta-Rogue.app

### Linux

1. Unzip it, with your file manager or:   unzip Meta-Rogue-VERSION-linux.zip
2. Run Meta-Rogue/Meta-Rogue.x86_64 (double-click it, or start it from a
   terminal). If it does not start, make it executable:
       chmod +x Meta-Rogue/Meta-Rogue.x86_64
3. For a menu entry, save this as ~/.local/share/applications/meta-rogue.desktop,
   with Exec set to where you put the game:

       [Desktop Entry]
       Type=Application
       Name=Meta-Rogue
       Exec=/home/YOU/Games/Meta-Rogue/Meta-Rogue.x86_64
       Categories=Game;RolePlaying;


## 3. Play

- The game starts fullscreen, at your screen's resolution. F10 opens the video
  settings (window or fullscreen, window size, monitor, VSync); Alt+Enter
  switches between a window and fullscreen.
- Each new game starts at the Fighters' Guild. The gold of your Hall of Fame buys
  training, arms, armour, rings, wands, potions, scrolls, supplies and skills:
      j k      choose                    1-9         change section
      Enter    buy                       Backspace   return
      ?        the coffers and keys      e           enter the dungeon
  Your first hero has nothing to spend: the coffers fill as your heroes die, or
  win. Skills change a rule of the game for that hero: Throw Anything makes thrown
  potions, scrolls, rings and wands work on the monster they hit, Coin Scrounger
  multiplies the gold you find, and so on. The text under the list says what the
  chosen skill does.
- In the dungeon you play Rogue as it was. "?" lists the commands and "/" names
  a symbol on the map. h j k l y u b n, the arrow keys or the keypad move; with
  Shift you run. A command that needs an item (read, quaff, wield, ...) lists the
  items that fit; type the item's letter.
- S saves the game and quits. The next start continues it. Closing the window
  during a game saves it too.
- The status line's "Exp: 2/15/20" reads: level 2, 15 experience points, level 3
  at 20.


## 4. Options

Options go after "--" on the command line:

    --classic       the untouched original Rogue 5.4.4: no Guild, no fixes, with
                    its own saves and scores
    --windowed      a window, for this run only (--fullscreen: fullscreen)
    --no-guild      new games start with the usual kit, without the Guild
    --rogueopts=O   Rogue's own options, e.g. --rogueopts=terse,fruit=kiwi

    Windows   make a shortcut to Meta-Rogue.exe; in its Properties, add
              -- --classic   at the end of "Target"
    macOS     in Terminal:   open -a Meta-Rogue --args -- --classic
    Linux     ./Meta-Rogue.x86_64 -- --classic


## 5. Your files

Your saved games, your Hall of Fame (rogue.scr) and your video settings
(video.cfg) are kept here:

    Windows   %APPDATA%\Meta-Rogue           (paste it into File Explorer's
                                               address bar)
    macOS     ~/Library/Application Support/Meta-Rogue    (Finder: Go, Go to
                                                           Folder...)
    Linux     ~/.local/share/Meta-Rogue

The classic game's (--classic) are in its "classic" folder. Earlier builds of
this game, from before it was called Meta-Rogue, kept these files in Godot's
folder for a game named "Rogue" (.../godot/app_userdata/Rogue). The first start
of Meta-Rogue copies them over and leaves the old folder as it was.


## 6. The Guild's prices

guild_prices.txt holds the Guild's price list and its formulas, the coffers'
too. It explains itself; change it with any text editor. The Guild reads it each
time it opens, and its "?" page shows where the file is and any line it cannot
use.

    Windows, Linux   next to the game (Meta-Rogue.exe, Meta-Rogue.x86_64). If
                     that folder cannot be written, the game keeps it in your
                     files' folder (section 5).
    macOS            in your files' folder (section 5); the game writes it there
                     the first time.

Delete it to get the original prices back: the game writes a fresh copy.


## 7. Updating and uninstalling

- To update, download the new zip and put its Meta-Rogue folder (or
  Meta-Rogue.app) in place of the old one. Your saves, Hall of Fame and settings
  are in your files' folder and stay. If you changed guild_prices.txt next to the
  game, keep your copy.
- To uninstall, delete the Meta-Rogue folder (or Meta-Rogue.app) and, if you
  wish, your files' folder (section 5).


## 8. From the source

Meta-Rogue is open source: https://github.com/mw32445/meta-rogue (the releases
have the source code as zips too). To play from the source, open
godot/project.godot in Godot 4.7 and press F5. To make these downloads yourself,
run tools/export.sh --templates (godot/README.md, "Exporting and releasing").
LICENSES.txt, next to the game, has the licences of Rogue, its font and Godot.
