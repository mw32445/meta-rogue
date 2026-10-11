#!/usr/bin/env python3
"""Lint the GDScript port for coroutine discipline (docs/CONVENTIONS.md §7).

Rules
  1. A function that is a C function (tools/symbols.json) is a coroutine in the
     port iff it is on the closed blocking list (tools/blocking.json); it must
     contain `await` iff it is listed.
  2. Port-only helpers (not C functions) are coroutines iff their body awaits.
  3. Every call to a coroutine is directly preceded by `await`.
  4. Every `await`ed call targets a coroutine (Godot also reports REDUNDANT_AWAIT).

usage: tools/lint_await.py [files...]   (default: every .gd under godot/rogue)
exit status 1 on any violation.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RENAME_FUNC = {"call": "call_"}
# Coroutine primitives that are not C functions.
PRIMITIVES = {
    ("RogueBase", "getch"), ("RogueBase", "wgetch"), ("RogueBase", "wgetnstr"),
    ("RogueBase", "fgets_stdin"), ("RogueBase", "exit"), ("RogueBase", "abort"),
    ("RogueBase", "debug"), ("RogueBase", "_todo"),
}
DEF_RE = re.compile(r"^(static\s+)?func\s+(\w+)\s*\(")
CALL_RE = re.compile(r"(?<![\w.])(?:(\w+)\.)?(\w+)\s*\(")
CLASS_RE = re.compile(r"^class_name\s+(\w+)")


def strip(line):
    """Remove string literals and comments (good enough for our code style)."""
    out, i, q = [], 0, None
    while i < len(line):
        c = line[i]
        if q:
            if c == "\\":
                i += 2
                continue
            if c == q:
                q = None
                out.append('""')
            i += 1
            continue
        if c in "\"'":
            q = c
            i += 1
            continue
        if c == "#":
            break
        out.append(c)
        i += 1
    return "".join(out)


def parse(path):
    cls = None
    funcs = []          # (name, start_line, [body lines (stripped)])
    cur = None
    for n, raw in enumerate(open(path, encoding="utf-8"), 1):
        line = raw.rstrip("\n")
        m = CLASS_RE.match(line)
        if m:
            cls = m.group(1)
        d = DEF_RE.match(line)
        if d:
            cur = [d.group(2), n, []]
            funcs.append(cur)
            continue
        if cur is not None:
            if line and not line[0].isspace() and not line.startswith("#"):
                cur = None
                continue
            cur[2].append((n, strip(line)))
    return cls, funcs


def main():
    sym = json.load(open(os.path.join(ROOT, "tools", "symbols.json")))
    blk = json.load(open(os.path.join(ROOT, "tools", "blocking.json")))
    c_funcs = {RENAME_FUNC.get(f, f) for f in sym["functions"]}
    listed = {RENAME_FUNC.get(f, f) for f in blk["blocking"]}
    # coroutines added by changes to the port itself (gameplay changes), with reasons
    listed |= {RENAME_FUNC.get(f, f) for f in blk.get("port_blocking", {})}
    files = [os.path.join(dp, f) for dp, _, fs in os.walk(os.path.join(ROOT, "godot", "rogue"))
             for f in fs if f.endswith(".gd")]
    only = {os.path.realpath(f) for f in sys.argv[1:]}   # report only these (all are parsed)
    modules = {}
    for p in files:
        cls, funcs = parse(p)
        modules[p] = (cls or os.path.basename(p), funcs)
    # function -> defining classes; coroutine set as (class, func)
    defined = {}
    awaits = set()
    for p, (cls, funcs) in modules.items():
        for name, _, body in funcs:
            defined.setdefault(name, set()).add(cls)
            if any(re.search(r"\bawait\b", t) for _, t in body):
                awaits.add((cls, name))
    coro = set(PRIMITIVES) | {(c, f) for (c, f) in awaits}
    errors = []
    # rule 1
    for p, (cls, funcs) in modules.items():
        if cls == "RogueBase":
            continue
        for name, line, body in funcs:
            if name in c_funcs:
                has = (cls, name) in awaits
                if name in listed and not has:
                    errors.append(f"{p}:{line}: {name} is on the blocking list but never awaits")
                if name not in listed and has:
                    errors.append(f"{p}:{line}: {name} awaits but is not on the blocking list "
                                  "(tools/blocking.json); see CONVENTIONS.md §7")
    # C functions on the list are coroutines even before they are translated
    for name in listed:
        for cls in defined.get(name, ()):
            coro.add((cls, name))
    coro_names = {f for _, f in coro}

    def is_coro(qual, name, cls):
        if qual:
            return (qual, name) in coro
        # unqualified: same class, then RogueBase (inherited)
        return (cls, name) in coro or ("RogueBase", name) in coro

    # rules 3 and 4
    for p, (cls, funcs) in modules.items():
        for fname, _, body in funcs:
            for n, text in body:
                for m in CALL_RE.finditer(text):
                    qual, name = m.group(1), m.group(2)
                    if name in ("func", "if", "elif", "while", "for", "match", "return", "await", "not", "and", "or"):
                        continue
                    before = text[:m.start()].rstrip()
                    awaited = before.endswith("await")
                    if name not in coro_names:
                        if awaited and qual is not None and qual[0].isupper():
                            errors.append(f"{p}:{n}: `await {qual}.{name}(...)` but {name} is not a coroutine")
                        continue
                    if is_coro(qual, name, cls) and not awaited:
                        errors.append(f"{p}:{n}: call to coroutine {qual + '.' if qual else ''}{name}() is not awaited")
    if only:
        errors = [e for e in errors if os.path.realpath(e.split(":")[0]) in only]
    for e in errors:
        print(e)
    print(f"lint_await: {len(errors)} problem(s) in {len(only) or len(modules)} file(s)")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
