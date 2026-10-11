#!/usr/bin/env python3
"""Explorer bot: plays the C oracle to record long, deep games for difftest.

The oracle runs in interactive mode (ROGUE_KEYS=-). At every keyboard read it
writes the full screen and the state digest (harness/DUMP_FORMAT.md) and waits
for a key on stdin; the bot reads the screen and answers. The recorded keys
are an ordinary difftest key script, replayed later on both programs:

  bot.py --seed N [--max-keys K] [--out FILE] [--opts ROGUEOPTS] [--master]
  bot.py --count N --first-seed S --out-dir DIR [--jobs J] ...

The bot explores each level (walks to unexplored doors and corridors, picks up
items, fights what it meets), uses items now and then (eats when hungry,
quaffs, reads, zaps, wears, wields, puts on rings, throws) and goes down the
stairs once a level is explored or it has spent long enough on it. It answers
every prompt it recognizes; anything else gets ESC or space.
"""
import argparse
import collections
import concurrent.futures as cf
import os
import random
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import difftest  # noqa: E402  (oracle paths, pinned environment, key files)

MOVES = {(-1, 0): "k", (1, 0): "j", (0, -1): "h", (0, 1): "l",
         (-1, -1): "y", (-1, 1): "u", (1, -1): "b", (1, 1): "n"}
WALK = set(".#+%!?/=*:])},")       # squares the bot may step on (not traps)
ITEMS = set("!?/=*:]),")
NOT_STEP = set(" |-")               # step_ok() is false for these (and letters)
DIGEST_PACK = re.compile(r"\[(\d+) (\d+) (\d+) c(-?\d+) f([0-9a-f]+) h(-?\d+) d(-?\d+) a(-?\d+) g(\d+)\]")
DIGEST_MON = re.compile(r"\[(\d+) (\d+),(\d+) f([0-9a-f]+) h(-?\d+) g(-?\d+) o(-?\d+) t(\S+) r(-?\d+)\]")


class Step:
    def __init__(self, head, rows, digest):
        self.head = head
        self.rows = rows            # 24 strings of 80 chars ([] when curses is gone)
        self.digest = digest
        f = digest.split()
        self.vals = {}
        for t in f[:12]:
            self.vals[t[0]] = int(t[1:])
        m = re.search(r" P(\d+),(\d+) ", digest)
        self.pos = (int(m.group(1)), int(m.group(2))) if m else (0, 0)
        m = re.search(r" h(-?\d+)/(\d+) ", digest)
        self.hp, self.maxhp = (int(m.group(1)), int(m.group(2))) if m else (1, 1)
        k = digest.split(" k:", 1)[1].split(" d:", 1)[0] if " k:" in digest else ""
        self.pack = [(chr(int(a)), int(b), int(c)) for a, b, c, *_ in DIGEST_PACK.findall(k)]
        m = digest.split(" m:", 1)[1].split(" o:", 1)[0] if " m:" in digest else ""
        self.monsters = [(int(y), int(x)) for _, y, x, *_ in DIGEST_MON.findall(m)]
        m = re.search(r" W(-?\d+) R(-?\d+) Q(-?\d+),(-?\d+)", digest)
        worn = {int(v) for v in m.groups()} if m else set()
        self.equipped = {self.pack[i][0] for i in worn if 0 <= i < len(self.pack)}

    def msg(self):
        return self.rows[0] if self.rows else ""

    def text(self):
        return "\n".join(self.rows)


def read_step(stream):
    """Read the next step block from the oracle; None at END/EXIT/EOF."""
    head = None
    while True:
        line = stream.readline()
        if not line:
            return None
        line = line.rstrip("\n")
        if line.startswith(("END", "EXIT")):
            return None
        if line.startswith("S"):
            head = line
            break
    rows = []
    digest = ""
    while True:
        line = stream.readline()
        if not line:
            return None
        line = line.rstrip("\n")
        if line.startswith("|"):
            rows.append(line[1:-1])
        elif line.startswith("G "):
            digest = line[2:]
            break
    return Step(head, rows, digest)


