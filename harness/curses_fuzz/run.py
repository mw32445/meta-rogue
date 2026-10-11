#!/usr/bin/env python3
"""Curses differential fuzzer: random op scripts on real ncurses (cfuzz.c) vs the
GDScript emulation (godot/tests/curses_fuzz.gd). Reports the first mismatch.

usage: run.py [--count N] [--ops N] [--seed S] [--godot PATH]
"""
import argparse
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))


def build_cfuzz(out):
    subprocess.run(["gcc", "-O1", "-w", "-o", out, os.path.join(HERE, "cfuzz.c"), "-lncurses"], check=True)


def same(a, b):
    """Compare outputs; a '?' cursor on the emulation side matches anything."""
    if a == b:
        return True
    ta, tb = a.split(" ", 2), b.split(" ", 2)
    if len(ta) >= 2 and len(tb) >= 2 and ta[0] == tb[0] and ta[0] in ("=curscr", "=win") and "?" in (ta[1], tb[1]):
        return ta[2:] == tb[2:]
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=200)
    ap.add_argument("--ops", type=int, default=300)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix="cfuzz")
    cf = os.path.join(tmp, "cfuzz")
    build_cfuzz(cf)
    env = dict(os.environ, TERM="xterm", LINES="24", COLUMNS="80")
    pairs = []
    for i in range(a.count):
        seed = a.seed + i
        ops = os.path.join(tmp, f"ops{seed}.txt")
        with open(ops, "w") as f:
            subprocess.run([sys.executable, os.path.join(HERE, "gen.py"), str(seed), str(a.ops)], stdout=f, check=True)
        with open(os.path.join(tmp, f"c{seed}.txt"), "w") as f:
            subprocess.run([cf, ops], stdout=f, env=env, check=True)
        pairs += [ops, os.path.join(tmp, f"g{seed}.txt")]
    subprocess.run([a.godot, "--headless", "--path", os.path.join(ROOT, "godot"),
                    "--script", "res://tests/curses_fuzz.gd", "--"] + pairs, check=True,
                   stdout=subprocess.DEVNULL)
    bad = 0
    for i in range(a.count):
        seed = a.seed + i
        c = open(os.path.join(tmp, f"c{seed}.txt")).read().split("\n")
        g = open(os.path.join(tmp, f"g{seed}.txt")).read().split("\n")
        for n, (x, y) in enumerate(zip(c, g)):
            if not same(x, y):
                bad += 1
                op = next((c[k] for k in range(n, -1, -1) if not c[k].startswith(("=", " "))), "?")
                print(f"seed {seed}: mismatch at output line {n + 1} after op `{op}`\n  ncurses: {x[:300]}\n  godot:   {y[:300]}")
                break
        else:
            if len(c) != len(g):
                bad += 1
                print(f"seed {seed}: output length differs ({len(c)} vs {len(g)})")
    print(f"{a.count - bad}/{a.count} scripts identical ({tmp})")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
