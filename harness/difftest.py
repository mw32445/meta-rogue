#!/usr/bin/env python3
"""Differential test: the C oracle vs the Godot port on identical inputs.

Both programs get the same seed, pinned environment and key script, and write a
step log (harness/DUMP_FORMAT.md). The first differing step is the divergence;
the report re-runs both with full screens around it.

  difftest.py one --seed N --keys FILE [common options]
  difftest.py fuzz --count N [--len L] [--first-seed S] [--jobs J] [common options]
  difftest.py corpus [DIR]          replay every *.keys file (seed/options in its header)
  difftest.py seeds --count N [--first-seed S]   first screen of many seeds (level generation)
  difftest.py saves --count N [--len L] ...      save/restore chains (play, save, restore, ...)
  difftest.py smoke --count N [--wizard] [--fixes] [--guild] [--menus]
                                    the port alone on random scripts, for the switches the
                                    oracle cannot judge: every run must end with no script
                                    error (--guild gives each run a random Guild loadout)

common options: --opts ROGUEOPTS | --no-opts, --master, --fixes, --arg A, --keep

--fixes compares the port with RogueBase.fixes on against the "fixed" oracle (C with
harness/oracle/fixes.patch); with --master/--wizard, "fixedmaster".

Key files: decimal key codes separated by whitespace; '#' starts a comment. A
header line "# difftest: seed=N opts=... master=1 fixes=1 arg=..." stores the run
options. Lines "# expect-classic: TEXT" / "# expect-fixed: TEXT" say that TEXT must
appear on some screen (or in stdout) of the port's run in that mode;
"# expect-not-classic: TEXT" / "# expect-not-fixed: TEXT" say it must not. They check
the behavior itself, which the oracle diff cannot (both sides implement the same thing).
"""
import argparse
import concurrent.futures as cf
import os
import random
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GODOT = os.environ.get("GODOT", shutil.which("godot") or "/root/bin/godot")
OUT = os.path.join(HERE, "out")
TIME = 1000000000
HOME = "./"
NAME = "rodney"
UID = 1000


def oracle_bin(master, variant=None, fixes=False):
    v = variant or ("fixed" if fixes else "") + ("master" if master else "") or "std"
    p = os.path.join(HERE, "oracle", "build", v, "rogue-oracle")
    if not os.path.exists(p):
        subprocess.run([os.path.join(HERE, "oracle", "build.sh"), v], check=True, stdout=subprocess.DEVNULL)
    return p


# ------------------------------------------------------------------ running

def runs_of(case):
    """A case is one run, or a chain of runs sharing a directory (save, then restore)."""
    return case["chain"] if case.get("chain") else [case]


def tag(case, k):
    """File-name tag of run k: dump{tag}.txt, stdout{tag}.bin."""
    return str(k) if case.get("chain") else ""


def run_oracle(case, d, full=None, t=""):
    os.makedirs(d, exist_ok=True)
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "TERM": "xterm", "LINES": "24",
           "COLUMNS": "80", "TZ": "UTC", "ROGUE_SEED": str(case["seed"]), "ROGUE_TIME": str(TIME),
           "ROGUE_NAME": NAME, "ROGUE_HOME": HOME, "ROGUE_UID": str(UID),
           "ROGUE_KEYS": case["keys"], "ROGUE_DUMP": os.path.join(d, f"dump{t}.txt")}
    if case.get("opts") is not None:
        env["ROGUEOPTS"] = case["opts"]
    if full is not None:
        env["ROGUE_FULL"] = str(full)
    argv = [oracle_bin(case.get("master"), case.get("variant"), case.get("fixes"))] + case.get("args", [])
    with open(os.path.join(d, f"stdout{t}.bin"), "wb") as so:
        try:
            subprocess.run(argv, cwd=d, env=env, stdout=so, stderr=subprocess.DEVNULL, timeout=60)
        except subprocess.TimeoutExpired:
            open(os.path.join(d, f"dump{t}.txt"), "a").write("TIMEOUT\n")


def run_oracle_all(case, d, full=None, full_run=None):
    """Run a case (every run of a chain, in order, in one directory)."""
    for k, sub in enumerate(runs_of(case)):
        run_oracle(sub, d, full if full_run in (None, k) else None, tag(case, k))