class Bot:
    def __init__(self, rng, master=False, goal="deep"):
        self.rng = rng
        self.master = master
        self.goal = goal            # "deep": go down; "win": take the Amulet up and out
        self.plan = collections.deque()   # keys still to send for the current action
        self.level = 0
        self.level_keys = 0
        self.stuck = 0
        self.last_pos = None
        self.searches = 0
        self.visited = collections.Counter()
        self.recent = collections.deque()

    # ---------------------------------------------------------------- helpers
    def item(self, st, otype, spare=False):
        """A pack letter holding an item of this type (an ord), or None.
        spare: not the wielded weapon, worn armor or a worn ring."""
        c = [p for p, t, _ in st.pack if t == otype and not (spare and p in st.equipped)]
        return self.rng.choice(c) if c else None

    def neighbors(self, rows, y, x):
        for (dy, dx) in MOVES:
            ny, nx = y + dy, x + dx
            if 1 <= ny <= 22 and 0 <= nx < 80:
                yield dy, dx, ny, nx

    def passable(self, rows, y, x):
        c = rows[y][x]
        return c in WALK or c == "@"

    def diag_ok(self, rows, y, x, dy, dx):
        if dy == 0 or dx == 0:
            return True
        a, b = rows[y + dy][x], rows[y][x + dx]
        return a not in NOT_STEP and not a.isalpha() and b not in NOT_STEP and not b.isalpha()

    def bfs(self, rows, start, goal):
        """First move toward the nearest square where goal(y, x) holds."""
        prev = {start: None}
        q = collections.deque([start])
        while q:
            y, x = q.popleft()
            if (y, x) != start and goal(y, x):
                while prev[(y, x)] != start:
                    y, x = prev[(y, x)]
                return (y - start[0], x - start[1])
            for dy, dx, ny, nx in self.neighbors(rows, y, x):
                if (ny, nx) in prev or not self.passable(rows, ny, nx):
                    continue
                if not self.diag_ok(rows, y, x, dy, dx):
                    continue
                prev[(ny, nx)] = (y, x)
                q.append((ny, nx))
        return None

    def frontier(self, rows, y, x):
        """A walkable square next to unexplored darkness."""
        if rows[y][x] not in ".#+":
            return False
        for dy, dx, ny, nx in self.neighbors(rows, y, x):
            if rows[ny][nx] == " " and (rows[y][x] in "#+" or dy == 0 or dx == 0):
                return self.visited[(y, x)] < 2
        return False

    # ---------------------------------------------------------------- policy
    def decide(self, st):
        rows = st.rows
        if not rows:                       # after score(): fgets for "[Press return...]"
            return 13
        # a loop (the same screen again and again): try something else
        self.recent.append(st.head.split(" X")[-1])
        if len(self.recent) > 24:
            self.recent.popleft()
        if len(self.recent) == 24 and len(set(self.recent)) <= 2:
            self.recent.clear()
            self.plan.clear()
            letters = [p for p, _, _ in st.pack]
            return ord(self.rng.choice(letters + list("hjklyubn") + [" "]))
        screen = st.text()
        msg = st.msg()
        if "--More--" in msg or "Press space to continue" in screen:
            return 32
        if "[Press return to continue]" in screen:
            return 13
        if self.plan:
            return self.plan.popleft()
        low = msg.lower()
        if "which direction" in low:
            return ord(self.rng.choice("hjklyubn"))
        if "hand" in low and "?" in low:
            return ord(self.rng.choice("lr"))
        if "call it" in low or "file name" in low or "save file" in low:
            return 27
        if "really quit" in low:
            return ord("n")
        if ("what" in low or "which" in low) and "?" in low:
            # an item prompt; identify cannot be cancelled, so usually answer
            letters = [p for p, _, _ in st.pack]
            if letters and ("identify" in low or self.rng.random() < 0.8):
                return ord(self.rng.choice(letters))
            return 27
        return self.act(st)

    def act(self, st):
        rows, pos = st.rows, st.pos
        rng = self.rng
        if st.vals.get("L") != self.level:
            self.level = st.vals.get("L")
            self.level_keys = 0
            self.visited.clear()
            self.searches = 0
            self.budget = rng.randint(150, 450)
        self.level_keys += 1
        self.visited[pos] += 1
        o = ord

        # hunger: eat
        if st.vals.get("H", 0) >= 1:
            f = self.item(st, o(":"))
            if f:
                self.plan.append(o(f))
                return o("e")
        # fight anything next to us; when losing, try potions and scrolls
        for dy, dx, ny, nx in self.neighbors(rows, *pos):
            if rows[ny][nx].isupper() and self.diag_ok(rows, pos[0], pos[1], dy, dx):
                if st.hp * 3 < st.maxhp and rng.random() < 0.6:
                    for cmd, kind in (("q", "!"), ("r", "?")):
                        p = self.item(st, o(kind))
                        if p and rng.random() < 0.7:
                            self.plan.append(o(p))
                            return o(cmd)
                if rng.random() < 0.15:
                    w = self.item(st, o("/"))
                    if w:
                        self.plan += [o(w), o(MOVES[(dy, dx)])]
                        return o("z")
                return o(MOVES[(dy, dx)])
        # hurt and nothing next to us: rest (a counted search)
        if st.hp * 10 < st.maxhp * 7 and rng.random() < 0.85:
            self.plan += [o("0"), o("s")]
            return o("2")
        # sometimes use things (coverage)
        r = rng.random()
        if r < 0.025:
            choice = rng.choice(["q!", "r?", "w)", "W]", "P=", "R=", "T]", "d*", "t)", "z/", "i", "D", "c?"])
            cmd, kind = choice[0], choice[1:] if len(choice) > 1 else ""
            if kind == "*":
                letters = [p for p, _, _ in st.pack if p not in st.equipped]
                if letters:
                    self.plan.append(o(rng.choice(letters)))
                    return o(cmd)
            elif kind:
                p = self.item(st, o(kind), spare=cmd in "dt")
                if p:
                    self.plan.append(o(p))
                    if cmd in "tz":
                        self.plan.append(o(rng.choice("hjklyubn")))
                    if cmd == "P":
                        self.plan.append(o(rng.choice("lr")))
                    if cmd == "c":
                        self.plan += [o(ch) for ch in rng.choice(["foo", "x", "bar"])] + [13]
                    return o(cmd)
            else:
                return o(cmd)
        # on the stairs and ready to leave
        explored = self.level_keys > self.budget or self.searches > 20
        winning = self.goal == "win" and st.vals.get("A") == 1
        if winning:
            explored = True
        if explored and rows[pos[0]][pos[1]] == "@" and self.on_stairs(st):
            return o("<" if winning else ">")
        # wizard: skip a level that takes too long
        if self.master and self.level_keys > 2 * self.budget and rng.random() < 0.05:
            return 4                                   # ^D
        # walk: items, then unexplored places, then the stairs (the stairs
        # first once the level is done; keep exploring while they are unseen)
        items = lambda y, x: rows[y][x] in ITEMS
        unexplored = lambda y, x: self.frontier(rows, y, x)
        stairs = lambda y, x: rows[y][x] == "%"
        goals = [stairs, unexplored, items] if explored else [items, unexplored, stairs]
        for g in goals:
            mv = self.bfs(rows, pos, g)
            if mv is not None:
                key = MOVES[mv]
                if pos == self.last_pos:
                    self.stuck += 1
                self.last_pos = pos
                if self.stuck > 6:
                    self.stuck = 0
                    return o(rng.choice("hjklyubn"))
                if rng.random() < 0.2 and rows[pos[0] + mv[0]][pos[1] + mv[1]] in ".#":
                    return o(key.upper())          # run
                return o(key)
        # nothing to do: search, then wander
        self.searches += 1
        if rng.random() < 0.6:
            return o("s")
        return o(rng.choice("hjklyubn"))

    def on_stairs(self, st):
        # the stairs square is drawn as '%' when we stand next to it; the digest
        # has no "under the hero", so remember where we saw it
        y, x = st.pos
        return getattr(self, "stairs", None) == (self.level, y, x)

    def note(self, st):
        if st.rows:
            for y in range(1, 23):
                x = st.rows[y].find("%")
                if x >= 0:
                    self.stairs = (st.vals.get("L"), y, x)


