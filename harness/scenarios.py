#!/usr/bin/env python3
"""Curated end-of-game scenarios for the regression corpus.

  scenarios.py [--out DIR] [--seeds N]      (default DIR: harness/corpus/scenarios)

Writes key scripts (difftest format) that the random fuzzers rarely reach:
  win-<seed>.keys          wizard mode: create the Amulet and climb out (total_winner)
  scores-<seed>.keys       chains: three games that end in death fill the score file,
                           then `rogue -s` prints it
  notomb-<seed>.keys       a death with ROGUEOPTS=notombstone
  deathdemo-<seed>.keys    `rogue -d`: a random death screen
  rings-<seed>.keys        wizard mode: rings on both hands, a third, the hand prompt,
                           a cursed ring, identify ([+N]); also with ROGUEOPTS=terse
  scoreedit-<seed>.keys    chains: deaths fill the score file, then a wizard quits and
                           types "names" or "edit" (deleting entries), then `rogue -s`
  fullpack-<seed>.keys     wizard mode: fill the pack (23 kinds), then one more
  emptypack-<seed>.keys    drop everything, then inventory and item commands

The games are played by harness/bot.py on the oracle, so they are real games; they are
then fixed inputs for both programs.
"""
import argparse
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bot        # noqa: E402
import difftest   # noqa: E402


def keys_of(path):
    return [int(t) for t in " ".join(l.split("#")[0] for l in open(path).read().splitlines()).split()]


def ended_by_death(path, case):
    """Replay a recorded game on the oracle: did it end on the tombstone/score path?"""
    d = tempfile.mkdtemp(dir=difftest.OUT)
    difftest.run_oracle(case, d)
    out = open(os.path.join(d, "stdout.bin"), "rb").read()
    shutil.rmtree(d, ignore_errors=True)
    return b"[Press return to continue]" in out


def ring_keys():
    o = ord
    k = []
    k += [o("C"), o("="), o("0"), o("+"), 32]        # f: ring of protection, blessed
    k += [o("P"), o("f"), o("l"), 32]                # put it on: which hand? left
    k += [o("C"), o("="), o("6"), 32]                # g: aggravate monster (cursed)
    k += [o("P"), o("g"), 32]                        # right hand by itself; aggravate()
    k += [o("C"), o("="), o("3"), 32]                # h: searching
    k += [o("P"), o("h"), 32]                        # already a ring on each hand
    k += [o("R"), o("x"), 32, o("r"), 32]            # which hand? x: L or R; r: cursed
    k += [o("R"), o("l"), 32]                        # take off the left one
    k += [o("P"), o("h"), 32]                        # left hand by itself
    k += [o("C"), o("?"), o("9"), 32]                # i: identify ring, wand or staff
    k += [o("r"), o("i"), 32, o("f"), 32, 32]        # identify the protection ring
    k += [o("i"), 32, 32]                            # inventory: [+N]
    k += [o("s")] * 30 + [27]                        # wear them a while (ring_eat)
    return k


def fullpack_keys():
    o = ord
    k = []
    for w in "0123456789abcd":                       # 14 kinds of potion: f..s
        k += [o("C"), o("!"), o(w), 32]
    for w in "0123":                                 # 4 kinds of scroll: t..w (pack full)
        k += [o("C"), o("?"), o(w), 32]
    k += [o("C"), o("!"), o("0"), 32]                # a potion that stacks: still fits
    k += [o("C"), o("?"), o("5"), 32, 32]            # a new kind: no room in your pack
    k += [o("i"), 32, 32, o("s"), 27]
    return k