def port_line(case, d, full=None, t=""):
    os.makedirs(d, exist_ok=True)
    kv = {"seed": case["seed"], "time": TIME, "name": NAME, "home": HOME, "uid": UID,
          "keys": case["keys"], "dump": os.path.join(d, f"dump{t}.txt"),
          "stdout": os.path.join(d, f"stdout{t}.bin"), "cwd": d}
    if case.get("opts") is not None:
        kv["opts"] = case["opts"]
    if case.get("master"):
        kv["master"] = "1"
    if case.get("fixes"):
        kv["fixes"] = "1"
    for sw in ("guild", "menus"):
        if case.get(sw):
            kv[sw] = "1"
    if case.get("loadout"):
        kv["loadout"] = case["loadout"]
    if case.get("args"):
        kv["arg"] = "\x1f".join(case["args"])
    if full is not None:
        kv["full"] = full
    return "\t".join(f"{k}={v}" for k, v in kv.items())


def port_lines(case, d, full=None, full_run=None):
    """Batch lines for a case; a chain's runs stay together and in order."""
    return [port_line(sub, d, full if full_run in (None, k) else None, tag(case, k))
            for k, sub in enumerate(runs_of(case))]


def run_port_batch(lines, workdir):
    """Run the port on a batch of runs in one Godot process; returns the stderr file."""
    batch = os.path.join(workdir, f"batch{os.getpid()}_{random.random():.9f}.txt")
    with open(batch, "w") as f:
        f.write("\n".join(lines) + "\n")
    err = batch + ".err"
    try:
        subprocess.run([GODOT, "--headless", "--path", os.path.join(ROOT, "godot"), "--script",
                        "res://tests/replay.gd", "--", "--batch", batch],
                       stdout=subprocess.DEVNULL, stderr=open(err, "w"), timeout=120 + 20 * len(lines))
    except subprocess.TimeoutExpired:
        open(err, "a").write("TIMEOUT: the Godot batch was killed\n")
    return err


def port_errors(err, limit=12):
    """The first engine errors in a port run's stderr (GDScript errors and their locations)."""
    try:
        lines = open(err, errors="replace").read().splitlines()
    except FileNotFoundError:
        return []
    out = []
    for i, l in enumerate(lines):
        if "ERROR" in l or l.startswith("TIMEOUT"):
            out.append(l.strip())
            for m in lines[i + 1:i + 4]:
                if m.strip().startswith(("at:", "[0]", "[1]", "[2]")):
                    out.append("    " + m.strip())
        if len(out) >= limit:
            break
    return out


# --------------------------------------------------------------- comparing

def parse_log(path):
    try:
        lines = open(path).read().splitlines()
    except FileNotFoundError:
        return []
    return [l for l in lines if l.startswith(("S", "END", "EXIT", "TIMEOUT"))]


def step_equal(a, b):
    if a == b:
        return True
    fa, fb = a.split(), b.split()
    if len(fa) != len(fb):
        return False
    for x, y in zip(fa, fb):
        if x != y and not (x[0] == "C" and y[0] == "C" and "?" in (x, y) or x == "C?" or y == "C?"):
            return False
    return True


def compare(case, d):
    """None, or (run, log line index, oracle line, port line) of the first difference;
    a log line index of -1 means the stdout bytes differ."""
    for k in range(len(runs_of(case))):
        t = tag(case, k)
        o = parse_log(os.path.join(d, "oracle", f"dump{t}.txt"))
        p = parse_log(os.path.join(d, "port", f"dump{t}.txt"))
        for i, (a, b) in enumerate(zip(o, p)):
            if not step_equal(a, b):
                return k, i, a, b
        if len(o) != len(p):
            i = min(len(o), len(p))
            return k, i, (o[i] if i < len(o) else "<end of log>"), (p[i] if i < len(p) else "<end of log>")
        fo, fp = os.path.join(d, "oracle", f"stdout{t}.bin"), os.path.join(d, "port", f"stdout{t}.bin")
        so = open(fo, "rb").read() if os.path.exists(fo) else b""
        sp = open(fp, "rb").read() if os.path.exists(fp) else b""
        if so != sp:
            return k, -1, repr(so[-200:]), repr(sp[-200:])
    return None


def expect_mode(case):
    return "fixed" if case.get("fixes") else "classic"


