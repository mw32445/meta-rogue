#!/usr/bin/env python3
"""Check the downloads that tools/export.sh made (dist/).

  - Every zip: what it holds. README.txt is INSTALL.md, guild_prices.txt is the
    game's, LICENSES.txt has its three parts, and SHA256SUMS.txt matches.
  - The executables:
      Windows: PE x86-64, with the name and version in its version info.
      Linux:   ELF x86-64, executable.
      macOS:   a universal Mach-O (x86_64 + arm64); Info.plist has the name, id and
               version; the app is signed (ad hoc).
  - Each platform's game data (the .pck, embedded or in the .app), loaded by Godot
    (tools/check_pck.gd): the name and version, guild_prices.txt, and every game
    script there and compiling, with no tests.
  - With --run, the Linux game itself, in a window on a virtual display (Xvfb,
    godot/tests/with_display.sh, keys sent by XTest):
      1. a first launch: fullscreen at the screen's size, and the Meta-Rogue data
         folder with video.cfg;
      2. the Guild, then into the dungeon, then save (S, y): rogue.save is written;
      3. a relaunch restores it (and deletes it, like rogue -r);
      4. a "Rogue" data folder (the game's earlier name) is copied over: its
         video.cfg (windowed 1600 x 900) decides the window.
    Screenshots go to the folder given by --shots.

usage: tools/check_export.py [--run] [--shots=DIR] [DIST]   (DIST: default dist/)
GODOT=/path/to/godot overrides the binary (default: godot on PATH, else /root/bin/godot).
Exit status 1 on any failure.
"""
import hashlib
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = "Meta-Rogue"
GODOT = os.environ.get("GODOT") or shutil.which("godot") or "/root/bin/godot"
failed = []


def check(what, ok, detail=""):
    if not ok:
        failed.append(what)
        print(f"FAIL {what} {detail}".rstrip())
    return ok


def version():
    m = re.search(r'^config/version="(.*)"$', open(os.path.join(ROOT, "godot", "project.godot")).read(), re.M)
    return m.group(1)


def read(path, mode="r"):
    with open(path, mode) as f:
        return f.read()


# ---- the zips -----------------------------------------------------------------

def check_zip(z, os_, ver, top, out):
    """Unpack z into out; check the files around the game."""
    with zipfile.ZipFile(z) as zf:
        names = set(zf.namelist())
        zf.extractall(out)
        for info in zf.infolist():	# zipfile drops the permissions: put them back
            mode = info.external_attr >> 16
            if mode:
                os.chmod(os.path.join(out, info.filename), mode & 0o777)
    check(f"{os_}: the zip is under 100 MB", os.path.getsize(z) < 100 * 2**20, os.path.getsize(z))
    base = os.path.join(out, top)
    check(f"{os_}: README.txt is INSTALL.md",
          read(os.path.join(base, "README.txt")) == read(os.path.join(ROOT, "INSTALL.md")))
    lic = read(os.path.join(base, "LICENSES.txt"))
    check(f"{os_}: LICENSES.txt has Rogue's, the font's and Godot's (with its components)",
          f"Meta-Rogue {ver}" in lic and "Rogue: Exploring the Dungeons of Doom" in lic
          and "Bitstream Vera" in lic and "Godot Engine contributors" in lic and "FreeType" in lic)
    if os_ != "macos":
        check(f"{os_}: guild_prices.txt next to the game is the game's",
              read(os.path.join(base, "guild_prices.txt")) == read(os.path.join(ROOT, "godot", "guild_prices.txt")))
    return names


def check_pck(os_, pck, ver):
    """tools/check_pck.gd on a .pck or an executable holding one."""
    r = subprocess.run([GODOT, "--headless", "--main-pack", pck, "--script",
                        os.path.join(ROOT, "tools", "check_pck.gd"), "--",
                        "--src=" + os.path.join(ROOT, "godot"), "--name=" + NAME, "--version=" + ver],
                       cwd=tempfile.gettempdir(), capture_output=True, text=True, timeout=300)
    ok = r.returncode == 0 and "check_pck: OK" in r.stdout
    check(f"{os_}: the game data loads (name, version, prices, every script, no tests)", ok,
          "\n" + "\n".join(l for l in r.stdout.splitlines() if l.startswith("check_pck")))