def play(seed, max_keys, out, opts=None, master=False, args=(), goal="deep"):
    """Play one game on the oracle; write the key script; return (keys, steps, level)."""
    case = {"seed": seed, "opts": opts, "master": master, "args": list(args)}
    env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "TERM": "xterm", "LINES": "24",
           "COLUMNS": "80", "TZ": "UTC", "ROGUE_SEED": str(seed), "ROGUE_TIME": str(difftest.TIME),
           "ROGUE_NAME": difftest.NAME, "ROGUE_HOME": difftest.HOME, "ROGUE_UID": str(difftest.UID),
           "ROGUE_KEYS": "-", "ROGUE_DUMP": "/dev/stderr", "ROGUE_FULL": "1"}
    if opts is not None:
        env["ROGUEOPTS"] = opts
    rundir = out + ".run"
    os.makedirs(rundir, exist_ok=True)
    p = subprocess.Popen([difftest.oracle_bin(master)] + list(args), cwd=rundir, env=env,
                         stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                         text=True, bufsize=1)
    bot = Bot(random.Random(seed * 104729 + 7), master, goal)
    if master and args and args[0] == "":
        bot.plan.append(9)         # wizard ^I: level 10, a +1,+1 two-handed sword, plate mail
        if goal == "win":          # create the Amulet of Yendor: C , 0
            bot.plan += [32, 32, ord("C"), ord(","), ord("0"), 32, 32]
    keys = []
    deepest = 1
    try:
        while True:
            st = read_step(p.stderr)
            if st is None:
                break
            deepest = max(deepest, st.vals.get("L", 1))
            if len(keys) >= max_keys:
                p.stdin.close()
                break
            bot.note(st)
            k = bot.decide(st)
            keys.append(k)
            p.stdin.write(f"{k}\n")
            p.stdin.flush()
    except (BrokenPipeError, OSError):
        pass
    finally:
        try:
            p.wait(timeout=30)
        except subprocess.TimeoutExpired:
            p.kill()
    difftest.write_keys(out, keys, case)
    for f in os.listdir(rundir):
        os.remove(os.path.join(rundir, f))
    os.rmdir(rundir)
    return len(keys), deepest


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--count", type=int, default=1)
    ap.add_argument("--first-seed", type=int)
    ap.add_argument("--max-keys", type=int, default=5000)
    ap.add_argument("--out", help="key file (one game)")
    ap.add_argument("--out-dir", default=os.path.join(HERE, "out", "bot"))
    ap.add_argument("--opts")
    ap.add_argument("--master", action="store_true")
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--goal", choices=["deep", "win"], default="deep",
                    help="win (with --master): create the Amulet and climb out")
    a = ap.parse_args()
    os.makedirs(a.out_dir, exist_ok=True)
    first = a.first_seed if a.first_seed is not None else a.seed
    seeds = list(range(first, first + a.count))

    def one(s):
        path = a.out if (a.out and a.count == 1) else os.path.join(a.out_dir, f"bot{s}.keys")
        n, deepest = play(s, a.max_keys, path, a.opts, a.master, [""] if a.master else [], a.goal)
        return s, path, n, deepest

    with cf.ThreadPoolExecutor(max_workers=a.jobs) as ex:
        for s, path, n, deepest in ex.map(one, seeds):
            print(f"seed {s}: {n} keys, deepest level {deepest} -> {path}", flush=True)


if __name__ == "__main__":
    main()