def check_expect(case, d):
    """Failed expectations ("# expect-...") of this case's mode, against every screen
    of the port's full dumps and its stdout."""
    exp = [(pos, text) for mode, pos, text in case.get("expect", []) if mode == expect_mode(case)]
    if not exp:
        return []
    seen = []
    for k in range(len(runs_of(case))):
        t = tag(case, k)
        try:
            seen += [l[1:-1] for l in open(os.path.join(d, "port", f"dump{t}.txt")).read().splitlines()
                     if l.startswith("|")]
        except FileNotFoundError:
            pass
        try:
            seen += open(os.path.join(d, "port", f"stdout{t}.bin"), "rb").read().decode("latin-1").splitlines()
        except FileNotFoundError:
            pass
    bad = []
    for pos, text in exp:
        found = any(text in l for l in seen)
        if found != pos:
            bad.append(f"  expect-{'' if pos else 'not-'}{expect_mode(case)}: {text!r} "
                       f"{'never appeared' if pos else 'appeared'}")
    return bad


def full_dump(path, step):
    """Return (screen rows, extra, digest) for a step from a full-mode log."""
    lines = open(path).read().splitlines()
    for i, l in enumerate(lines):
        if l.startswith(f"S{step} "):
            rows = [x for x in lines[i + 1:i + 25] if x.startswith("|")]
            extra = next((x for x in lines[i + 1:i + 28] if x.startswith("E")), "")
            dg = next((x for x in lines[i + 1:i + 29] if x.startswith("G ")), "")
            return rows, extra, dg
    return [], "", ""


def report(case, d, run, idx, a, b):
    out = [f"DIVERGENCE seed={case['seed']} keys={case['keys']} opts={case.get('opts')!r} "
           f"master={bool(case.get('master'))} fixes={bool(case.get('fixes'))} args={case.get('args', [])}"]
    if case.get("chain"):
        sub = case["chain"][run]
        out.append(f"  in run {run + 1} of {len(case['chain'])} of the chain (args={sub.get('args', [])}, "
                   f"keys={sub['keys']})")
    if idx == -1:
        out.append(f"  stdout differs\n    oracle: ...{a}\n    port:   ...{b}")
        return "\n".join(out)
    out.append(f"  log line {idx + 1}:\n    oracle: {a}\n    port:   {b}")
    step = int(a[1:].split()[0]) if a.startswith("S") else int(b[1:].split()[0]) if b.startswith("S") else None
    if step is None:
        return "\n".join(out)
    first = max(1, step - 1)
    t = tag(case, run)
    run_oracle_all(case, os.path.join(d, "oracle_full"), full=first, full_run=run)
    err = run_port_batch(port_lines(case, os.path.join(d, "port_full"), full=first, full_run=run), d)
    errs = port_errors(err)
    if errs:
        out.append("  port errors:\n    " + "\n    ".join(errs))
    ro, eo, go = full_dump(os.path.join(d, "oracle_full", f"dump{t}.txt"), step)
    rp, ep, gp = full_dump(os.path.join(d, "port_full", f"dump{t}.txt"), step)
    keys = [int(x) for x in " ".join(l.split("#")[0] for l in open(runs_of(case)[run]["keys"]).read().splitlines()).split()]
    recent = keys[max(0, step - 12):step]
    out.append(f"  keys before step {step}: {' '.join(_keyname(k) for k in recent)}")
    out.append("  screen (oracle | port, '*' marks differing rows):")
    for y in range(max(len(ro), len(rp))):
        r1 = ro[y] if y < len(ro) else ""
        r2 = rp[y] if y < len(rp) else ""
        out.append(f"  {'*' if r1 != r2 else ' '}{y:2d} {r1}   {r2}")
    if eo != ep:
        out.append(f"  attrs oracle: {eo[:300]}\n  attrs port:   {ep[:300]}")
    if go != gp:
        fo, fp = go.split(), gp.split()
        diffs = [(x, y) for x, y in zip(fo, fp) if x != y]
        out.append(f"  digest differs: {diffs[:8]}{' ...' if len(diffs) > 8 else ''}")
        if len(fo) != len(fp):
            out.append(f"  digest oracle: {go[:600]}\n  digest port:   {gp[:600]}")
    return "\n".join(out)