def check_windows(z, ver, tmp):
    out = os.path.join(tmp, "windows")
    names = check_zip(z, "windows", ver, NAME, out)
    check("windows: the files", names >= {f"{NAME}/{NAME}.exe", f"{NAME}/guild_prices.txt",
                                           f"{NAME}/README.txt", f"{NAME}/LICENSES.txt"}, sorted(names))
    exe = os.path.join(out, NAME, NAME + ".exe")
    d = read(exe, "rb")
    pe = struct.unpack_from("<I", d, 0x3C)[0] if d[:2] == b"MZ" else 0
    check("windows: a PE x86-64 executable", pe and d[pe:pe + 4] == b"PE\0\0"
          and struct.unpack_from("<H", d, pe + 4)[0] == 0x8664)
    check("windows: its version info names Meta-Rogue and the version",
          NAME.encode("utf-16-le") in d and ver.encode("utf-16-le") in d)
    check_pck("windows", exe, ver)


def check_linux(z, ver, tmp):
    out = os.path.join(tmp, "linux")
    names = check_zip(z, "linux", ver, NAME, out)
    check("linux: the files", names >= {f"{NAME}/{NAME}.x86_64", f"{NAME}/guild_prices.txt",
                                         f"{NAME}/README.txt", f"{NAME}/LICENSES.txt"}, sorted(names))
    exe = os.path.join(out, NAME, NAME + ".x86_64")
    d = read(exe, "rb")[:64]
    check("linux: an ELF x86-64 executable", d[:4] == b"\x7fELF" and d[4] == 2
          and struct.unpack_from("<H", d, 18)[0] == 0x3E)
    check("linux: it can be run as unzipped", os.access(exe, os.X_OK))
    check_pck("linux", exe, ver)
    return exe


def check_macos(z, ver, tmp):
    out = os.path.join(tmp, "macos")
    names = check_zip(z, "macos", ver, "", out)
    app = f"{NAME}.app/Contents/"
    want = {app + "Info.plist", app + f"MacOS/{NAME}", app + f"Resources/{NAME}.pck",
            app + "Resources/icon.icns", app + "_CodeSignature/CodeResources", "README.txt", "LICENSES.txt"}
    check("macos: the files", names >= want, sorted(want - names))
    p = plistlib.loads(read(os.path.join(out, app, "Info.plist"), "rb"))
    check("macos: Info.plist names Meta-Rogue, its id and version",
          p.get("CFBundleName") == NAME and p.get("CFBundleExecutable") == NAME
          and p.get("CFBundleIdentifier") == "io.github.mw32445.metarogue"
          and p.get("CFBundleShortVersionString") == ver, p)
    print(f"macos: minimum macOS {p.get('LSMinimumSystemVersionByArchitecture')}")
    exe = os.path.join(out, app, "MacOS", NAME)
    d = read(exe, "rb")
    arches = []
    if d[:4] == b"\xca\xfe\xba\xbe":	# a universal (fat) binary, big-endian header
        for i in range(struct.unpack_from(">I", d, 4)[0]):
            arches.append(struct.unpack_from(">I", d, 8 + 20 * i)[0])
    check("macos: a universal binary, Intel and Apple Silicon", sorted(arches) == [0x01000007, 0x0100000C],
          [hex(a) for a in arches])
    check("macos: the binary can be run as unzipped", os.access(exe, os.X_OK))
    res = read(os.path.join(out, app, "_CodeSignature", "CodeResources"))
    check("macos: the app is signed (its signature covers the game data)", f"Resources/{NAME}.pck" in res)
    check_pck("macos", os.path.join(out, app, "Resources", NAME + ".pck"), ver)


def check_sums(dist, zips):
    sums = {}
    for line in read(os.path.join(dist, "SHA256SUMS.txt")).splitlines():
        h, f = line.split(None, 1)
        sums[f.lstrip("*")] = h
    for z in zips:
        h = hashlib.sha256(read(z, "rb")).hexdigest()
        check(f"SHA256SUMS.txt: {os.path.basename(z)}", sums.get(os.path.basename(z)) == h)


# ---- the Linux game in a window ---------------------------------------------------

def run_in_display(exe, shots):
    """Run this script's --inside part on a virtual 1920 x 1080 display."""
    r = subprocess.run([os.path.join(ROOT, "godot", "tests", "with_display.sh"), "--keep-data", "--",
                        sys.executable, os.path.abspath(__file__), "--inside", exe, shots], timeout=600)
    check("run: the game in a window", r.returncode == 0)


