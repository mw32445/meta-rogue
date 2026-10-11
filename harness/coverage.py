#!/usr/bin/env python3
"""gcov line coverage of the original C code by key scripts.

Runs key scripts (difftest's *.keys files, options in their headers) on the
gcov-instrumented oracle only, then reports per-file line coverage. This shows
which parts of the original game the differential tests have exercised.

  coverage.py [--master] [--reset] [--annotate FILE.c] PATH...

PATH: key files or directories of them. --master uses the wizard-mode build
(covmaster) for every run; otherwise runs whose header says master=1 go to
covmaster and the rest to cov. --reset clears earlier counts first.
--annotate writes FILE.c.gcov listings (unexecuted lines are marked #####)
into harness/out/coverage/. --uncovered FILE prints the lines of FILE.c that
neither build ran (without PATH, it reports the counts gathered so far).
"""
import argparse
import concurrent.futures as cf
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import difftest  # noqa: E402

# The game logic. mdport.c (portability), xcrypt.c (DES) and vers.c are not.
GAME = ["armor", "chase", "command", "daemon", "daemons", "extern", "fight", "init", "io",
        "list", "main", "mach_dep", "misc", "monsters", "move", "new_level", "options", "pack",
        "passages", "potions", "rings", "rip", "rooms", "save", "scrolls", "state", "sticks",
        "things", "weapons", "wizard"]


def builddir(v):
    return os.path.join(HERE, "oracle", "build", v)


def gcov_lines(v, name, src=None):
    """(executable line numbers, executed line numbers) of one file in one build;
    src, if given, collects {line number: source text}."""
    d = builddir(v)
    if not os.path.exists(os.path.join(d, name + ".gcda")):
        return None
    r = subprocess.run(["gcov", "-t", "-o", d, name + ".c"], cwd=d, capture_output=True, text=True)
    exe, ran = set(), set()
    for line in r.stdout.splitlines():
        parts = line.split(":", 2)
        if len(parts) < 3:
            continue
        cnt, num = parts[0].strip(), parts[1].strip()
        if not num.isdigit() or cnt == "-":
            continue
        n = int(num)
        if n == 0:
            continue
        if src is not None:
            src[n] = parts[2]
        exe.add(n)
        if cnt not in ("#####", "====="):
            ran.add(n)
    return exe, ran


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--master", action="store_true")
    ap.add_argument("--reset", action="store_true")
    ap.add_argument("--annotate", action="append", default=[])
    ap.add_argument("--uncovered", action="append", default=[])
    ap.add_argument("--jobs", type=int, default=4)
    a = ap.parse_args()
    for v in ("cov", "covmaster"):
        if not os.path.exists(os.path.join(builddir(v), "rogue-oracle")):
            subprocess.run([os.path.join(HERE, "oracle", "build.sh"), v], check=True,
                           stdout=subprocess.DEVNULL)
        if a.reset:
            for f in glob.glob(os.path.join(builddir(v), "*.gcda")):
                os.remove(f)
    files = []
    for p in a.paths:
        if os.path.isdir(p):
            files += sorted(os.path.join(dp, f) for dp, _, fs in os.walk(p) for f in fs if f.endswith(".keys"))
        else:
            files.append(p)
    cases = [difftest.read_case(os.path.abspath(f)) for f in files]
    for c in cases:
        for sub in difftest.runs_of(c):
            sub["variant"] = "covmaster" if (a.master or sub.get("master")) else "cov"
    work = tempfile.mkdtemp(prefix="cov", dir=os.path.join(HERE, "out")) if cases else None
    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        list(ex.map(lambda ic: difftest.run_oracle_all(ic[1], os.path.join(work, f"r{ic[0]}")),
                    enumerate(cases)))
    if work:
        shutil.rmtree(work, ignore_errors=True)

    # merge the two builds line by line: a line is covered if either build ran it
    print(f"{'file':12s} {'lines':>7s} {'covered':>8s}   (std / master runs)")
    te = tt = 0
    for n in GAME:
        exe, ran = set(), set()
        for v in ("cov", "covmaster"):
            r = gcov_lines(v, n)
            if r:
                exe |= r[0]
                ran |= r[1]
        if not exe:
            continue
        te += len(ran)
        tt += len(exe)
        print(f"{n:12s} {len(exe):7d} {100 * len(ran) / len(exe):7.1f}%")
    print(f"game logic: {te}/{tt} lines = {100 * te / max(1, tt):.1f}%")
    for f in a.uncovered:
        name = f[:-2] if f.endswith(".c") else f
        exe, ran, src = set(), set(), {}
        for v in ("cov", "covmaster"):
            r = gcov_lines(v, name, src)
            if r:
                exe |= r[0]
                ran |= r[1]
        miss = sorted(exe - ran)
        print(f"===== {name}.c: {len(miss)} of {len(exe)} lines not run")
        prev = None
        for n in miss:
            if prev is not None and n != prev + 1:
                print("   ...")
            print(f"{n:5d}: {src.get(n, '').rstrip()}")
            prev = n
    if a.annotate:
        outd = os.path.join(HERE, "out", "coverage")
        os.makedirs(outd, exist_ok=True)
        for f in a.annotate:
            for v in ("cov", "covmaster"):
                d = builddir(v)
                subprocess.run(["gcov", "-o", d, f], cwd=d, capture_output=True)
                g = os.path.join(d, f + ".gcov")
                if os.path.exists(g):
                    shutil.copy(g, os.path.join(outd, f"{v}-{f}.gcov"))
        print(f"annotated listings in {outd}")


if __name__ == "__main__":
    main()