def _keyname(k):
    if 32 < k < 127:
        return chr(k)
    return {32: "SP", 27: "ESC", 10: "\\n", 13: "\\r", 127: "DEL"}.get(k, f"^{chr(k + 64)}" if k < 32 else str(k))


# ------------------------------------------------------------- generating

LETTERS = "abcdefghijklmnopqrstuvwxyz"
MOVES = "hjklyubn"


def gen_keys(rng, n):
    """A weighted random key script (see docs/PORT_PLAN.md Phase 4)."""
    keys = []
    o = ord
    while len(keys) < n:
        p = rng.random()
        if p < 0.40:                                   # walk
            keys += [o(rng.choice(MOVES))] * rng.choice([1, 1, 1, 2, 3, 5])
        elif p < 0.47:                                 # run
            keys.append(o(rng.choice(MOVES.upper())))
        elif p < 0.49:                                 # run until adjacent (^H ^J ...)
            keys.append(o(rng.choice(MOVES.upper())) - 64)
        elif p < 0.55:
            keys.append(o(rng.choice("s.s.s,")))
        elif p < 0.62:                                 # --More--, cancel
            keys.append(rng.choice([32, 32, 32, 27]))
        elif p < 0.75:                                 # item commands + an item letter
            keys.append(o(rng.choice("qrewWTPRdcIq")))
            keys.append(rng.choice([o(c) for c in "abcdefgh"] * 3 + [o("*"), 27, o(rng.choice(LETTERS))]))
        elif p < 0.81:                                 # directional commands
            keys.append(o(rng.choice("tzfFm^")))
            keys.append(o(rng.choice(MOVES)) if rng.random() < 0.85 else 27)
            if keys[-2] in (o("t"), o("z")):
                keys.append(rng.choice([o(c) for c in "abcdefgh"] + [27]))
        elif p < 0.86:
            keys.append(o(rng.choice("i>< D/?)]=@v")))
            if keys[-1] == o("/") or keys[-1] == o("?"):
                keys.append(o(rng.choice("*abcdefghijklmnopqrstuvwxyzHJK@%#.")))
        elif p < 0.89:                                 # counts
            keys += [o(c) for c in str(rng.randint(1, 30))] + [o(rng.choice("s.hjkl"))]
        elif p < 0.91:
            keys.append(rng.choice([16, 18, 1]))       # ^P ^R ^A
        elif p < 0.93:                                 # call: c<letter><name>\n
            keys += [o("c"), o(rng.choice("abcdef"))] + [o(c) for c in rng.choice(["foo", "x", "bar baz", ""])] + [10]
        elif p < 0.95:                                 # options screen
            keys.append(o("o"))
            keys += [rng.choice([10, 13, o("t"), o("f"), 27, o("-")]) for _ in range(rng.randint(1, 12))]
        elif p < 0.96:
            keys += [o("Q"), o(rng.choice("ny"))]
        elif p < 0.965:
            keys += [o("!"), 10]
        elif p < 0.97:
            keys.append(3)                             # ^C
        else:
            keys.append(rng.choice([o(c) for c in LETTERS + LETTERS.upper() + "0123456789!@#$%&*()_+-=[]{};:'\",.<>/?|~`"] + [10, 13, 127, 8, 9, 26]))
    return keys[:n]


# create_obj (wizard 'C'): item type -> number of kinds ("which" keys 0-9a-h)
CREATE = {"!": 14, "?": 18, "/": 14, "=": 14, ")": 9, "]": 8, ":": 2, ",": 1}
BLESSED_RINGS = (0, 1, 7, 8)        # R_PROTECT R_ADDSTR R_ADDHIT R_ADDDAM ask "blessing?"


def create_keys(rng):
    """Keys for one wizard 'C'reate of a valid object."""
    o = ord
    t = rng.choice(list(CREATE) + ["*"])
    if t == "*":
        return [o("C"), o("*")] + [o(c) for c in str(rng.randint(1, 500))] + [13]
    w = rng.randrange(CREATE[t])
    keys = [o("C"), o(t), o("0123456789abcdefgh"[w])]
    if t in ")]" or (t == "=" and w in BLESSED_RINGS):
        keys.append(o(rng.choice("+-n")))
    return keys


