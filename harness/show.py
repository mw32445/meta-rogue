#!/usr/bin/env python3
"""Show the screens of a key script around some step, from the oracle and/or the port.

  show.py KEYFILE --step N [--before 2] [--after 0] [--port] [--digest]

Uses the run options in the key file's header (seed, opts, master, args). For a
chain file, --run K picks the run (0-based); earlier runs are replayed first.
"""
import argparse
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import difftest  # noqa: E402


def blocks(path):
    """{step: (header, rows, digest)} from a full-mode dump."""
    out = {}
    lines = open(path).read().splitlines()
    i = 0
    while i < len(lines):
        l = lines[i]
        if l.startswith("S") and " K" in l:
            step = int(l[1:].split()[0])
            rows, dg = [], ""
            j = i + 1
            while j < len(lines) and not lines[j].startswith(("S", "END", "EXIT")):
                if lines[j].startswith("|"):
                    rows.append(lines[j])
                elif lines[j].startswith("G "):
                    dg = lines[j][2:]
                j += 1
            out[step] = (l, rows, dg)
            i = j
        else:
            i += 1
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keys")
    ap.add_argument("--step", type=int, required=True)
    ap.add_argument("--before", type=int, default=2)
    ap.add_argument("--after", type=int, default=0)
    ap.add_argument("--port", action="store_true", help="also run the port and show both")
    ap.add_argument("--digest", action="store_true")
    ap.add_argument("--run", type=int, default=0)
    a = ap.parse_args()
    case = difftest.read_case(os.path.abspath(a.keys))
    first = max(1, a.step - a.before)
    work = tempfile.mkdtemp(prefix="show", dir=difftest.OUT)
    t = difftest.tag(case, a.run)
    difftest.run_oracle_all(case, os.path.join(work, "oracle"), full=first, full_run=a.run)
    ob = blocks(os.path.join(work, "oracle", f"dump{t}.txt"))
    pb = {}
    if a.port:
        difftest.run_port_batch(difftest.port_lines(case, os.path.join(work, "port"), full=first,
                                                    full_run=a.run), work)
        pb = blocks(os.path.join(work, "port", f"dump{t}.txt"))
    for step in range(first, a.step + a.after + 1):
        o = ob.get(step)
        p = pb.get(step)
        print(f"--- step {step}")
        print("  oracle:", o[0] if o else "-")
        if a.port:
            print("  port:  ", p[0] if p else "-")
        rows_o = o[1] if o else []
        rows_p = p[1] if p else []
        for y in range(max(len(rows_o), len(rows_p))):
            r1 = rows_o[y] if y < len(rows_o) else ""
            if a.port:
                r2 = rows_p[y] if y < len(rows_p) else ""
                print(f"{'*' if r1 != r2 else ' '}{y:2d} {r1}  {r2}")
            elif r1.strip("| "):
                print(f" {y:2d} {r1}")
        if a.digest:
            print("  G oracle:", o[2] if o else "")
            if a.port:
                print("  G port:  ", p[2] if p else "")
    shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()
