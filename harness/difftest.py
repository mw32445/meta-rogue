#!/usr/bin/env python3
"""Differential test: the C oracle vs the Godot port on identical inputs.

Both programs get the same seed, pinned environment and key script, and write a
step log (harness/DUMP_FORMAT.md). The first differing step is the divergence;
the report re-runs both with full screens around it.

  difftest.py one --seed N --keys FILE [common options]
  difftest.py fuzz --count N [--len L] [--first-seed S] [--jobs J] [common options]
  difftest.py corpus [DIR]          replay every *.keys file (seed/options in its header)
  difftest.py seeds --count N [--first-seed S]   first screen of many seeds (level generation)

common options: --opts ROGUEOPTS | --no-opts, --master, --arg A, --keep, --variant V

Key files: decimal key codes separated by whitespace; '#' starts a comment. A
header line "# difftest: seed=N opts=... master=1 arg=..." stores the run options.
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


def oracle_bin(master, variant=None):
    v = variant or ("master" if master else "std")
    p = os.path.join(HERE, "oracle", "build", v, "rogue-oracle")
    if not os.path.exists(p):
        subprocess.run([os.path.join(HERE, "oracle", "build.sh"), v], check=True, stdout=subprocess.DEVNULL)
    return p


# ------------------------------------------------------------------ running

def run_oracle(case, d, full=None):
    os.makedirs(d, exist_ok=True)
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "TERM": "xterm", "LINES": "24",
           "COLUMNS": "80", "TZ": "UTC", "ROGUE_SEED": str(case["seed"]), "ROGUE_TIME": str(TIME),
           "ROGUE_NAME": NAME, "ROGUE_HOME": HOME, "ROGUE_UID": str(UID),
           "ROGUE_KEYS": case["keys"], "ROGUE_DUMP": os.path.join(d, "dump.txt")}
    if case.get("opts") is not None:
        env["ROGUEOPTS"] = case["opts"]
    if full is not None:
        env["ROGUE_FULL"] = str(full)
    argv = [oracle_bin(case.get("master"), case.get("variant"))] + case.get("args", [])
    with open(os.path.join(d, "stdout.bin"), "wb") as so:
        try:
            subprocess.run(argv, cwd=d, env=env, stdout=so, stderr=subprocess.DEVNULL, timeout=60)
        except subprocess.TimeoutExpired:
            open(os.path.join(d, "dump.txt"), "a").write("TIMEOUT\n")


def port_line(case, d, full=None):
    os.makedirs(d, exist_ok=True)
    kv = {"seed": case["seed"], "time": TIME, "name": NAME, "home": HOME, "uid": UID,
          "keys": case["keys"], "dump": os.path.join(d, "dump.txt"),
          "stdout": os.path.join(d, "stdout.bin"), "cwd": d}
    if case.get("opts") is not None:
        kv["opts"] = case["opts"]
    if case.get("master"):
        kv["master"] = "1"
    if case.get("args"):
        kv["arg"] = "\x1f".join(case["args"])
    if full is not None:
        kv["full"] = full
    return "\t".join(f"{k}={v}" for k, v in kv.items())


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


def compare(d):
    o = parse_log(os.path.join(d, "oracle", "dump.txt"))
    p = parse_log(os.path.join(d, "port", "dump.txt"))
    for i, (a, b) in enumerate(zip(o, p)):
        if not step_equal(a, b):
            return i, a, b
    if len(o) != len(p):
        i = min(len(o), len(p))
        return i, (o[i] if i < len(o) else "<end of log>"), (p[i] if i < len(p) else "<end of log>")
    so = open(os.path.join(d, "oracle", "stdout.bin"), "rb").read() if os.path.exists(os.path.join(d, "oracle", "stdout.bin")) else b""
    sp = open(os.path.join(d, "port", "stdout.bin"), "rb").read() if os.path.exists(os.path.join(d, "port", "stdout.bin")) else b""
    if so != sp:
        return -1, repr(so[-200:]), repr(sp[-200:])
    return None


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


def report(case, d, idx, a, b):
    out = [f"DIVERGENCE seed={case['seed']} keys={case['keys']} opts={case.get('opts')!r} "
           f"master={bool(case.get('master'))} args={case.get('args', [])}"]
    if idx == -1:
        out.append(f"  stdout differs\n    oracle: ...{a}\n    port:   ...{b}")
        return "\n".join(out)
    out.append(f"  log line {idx + 1}:\n    oracle: {a}\n    port:   {b}")
    step = int(a[1:].split()[0]) if a.startswith("S") else int(b[1:].split()[0]) if b.startswith("S") else None
    if step is None:
        return "\n".join(out)
    first = max(1, step - 1)
    run_oracle(case, os.path.join(d, "oracle_full"), full=first)
    err = run_port_batch([port_line(case, os.path.join(d, "port_full"), full=first)], d)
    errs = port_errors(err)
    if errs:
        out.append("  port errors:\n    " + "\n    ".join(errs))
    ro, eo, go = full_dump(os.path.join(d, "oracle_full", "dump.txt"), step)
    rp, ep, gp = full_dump(os.path.join(d, "port_full", "dump.txt"), step)
    keys = [int(t) for t in " ".join(l.split("#")[0] for l in open(case["keys"]).read().splitlines()).split()]
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


def write_keys(path, keys, case):
    hdr = f"# difftest: seed={case['seed']}"
    if case.get("opts") is not None:
        hdr += f" opts={case['opts']}"
    if case.get("master"):
        hdr += " master=1"
    if case.get("args"):
        hdr += " arg=" + "\x1f".join(case["args"])
    with open(path, "w") as f:
        f.write(hdr + "\n")
        for i in range(0, len(keys), 20):
            f.write(" ".join(map(str, keys[i:i + 20])) + "\n")


def read_case(path):
    case = {"keys": path, "seed": 1}
    first = open(path).readline()
    if first.startswith("# difftest:"):
        for tok in first[len("# difftest:"):].strip().split(" "):
            if "=" in tok:
                k, v = tok.split("=", 1)
                if k == "seed":
                    case["seed"] = int(v)
                elif k == "opts":
                    case["opts"] = v
                elif k == "master":
                    case["master"] = v == "1"
                elif k == "arg":
                    case["args"] = v.split("\x1f")
    return case


# ------------------------------------------------------------------ driver

def run_cases(cases, jobs, keep, batch_size=40):
    os.makedirs(OUT, exist_ok=True)
    work = tempfile.mkdtemp(prefix="difftest", dir=OUT)
    dirs = []
    for i, c in enumerate(cases):
        d = os.path.join(work, f"run{i:05d}")
        os.makedirs(d)
        dirs.append(d)
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        list(ex.map(lambda cd: run_oracle(cd[0], os.path.join(cd[1], "oracle")), zip(cases, dirs)))
        batches = [list(range(i, min(i + batch_size, len(cases)))) for i in range(0, len(cases), batch_size)]
        list(ex.map(lambda b: run_port_batch([port_line(cases[i], os.path.join(dirs[i], "port")) for i in b], work), batches))
    bad = 0
    for c, d in zip(cases, dirs):
        r = compare(d)
        if r is not None:
            bad += 1
            print(report(c, d, *r), flush=True)
    print(f"difftest: {len(cases) - bad}/{len(cases)} runs identical  ({work})")
    if not keep and bad == 0:
        shutil.rmtree(work, ignore_errors=True)
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["one", "fuzz", "corpus", "seeds"])
    ap.add_argument("dir", nargs="?")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--keys")
    ap.add_argument("--opts")
    ap.add_argument("--no-opts", action="store_true")
    ap.add_argument("--master", action="store_true")
    ap.add_argument("--arg", action="append", default=[])
    ap.add_argument("--count", type=int, default=100)
    ap.add_argument("--len", type=int, default=600)
    ap.add_argument("--first-seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--save-failures", help="copy failing key scripts here")
    a = ap.parse_args()
    opts = None if a.no_opts else a.opts
    if a.mode == "one":
        case = read_case(a.keys) if not a.seed else {"keys": os.path.abspath(a.keys), "seed": a.seed}
        case.update({"opts": opts, "master": a.master, "args": a.arg})
        sys.exit(1 if run_cases([case], 1, a.keep) else 0)
    if a.mode == "fuzz":
        os.makedirs(OUT, exist_ok=True)
        kdir = tempfile.mkdtemp(prefix="keys", dir=OUT)
        cases = []
        for i in range(a.count):
            seed = a.first_seed + i
            rng = random.Random(seed * 7919)
            case = {"seed": seed, "opts": opts, "master": a.master, "args": a.arg}
            path = os.path.join(kdir, f"fuzz{seed}.keys")
            write_keys(path, gen_keys(rng, a.len), case)
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
            case = {"seed": seed, "opts": opts, "master": a.master, "args": a.arg}
            path = os.path.join(kdir, f"seed{seed}.keys")
            write_keys(path, [27], case)
            case["keys"] = path
            cases.append(case)
        sys.exit(1 if run_cases(cases, a.jobs, a.keep, batch_size=100) else 0)
    if a.mode == "corpus":
        d = a.dir or os.path.join(HERE, "corpus")
        cases = [read_case(os.path.join(d, f)) for f in sorted(os.listdir(d)) if f.endswith(".keys")]
        sys.exit(1 if run_cases(cases, a.jobs, a.keep) else 0)


if __name__ == "__main__":
    main()