def gen_keys_wizard(rng, n):
    """Random play mixed with wizard commands (run with args [""], the MASTER oracle):
    levels down/up (never above level 1), map, teleport, creating every kind of
    object, power-up, whatis, object lists."""
    keys = []
    depth = 1
    o = ord
    while len(keys) < n:
        p = rng.random()
        if p < 0.55:
            keys += gen_keys(rng, rng.randint(5, 40))
        elif p < 0.65:
            keys += create_keys(rng)
            keys += [32, 32]
        elif p < 0.73:
            keys.append(4)                            # ^D: down a level
            depth += 1
        elif p < 0.76 and depth > 1:
            keys.append(1)                            # ^A: up a level
            depth -= 1
        elif p < 0.80:
            keys.append(rng.choice([6, 20, 5, 24, 3]))  # ^F map, ^T teleport, ^E food, ^X see, ^C pass
        elif p < 0.82:
            keys.append(9)                            # ^I: level 10, sword, plate mail
        elif p < 0.85:
            keys += [23, o(rng.choice("abcdefghij"))]  # ^W whatis
        elif p < 0.88:
            keys += [o("*"), o(rng.choice("!?/=)]:,*")), 32, 27]   # pr_list
        elif p < 0.90:
            keys += [o(rng.choice("$|"))]
        elif p < 0.92:
            keys += [o("+")]                          # leave wizard mode...
            keys += [o("+"), o("x"), 13]              # ...and come back
        else:
            keys += [o("D"), 32, 27]                  # discoveries
    return keys[:n]


def write_keys(path, keys, case):
    hdr = f"# difftest: seed={case['seed']}"
    if case.get("opts") is not None:
        hdr += f" opts={case['opts']}"
    if case.get("master"):
        hdr += " master=1"
    if case.get("fixes"):
        hdr += " fixes=1"
    if case.get("args"):
        hdr += " arg=" + "\x1f".join(case["args"])
    with open(path, "w") as f:
        f.write(hdr + "\n")
        for i in range(0, len(keys), 20):
            f.write(" ".join(map(str, keys[i:i + 20])) + "\n")


def _parse_opts(text, case):
    for tok in text.strip().split(" "):
        if "=" in tok:
            k, v = tok.split("=", 1)
            if k == "seed":
                case["seed"] = int(v)
            elif k == "opts":
                case["opts"] = v
            elif k == "master":
                case["master"] = v == "1"
            elif k == "fixes":
                case["fixes"] = v == "1"
            elif k == "arg":
                case["args"] = v.split("\x1f")


def read_case(path):
    """A key file. A file with "# run: ..." sections is a chain: each section is
    one run (its options override the header's), all in the same directory."""
    path = os.path.abspath(path)
    case = {"keys": path, "seed": 1}
    lines = open(path).read().splitlines()
    if lines and lines[0].startswith("# difftest:"):
        _parse_opts(lines[0][len("# difftest:"):], case)
    for l in lines:
        for mode in ("classic", "fixed"):
            for pos, pre in ((True, f"# expect-{mode}:"), (False, f"# expect-not-{mode}:")):
                if l.startswith(pre):
                    case.setdefault("expect", []).append((mode, pos, l[len(pre):].strip()))
    if not any(l.startswith("# run:") for l in lines):
        return case
    os.makedirs(OUT, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="chain", dir=OUT)
    chain = []
    for l in lines:
        if l.startswith("# run:"):
            sub = {k: v for k, v in case.items() if k != "keys"}
            sub["args"] = []
            _parse_opts(l[len("# run:"):], sub)
            sub["keys"] = os.path.join(tmp, f"run{len(chain)}.keys")
            open(sub["keys"], "w").close()
            chain.append(sub)
        elif chain:
            with open(chain[-1]["keys"], "a") as f:
                f.write(l + "\n")
    case["chain"] = chain
    return case


def write_chain(path, case, runs):
    """Write a chain file: runs is a list of (args, keys)."""
    hdr = f"# difftest: seed={case['seed']}"
    if case.get("opts") is not None:
        hdr += f" opts={case['opts']}"
    if case.get("master"):
        hdr += " master=1"
    if case.get("fixes"):
        hdr += " fixes=1"
    with open(path, "w") as f:
        f.write(hdr + "\n")
        for args, keys in runs:
            # no args: no arg= token ("arg=" alone is one empty argument)
            f.write("# run:" + (" arg=" + "\x1f".join(args) if args else "") + "\n")
            for i in range(0, len(keys), 20):
                f.write(" ".join(map(str, keys[i:i + 20])) + "\n")


