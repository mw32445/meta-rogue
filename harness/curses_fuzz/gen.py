#!/usr/bin/env python3
"""Generate random curses op scripts for the differential fuzzer (see cfuzz.c).

Biased toward what Rogue does and where curses is subtle: edge coordinates,
wrapping, '\\n' '\\t' '\\b' '\\r' and control characters, standout, overlapping
windows refreshed in different orders, touchwin, subwin, leaveok, getch's
implicit refresh.

usage: gen.py SEED [NOPS] > ops.txt
"""
import random
import sys

LINES, COLS = 24, 80
A_STANDOUT = 0x10000


def text(r):
    n = r.choice([0, 1, 2, 3, 5, 8, 13, 20, 40, 71, 79, 80, 81, 100, 160])
    out = []
    for _ in range(n):
        p = r.random()
        if p < 0.68:
            out.append(chr(r.randint(33, 126)))
        elif p < 0.78:
            out.append(" ")
        elif p < 0.83:
            out.append("\n")
        elif p < 0.87:
            out.append("\t")
        elif p < 0.90:
            out.append("\b")
        elif p < 0.92:
            out.append("\r")
        elif p < 0.97:
            out.append(chr(r.choice([1, 2, 3, 7, 11, 12, 14, 20, 26, 27, 31])))
        else:
            out.append(chr(127))
    return "".join(out).encode("latin-1").hex()


def coord(r, size):
    return r.choice([0, 0, 1, size - 2, size - 1, size - 1, size, -1,
                     r.randrange(size), r.randrange(size), r.randrange(size)])


def chtype(r):
    p = r.random()
    if p < 0.02:
        return 0xFFFFFFFF          # CCHAR(ERR) redrawn: char 0xff with every attribute
    c = r.choice([r.randint(32, 126)] * 8 + [ord("\n"), ord("\t"), ord("\b"), ord("\r"),
                                             1, 7, 27, 31, 127, 32, 32])
    if r.random() < 0.15:
        c |= A_STANDOUT
    return c


def main():
    seed = int(sys.argv[1])
    nops = int(sys.argv[2]) if len(sys.argv) > 2 else 300
    r = random.Random(seed)
    wins = {0: (LINES, COLS)}          # id -> (lines, cols); 1 = curscr (refresh/clearok only)
    nextid = 2
    out = []
    for _ in range(nops):
        p = r.random()
        ids = list(wins)
        w = r.choice(ids)
        nl, nc = wins[w]
        if p < 0.05 and len(wins) < 6:
            kind = r.random()
            if kind < 0.5:                          # full-screen overlay, like hw
                out.append(f"newwin {nextid} {LINES} {COLS} 0 0")
                wins[nextid] = (LINES, COLS)
            else:                                   # INV_OVER box + subwin
                l = r.randint(1, LINES)
                c = r.randint(2, COLS)
                bx = COLS - c
                out.append(f"newwin {nextid} {l} {c} 0 {bx}")
                wins[nextid] = (l, c)
                if r.random() < 0.7 and c > 1:
                    nextid += 1
                    out.append(f"subwin {nextid} {nextid - 1} {l} {c - 1} 0 {bx + 1}")
                    wins[nextid] = (l, c - 1)
            nextid += 1
        elif p < 0.07 and w >= 2:
            out.append(f"delwin {w}")
            del wins[w]
        elif p < 0.22:
            out.append(f"wmove {w} {coord(r, nl)} {coord(r, nc)}")
        elif p < 0.40:
            out.append(f"waddch {w} {chtype(r)}")
        elif p < 0.55:
            out.append(f"waddstr {w} {text(r) or '41'}")
        elif p < 0.60:
            out.append(f"mvwaddch {w} {coord(r, nl)} {coord(r, nc)} {chtype(r)}")
        elif p < 0.66:
            out.append(f"mvwaddstr {w} {coord(r, nl)} {coord(r, nc)} {text(r) or '42'}")
        elif p < 0.70:
            out.append(f"wclrtoeol {w}")
        elif p < 0.715:
            out.append(f"werase {w}")
        elif p < 0.73:
            out.append(f"wclear {w}")
        elif p < 0.76:
            out.append(f"touchwin {w}")
        elif p < 0.83:
            out.append(f"wrefresh {r.choice(ids + [1]) if r.random() < 0.1 else w}")
        elif p < 0.85:
            out.append(f"clearok {r.choice([w, 1])} {r.randint(0, 1)}")
        elif p < 0.87:
            out.append(f"leaveok {w} {r.randint(0, 1)}")
        elif p < 0.90:
            out.append(r.choice([f"wstandout {w}", f"wstandend {w}"]))
        elif p < 0.92:
            out.append(f"winch {w}")
        elif p < 0.94:
            out.append(f"mvwinch {w} {coord(r, nl)} {coord(r, nc)}")
        elif p < 0.95:
            out.append(f"getyx {w}")
        elif p < 0.975:
            out.append(f"getch {w}")
        else:
            out.append("dump")
    out.append("wrefresh 0")
    out.append("dump")
    print("\n".join(out))


if __name__ == "__main__":
    main()