def emptypack_keys():
    o = ord
    k = []
    for c, mv in zip("abcde", "lllll"):              # drop each item on its own square
        k += [o("d"), o(c), 32, o(mv), 32]
    k += [o("i"), 32, o("q"), 32, o("w"), 32, o("t"), 32, o("P"), 32, o("r"), 32, 27]
    return k


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(HERE, "corpus", "scenarios"))
    ap.add_argument("--seeds", type=int, default=4)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    os.makedirs(difftest.OUT, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="scen", dir=difftest.OUT)

    # winning games
    n = 0
    seed = 100
    while n < a.seeds and seed < 200:
        p = os.path.join(tmp, f"w{seed}.keys")
        bot.play(seed, 3000, p, master=True, args=[""], goal="win")
        case = difftest.read_case(p)
        d = tempfile.mkdtemp(dir=difftest.OUT)
        difftest.run_oracle(case, d)
        won = b"[Press return to continue]" not in open(os.path.join(d, "stdout.bin"), "rb").read()
        shutil.rmtree(d, ignore_errors=True)
        if won:
            shutil.copy(p, os.path.join(a.out, f"win-{seed}.keys"))
            n += 1
        seed += 1

    # deaths (standard build), used for score chains and notombstone
    deaths = []
    seed = 300
    while len(deaths) < 3 * a.seeds and seed < 500:
        p = os.path.join(tmp, f"d{seed}.keys")
        bot.play(seed, 4000, p)
        if ended_by_death(p, difftest.read_case(p)):
            deaths.append((seed, keys_of(p)))
        seed += 1
    for i in range(a.seeds):
        group = deaths[3 * i:3 * i + 3]
        if len(group) < 3:
            break
        path = os.path.join(a.out, f"scores-{group[0][0]}.keys")
        with open(path, "w") as f:
            f.write(f"# difftest: seed={group[0][0]}\n")
            f.write("# three games ending in death share a score file, then rogue -s lists it\n")
            for s, keys in group:
                f.write(f"# run: seed={s}\n")
                for j in range(0, len(keys), 20):
                    f.write(" ".join(map(str, keys[j:j + 20])) + "\n")
            f.write(f"# run: seed={group[0][0]} arg=-s\n")

    # a death with notombstone
    n = 0
    seed = 600
    while n < a.seeds and seed < 700:
        p = os.path.join(tmp, f"n{seed}.keys")
        bot.play(seed, 4000, p, opts="notombstone")
        if ended_by_death(p, difftest.read_case(p)):
            shutil.copy(p, os.path.join(a.out, f"notomb-{seed}.keys"))
            n += 1
        seed += 1

    # score listing for the wizard: "names", or "edit" with deletions, then -s
    o = ord
    for i in range(a.seeds):
        group = deaths[3 * i:3 * i + 3]
        if len(group) < 3:
            break
        for mode in ("names", "edit"):
            path = os.path.join(a.out, f"scoreedit-{mode}-{group[0][0]}.keys")
            with open(path, "w") as f:
                f.write(f"# difftest: seed={group[0][0]}\n")
                f.write(f"# deaths fill the score file; a wizard quits and types {mode!r} at the prompt\n")
                for s_, keys in group:
                    f.write(f"# run: seed={s_}\n")
                    for j in range(0, len(keys), 20):
                        f.write(" ".join(map(str, keys[j:j + 20])) + "\n")
                quit_keys = [o("Q"), o("y")] + [o(c) for c in mode] + [13]
                if mode == "edit":
                    quit_keys += [o("d"), 13, 13, o("d"), 13, 13, 13]
                f.write(f"# run: seed={group[0][0] + 1000} master=1 arg=\n")
                f.write(" ".join(map(str, quit_keys)) + "\n")
                f.write(f"# run: seed={group[0][0]} arg=-s\n")

    # rings
    for seed in range(900, 900 + a.seeds):
        difftest.write_keys(os.path.join(a.out, f"rings-{seed}.keys"), ring_keys(),
                            {"seed": seed, "master": True, "args": [""]})
        difftest.write_keys(os.path.join(a.out, f"rings-terse-{seed}.keys"), ring_keys(),
                            {"seed": seed, "master": True, "args": [""], "opts": "terse"})

    # a full pack, and an empty one
    for seed in range(950, 950 + a.seeds):
        difftest.write_keys(os.path.join(a.out, f"fullpack-{seed}.keys"), fullpack_keys(),
                            {"seed": seed, "master": True, "args": [""]})
        difftest.write_keys(os.path.join(a.out, f"emptypack-{seed}.keys"), emptypack_keys(),
                            {"seed": seed})

    # rogue -d: a random death screen, then return twice
    for seed in range(800, 800 + a.seeds):
        difftest.write_keys(os.path.join(a.out, f"deathdemo-{seed}.keys"), [13, 13],
                            {"seed": seed, "args": ["-d"]})
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"scenarios written to {a.out}")


if __name__ == "__main__":
    main()