# ------------------------------------------------------------------ driver

SMOKE_ERRORS = ("SCRIPT ERROR", "TIMEOUT", "Assertion failed", "two coroutines waiting")


def random_loadout(rng, path):
    """A random Guild loadout (godot/guild/loadout.gd's schema), written to path."""
    import json
    lo = {"maxpack": rng.choice([23, 23, 26, 30, 40, 52]), "str": rng.randint(0, 4),
          "hp": rng.choice([0, 2, 4, 8]), "arrows": rng.choice([0, 10, 30]),
          "food": rng.randint(0, 3),
          "weapon": {"which": rng.choice([0, 1, 4, 5, 8]), "enh": rng.randint(0, 3)},
          "armor": {"which": rng.randrange(8), "enh": rng.randint(0, 3)},
          "bow": {"enh": rng.randint(0, 2)},
          "weapons": [{"which": rng.choice([0, 1, 5, 8]), "enh": rng.randint(0, 2)}
                      for _ in range(rng.randint(0, 2))],
          "armors": [{"which": rng.randrange(8), "enh": rng.randint(0, 2)} for _ in range(rng.randint(0, 1))],
          "missiles": [{"which": rng.choice([4, 6, 7]), "count": rng.randint(2, 20)}
                       for _ in range(rng.randint(0, 2))],
          "rings": [{"which": rng.randrange(14), "enh": rng.randint(0, 3)} for _ in range(rng.randint(0, 3))],
          "sticks": [{"which": rng.randrange(14), "enh": rng.randint(0, 2)} for _ in range(rng.randint(0, 3))],
          "potions": [{"which": rng.randrange(14), "count": rng.randint(1, 3)} for _ in range(rng.randint(0, 4))],
          "scrolls": [{"which": rng.randrange(18), "count": rng.randint(1, 3)} for _ in range(rng.randint(0, 4))],
          "know_potions": rng.sample(range(14), rng.randint(0, 5)),
          "know_scrolls": rng.sample(range(18), rng.randint(0, 5))}
    with open(path, "w") as f:
        json.dump(lo, f)
    return path


def with_menu_keys(rng, keys):
    """For smoke runs with the item menus on: after each item command, a few keys a
    menu reads (*, space, Escape, pack letters), so every menu path is exercised."""
    o = ord
    out = []
    for k in keys:
        out.append(k)
        if 0 < k < 128 and chr(k) in "qrewWPdctz" and rng.random() < 0.6:
            for _ in range(rng.randint(1, 3)):
                out.append(rng.choice([o("*"), o("*"), 32, 27, o(rng.choice("abcdefghijklmnopqrstuvwxyzAB"))]))
    return out[:len(keys)]


def run_smoke(cases, jobs, keep, batch_size=40):
    """The port alone: every run must end (its log ends with END or EXIT) and no batch
    may report a script error, a failed assertion or a timeout."""
    os.makedirs(OUT, exist_ok=True)
    work = tempfile.mkdtemp(prefix="smoke", dir=OUT)
    dirs = [os.path.join(work, f"run{i:05d}") for i in range(len(cases))]
    for d in dirs:
        os.makedirs(d)
    batches = [list(range(i, min(i + batch_size, len(cases)))) for i in range(0, len(cases), batch_size)]
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        errs = list(ex.map(lambda b: (b, run_port_batch(
            [ln for i in b for ln in port_lines(cases[i], os.path.join(dirs[i], "port"))], work)), batches))
    bad = 0
    for b, err in errs:
        lines = [l for l in port_errors(err, limit=40) if any(e in l for e in SMOKE_ERRORS)]
        if lines:
            bad += 1
            print(f"SMOKE: errors in the batch of runs {b[0]}..{b[-1]} ({err}):\n    " + "\n    ".join(lines[:12]))
    for c, d in zip(cases, dirs):
        for k in range(len(runs_of(c))):
            log = parse_log(os.path.join(d, "port", f"dump{tag(c, k)}.txt"))
            if not log or not log[-1].startswith(("END", "EXIT")):
                bad += 1
                print(f"SMOKE: run did not end: keys={c['keys']} last log line: {log[-1] if log else None}")
                break
    print(f"smoke: {len(cases)} runs, {bad} problem(s)  ({work})")
    if not keep and bad == 0:
        shutil.rmtree(work, ignore_errors=True)
    return bad