class Display:
    """Just enough Xlib (and XTest) to find the game's window and type into it."""

    def __init__(self):
        import ctypes
        self.c = ctypes
        self.x = ctypes.cdll.LoadLibrary("libX11.so.6")
        self.xt = ctypes.cdll.LoadLibrary("libXtst.so.6")
        x = self.x
        x.XOpenDisplay.restype = ctypes.c_void_p
        x.XOpenDisplay.argtypes = [ctypes.c_char_p]
        x.XDefaultRootWindow.restype = ctypes.c_ulong
        x.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        x.XQueryTree.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                                 ctypes.POINTER(ctypes.c_ulong), ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
                                 ctypes.POINTER(ctypes.c_uint)]
        x.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
        x.XGetGeometry.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_ulong),
                                   ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int),
                                   ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint),
                                   ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]
        x.XStringToKeysym.restype = ctypes.c_ulong
        x.XStringToKeysym.argtypes = [ctypes.c_char_p]
        x.XKeysymToKeycode.restype = ctypes.c_ubyte
        x.XKeysymToKeycode.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
        x.XFlush.argtypes = [ctypes.c_void_p]
        x.XFree.argtypes = [ctypes.c_void_p]
        self.xt.XTestFakeKeyEvent.argtypes = [ctypes.c_void_p, ctypes.c_uint, ctypes.c_int, ctypes.c_ulong]
        self.d = x.XOpenDisplay(None)
        if not self.d:
            raise RuntimeError("no display")

    def windows(self, w=None):
        """Every window under w (default: the root), depth first."""
        c = self.c
        w = w or self.x.XDefaultRootWindow(self.d)
        root, parent, n = c.c_ulong(), c.c_ulong(), c.c_uint()
        kids = c.POINTER(c.c_ulong)()
        out = []
        if self.x.XQueryTree(self.d, w, c.byref(root), c.byref(parent), c.byref(kids), c.byref(n)):
            for i in range(n.value):
                out.append(kids[i])
                out += self.windows(kids[i])
            if kids:
                self.x.XFree(kids)
        return out

    def find(self, title):
        """The window named title, as (window, width, height), or None."""
        c = self.c
        for w in self.windows():
            name = c.c_char_p()
            if self.x.XFetchName(self.d, w, c.byref(name)) and name.value:
                if name.value.decode(errors="replace") == title:
                    r, x, y, wd, ht, b, dp = (c.c_ulong(), c.c_int(), c.c_int(), c.c_uint(), c.c_uint(),
                                              c.c_uint(), c.c_uint())
                    self.x.XGetGeometry(self.d, w, *(c.byref(v) for v in (r, x, y, wd, ht, b, dp)))
                    return (w, wd.value, ht.value)
        return None

    def key(self, name, shift=False):
        kc = self.x.XKeysymToKeycode(self.d, self.x.XStringToKeysym(name.encode()))
        sh = self.x.XKeysymToKeycode(self.d, self.x.XStringToKeysym(b"Shift_L"))
        if shift:
            self.xt.XTestFakeKeyEvent(self.d, sh, 1, 0)
        self.xt.XTestFakeKeyEvent(self.d, kc, 1, 0)
        self.xt.XTestFakeKeyEvent(self.d, kc, 0, 0)
        if shift:
            self.xt.XTestFakeKeyEvent(self.d, sh, 0, 0)
        self.x.XFlush(self.d)
        time.sleep(0.4)

    def type(self, text):
        for ch in text:
            if ch == "\n":
                self.key("Return")
            elif ch == "\x1b":
                self.key("Escape")
            else:
                self.key(ch.lower(), ch.isupper())


def wait_for(cond, secs):
    end = time.time() + secs
    while time.time() < end:
        v = cond()
        if v:
            return v
        time.sleep(0.25)
    return cond()