def _expects(case):
    return any(m == expect_mode(case) for m, _, _ in case.get("expect", []))


def set_fixes(case, on):
    """Turn the fixes on for a case and every run of its chain."""
    if on:
        case["fixes"] = True
        for sub in case.get("chain") or []:
            sub["fixes"] = True
    return case


def run_cases(cases, jobs, keep, batch_size=40):
    os.makedirs(OUT, exist_ok=True)
    work = tempfile.mkdtemp(prefix="difftest", dir=OUT)
    dirs = []
    for i, c in enumerate(cases):
        d = os.path.join(work, f"run{i:05d}")
        os.makedirs(d)
        dirs.append(d)
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        list(ex.map(lambda cd: run_oracle_all(cd[0], os.path.join(cd[1], "oracle")), zip(cases, dirs)))
        batches = [list(range(i, min(i + batch_size, len(cases)))) for i in range(0, len(cases), batch_size)]
        list(ex.map(lambda b: run_port_batch(
            [ln for i in b for ln in port_lines(cases[i], os.path.join(dirs[i], "port"),
                                                full=1 if _expects(cases[i]) else None)], work), batches))
    bad = unexpected = 0
    for c, d in zip(cases, dirs):
        r = compare(c, d)
        if r is not None:
            bad += 1
            print(report(c, d, *r), flush=True)
            continue
        e = check_expect(c, d)
        if e:
            unexpected += 1
            print(f"EXPECTATION FAILED keys={c['keys']} mode={expect_mode(c)}\n" + "\n".join(e), flush=True)
    print(f"difftest: {len(cases) - bad}/{len(cases)} runs identical"
          + (f", {unexpected} with failed expectations" if unexpected else "") + f"  ({work})")
    bad += unexpected
    if not keep and bad == 0:
        shutil.rmtree(work, ignore_errors=True)
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["one", "fuzz", "corpus", "seeds", "saves", "smoke"])
    ap.add_argument("dir", nargs="?")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--keys")
    ap.add_argument("--opts")
    ap.add_argument("--no-opts", action="store_true")
    ap.add_argument("--master", action="store_true")
    ap.add_argument("--fixes", action="store_true",
                    help="RogueBase.fixes on, against the fixed oracle (harness/oracle/fixes.patch)")
    ap.add_argument("--guild", action="store_true", help="smoke only: the Fighters' Guild on")
    ap.add_argument("--menus", action="store_true", help="smoke only: the item menus on")
    ap.add_argument("--arg", action="append", default=[])
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--len", type=int, default=600)
    ap.add_argument("--first-seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--save-failures", help="copy failing key scripts here")
    ap.add_argument("--wizard", action="store_true",
                    help="fuzz in wizard mode: MASTER oracle, args [\"\"], wizard commands")
    a = ap.parse_args()
    opts = None if a.no_opts else a.opts
    if (a.guild or a.menus) and a.mode != "smoke":
        sys.exit("--guild and --menus change the game in ways the oracle cannot judge: use them with smoke")
    if a.mode == "smoke":
        os.makedirs(OUT, exist_ok=True)
        kdir = tempfile.mkdtemp(prefix="keys", dir=OUT)
        cases = []
        for i in range(a.count):
            seed = a.first_seed + i
            rng = random.Random(seed * 7901)
            if a.wizard:
                case = {"seed": seed, "opts": opts, "master": True, "args": [""]}
                keys = gen_keys_wizard(rng, a.len)
            else:
                case = {"seed": seed, "opts": opts, "master": a.master, "args": a.arg}
                keys = gen_keys(rng, a.len)
            set_fixes(case, a.fixes)
            case["guild"], case["menus"] = a.guild, a.menus
            if a.menus:
                keys = with_menu_keys(rng, keys)
            if a.guild:
                case["loadout"] = random_loadout(rng, os.path.join(kdir, f"loadout{seed}.json"))
            path = os.path.join(kdir, f"smoke{seed}.keys")
            write_keys(path, keys, case)
            case["keys"] = path
            cases.append(case)
        sys.exit(1 if run_smoke(cases, a.jobs, a.keep) else 0)
    if a.mode == "one":
        case = read_case(a.keys) if not a.seed else {"keys": os.path.abspath(a.keys), "seed": a.seed}
        case.update({"opts": opts, "master": a.master, "args": a.arg})
        set_fixes(case, a.fixes)
        sys.exit(1 if run_cases([case], 1, a.keep) else 0)
    if a.mode == "fuzz":
        os.makedirs(OUT, exist_ok=True)
        kdir = tempfile.mkdtemp(prefix="keys", dir=OUT)
        cases = []
        for i in range(a.count):
            seed = a.first_seed + i
            rng = random.Random(seed * 7919)
            if a.wizard:
                case = {"seed": seed, "opts": opts, "master": True, "args": [""]}
                keys = gen_keys_wizard(rng, a.len)
            else:
                case = {"seed": seed, "opts": opts, "master": a.master, "args": a.arg}
                keys = gen_keys(rng, a.len)
            set_fixes(case, a.fixes)
            path = os.path.join(kdir, f"fuzz{seed}.keys")
            write_keys(path, keys, case)
            case["keys"] = path
            cases.append(case)
        bad = run_cases(cases, a.jobs, a.keep)
        sys.exit(1 if bad else 0)
    if a.mode == "seeds":
        # level generation: the first screen (and one ESC) for many seeds
        os.makedirs(OUT, exist_ok=True)
        kdir = tempfile.mkdtemp(prefix="keys", dir=OUT)
        cases = []
        for i in range(a.count):
            seed = a.first_seed + i
            case = set_fixes({"seed": seed, "opts": opts, "master": a.master, "args": a.arg}, a.fixes)
            path = os.path.join(kdir, f"seed{seed}.keys")
            write_keys(path, [27], case)
            case["keys"] = path
            cases.append(case)
        sys.exit(1 if run_cases(cases, a.jobs, a.keep, batch_size=100) else 0)
    if a.mode == "saves":
        # save/restore chains: play, save; restore (-r), play, save; restore, play
        os.makedirs(OUT, exist_ok=True)
        kdir = tempfile.mkdtemp(prefix="keys", dir=OUT)
        cases = []
        for i in range(a.count):
            seed = a.first_seed + i
            rng = random.Random(seed * 7907)
            # leave any prompt, then save (a second y overwrites a save file
            # that a wizard-mode restore did not delete)
            save = [32, 27, 32, 27, 27, ord("S"), ord("y"), ord("y")]
            if a.wizard:
                # wizard mode: quaff one kind of potion first (each one starts
                # a different daemon or fuse), go deeper and let monsters close
                # in (some chase objects or gold), then save
                case = set_fixes({"seed": seed, "opts": opts, "master": True}, a.fixes)
                o = ord
                potion = i % 14
                first = ([o("C"), o("!"), o("0123456789abcd"[potion]), 32, 32, o("q"), o("f"), 32, 32]
                         + [4] * rng.randint(0, 12) + [o("s")] * rng.randint(0, 30))
                runs = [([""], first + gen_keys_wizard(rng, rng.randint(10, a.len)) + save),
                        (["-r"], [o("s")] * rng.randint(0, 20) + gen_keys_wizard(rng, rng.randint(10, a.len)) + save),
                        (["-r"], gen_keys_wizard(rng, rng.randint(10, a.len)))]
            else:
                case = set_fixes({"seed": seed, "opts": opts, "master": a.master}, a.fixes)
                runs = [(a.arg, gen_keys(rng, rng.randint(20, a.len)) + save),
                        (["-r"], gen_keys(rng, rng.randint(20, a.len)) + save),
                        (["-r"], gen_keys(rng, rng.randint(20, a.len)))]
            path = os.path.join(kdir, f"save{seed}.keys")
            write_chain(path, case, runs)
            cases.append(read_case(path))
        sys.exit(1 if run_cases(cases, a.jobs, a.keep, batch_size=30) else 0)
    if a.mode == "corpus":
        d = a.dir or os.path.join(HERE, "corpus")
        cases = [set_fixes(read_case(os.path.join(dp, f)), a.fixes) for dp, _, fs in sorted(os.walk(d))
                 for f in sorted(fs) if f.endswith(".keys")]
        sys.exit(1 if run_cases(cases, a.jobs, a.keep) else 0)


if __name__ == "__main__":
    main()