def inside(exe, shots):
    """The --run checks, on the virtual display."""
    from PIL import ImageGrab
    dpy = Display()
    os.makedirs(shots, exist_ok=True)
    work = tempfile.mkdtemp(prefix="meta-rogue-run.")
    errors = []

    def launch(data, tag):
        env = dict(os.environ, XDG_DATA_HOME=data)
        log = open(os.path.join(work, tag + ".log"), "w")
        p = subprocess.Popen([exe], cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT)
        win = wait_for(lambda: dpy.find(NAME), 60)
        check(f"{tag}: a window named Meta-Rogue", win is not None)
        time.sleep(3)	# the video settings apply, the first screen is drawn
        return p, dpy.find(NAME) or win

    def shot(tag):
        ImageGrab.grab(xdisplay=os.environ["DISPLAY"]).save(os.path.join(shots, tag + ".png"))

    def finish(p, tag):
        if p.poll() is None:
            p.terminate()
            p.wait(10)
        text = read(os.path.join(work, tag + ".log"))
        bad = [l for l in text.splitlines() if re.search(r"SCRIPT ERROR|Parse Error|Failed to load|Invalid call", l)]
        errors.extend(bad)
        check(f"{tag}: no script errors", not bad, "\n" + "\n".join(bad[:10]))

    # 1-3: a first launch, a game saved, and restored
    data = os.path.join(work, "data")
    mine = os.path.join(data, NAME)
    p, win = launch(data, "first")
    if win:
        check("first: fullscreen at the screen's size", (win[1], win[2]) == (1920, 1080), win[1:])
        check("first: the Meta-Rogue data folder, with video.cfg",
              os.path.isfile(os.path.join(mine, "video.cfg")))
        check("first: the price file next to the game is the one read (none written to the data folder)",
              not os.path.exists(os.path.join(mine, "guild_prices.txt")))
        shot("1-guild")
        dpy.type("e")
        dpy.type("y")
        time.sleep(2)
        shot("2-dungeon")
        dpy.type("S")
        dpy.type("y")
        saved = wait_for(lambda: os.path.isfile(os.path.join(mine, "rogue.save")), 10)
        check("first: S and y save the game", saved)
        time.sleep(1)
        shot("3-saved")
        dpy.type("\x1b")
        check("first: Escape on the end screen quits", wait_for(lambda: p.poll() is not None, 15)
              and p.returncode == 0, p.returncode)
    finish(p, "first")
    p, win = launch(data, "restore")
    if win:
        check("restore: the saved game is restored (and its file deleted)",
              wait_for(lambda: not os.path.exists(os.path.join(mine, "rogue.save")), 15))
        time.sleep(1)
        shot("4-restored")
    finish(p, "restore")

    # 4: a data folder from the game's earlier name, "Rogue"
    data = os.path.join(work, "old")
    old = os.path.join(data, "godot", "app_userdata", "Rogue")
    os.makedirs(os.path.join(old, "classic"))
    os.makedirs(os.path.join(old, "logs"))
    open(os.path.join(old, "video.cfg"), "w").write(
        '[video]\n\nmode="windowed"\nsize=Vector2i(1600, 900)\nscreen=0\nvsync=true\n')
    for f in ("rogue.scr", "rogue.lck", "classic/rogue.scr"):
        open(os.path.join(old, f), "w").close()
    open(os.path.join(old, "logs", "godot.log"), "w").write("the old log\n")
    p, win = launch(data, "migrate")
    if win:
        mine = os.path.join(data, NAME)
        check("migrate: the old video.cfg is used (windowed 1600 x 900)", (win[1], win[2]) == (1600, 900), win[1:])
        log = os.path.join(mine, "logs", "godot.log")	# this run's own log
        check("migrate: the player's files are copied, not the lock or the logs",
              all(os.path.isfile(os.path.join(mine, f)) for f in ("video.cfg", "rogue.scr", "classic/rogue.scr"))
              and not os.path.exists(os.path.join(mine, "rogue.lck"))
              and not (os.path.isfile(log) and "the old log" in read(log)))
        check("migrate: the old folder is left as it was", os.path.isfile(os.path.join(old, "rogue.lck")))
        shot("5-migrated")
    finish(p, "migrate")
    shutil.rmtree(work, ignore_errors=True)


# ---- main -------------------------------------------------------------------------

def main():
    args = sys.argv[1:]
    if args[:1] == ["--inside"]:
        inside(args[1], args[2])
        print(f"run: {len(failed)} failure(s)")
        return 1 if failed else 0
    run = "--run" in args
    shots = next((a[len("--shots="):] for a in args if a.startswith("--shots=")),
                 os.path.join(ROOT, "harness", "out", "export_shots"))
    rest = [a for a in args if not a.startswith("--")]
    dist = os.path.abspath(rest[0] if rest else os.path.join(ROOT, "dist"))
    ver = version()
    zips = {o: os.path.join(dist, f"{NAME}-{ver}-{o}.zip") for o in ("windows", "macos", "linux")}
    for o, z in zips.items():
        if not check(f"{o}: {os.path.basename(z)} exists", os.path.isfile(z)):
            return 1
    tmp = tempfile.mkdtemp(prefix="meta-rogue-check.")
    try:
        check_sums(dist, zips.values())
        check_windows(zips["windows"], ver, tmp)
        check_macos(zips["macos"], ver, tmp)
        exe = check_linux(zips["linux"], ver, tmp)
        if run:
            run_in_display(exe, os.path.abspath(shots))
            print(f"run: screenshots in {shots}")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print(f"check_export: {'OK' if not failed else f'{len(failed)} failure(s)'} ({NAME} {ver})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
