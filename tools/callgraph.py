#!/usr/bin/env python3
"""Call-graph and symbol analysis of the original Rogue C sources (clang JSON AST).

Produces:
  tools/symbols.json   every function (file, line, signature, MASTER-only?), every
                       file-scope variable (global or static) and function-static
                       variable, with initializer text
  tools/blocking.json  the closed set of functions that can block on keyboard input
                       (each must be a coroutine in the port), the RNG-consuming set,
                       the function-pointer call sites and their targets
  docs/AUDIT.md        audits: unsequenced multi-RNG expressions, static-buffer
                       aliasing, indirect calls

The union of a default build and a MASTER build is analyzed, because the port keeps
every `#ifdef MASTER` block behind a runtime flag.

usage: tools/callgraph.py   (needs harness/oracle/build/{std,master}/config.h, i.e.
                            run harness/oracle/build.sh std && ... master first)
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRCS = ["vers", "extern", "armor", "chase", "command", "daemon", "daemons", "fight",
        "init", "io", "list", "mach_dep", "main", "mdport", "misc", "monsters", "move",
        "new_level", "options", "pack", "passages", "potions", "rings", "rip", "rooms",
        "save", "scrolls", "state", "sticks", "things", "weapons", "wizard", "xcrypt"]
# Functions whose port is replaced wholesale (portability layer / C save format).
PLATFORM_FILES = {"mdport.c", "state.c", "xcrypt.c", "mach_dep.c"}

# Library primitives that wait for keyboard input.
# exit/abort end the program: in the port they suspend forever, so their callers are coroutines too.
INPUT_PRIMITIVES = {"wgetch", "wgetnstr", "fgets", "getchar", "md_getpass", "exit", "abort"}
RNG_GLOBAL = "seed"

# Function-pointer call sites -> possible targets (verified by hand, see docs/AUDIT.md).
DAEMON_FUNCS = ["runners", "doctor", "swander", "stomach", "rollwand", "unconfuse",
                "nohaste", "unsee", "sight", "land", "come_down", "visuals", "turn_see"]
INDIRECT_TARGETS = {
    ("daemon.c", "do_daemons"): DAEMON_FUNCS,
    ("daemon.c", "do_fuses"): DAEMON_FUNCS,
    ("options.c", "option"): ["put_bool", "put_str", "put_inv_t",
                              "get_bool", "get_sf", "get_str", "get_inv_t"],
    ("things.c", "nameit"): ["nullstr", "ring_num", "charge_str"],
}
# Hand-reviewed verdicts for the unsequenced-RNG audit, keyed by (file, function, expression prefix).
REVIEWED = {
    "fuse(": "safe: BEFORE/AFTER are spread(1)/spread(2) = rnd(0), which consumes nothing; "
             "only the time argument draws",
    "GOLDCALC + GOLDCALC": "safe: identical-range draws that are summed; any order gives the "
                           "same total and the same final seed",
    "ring_eat(LEFT) + ring_eat(RIGHT)": "pinned: stock gcc -O0/-O2 calls LEFT first; oracle.patch "
                                        "makes it explicit; the port calls LEFT then RIGHT",
}
# Functions whose only blocking paths are unreachable or end in a crash. In the port
# they are plain functions; the message goes to push_error (docs/FIDELITY.md).
PORT_NONBLOCKING = {
    "new_item": "msg() only when calloc() fails, impossible in GDScript",
    "d_slot": "MASTER debug() when all 20 daemon slots are used; C then dereferences NULL",
    "inv_name": "MASTER debug() for an object type that does not exist",
    "pick_one": "MASTER debug() when the probability tables are inconsistent (they are fixed)",
    "find_obj": "MASTER debug('Non-object'); every caller then dereferences NULL",
    "roomin": "msg('in some bizarre place') is followed by a NULL dereference in C",
    "runto": "MASTER msg('couldn't find monster in runto') is followed by a NULL dereference",
    "new_thing": "MASTER debug() + wait_for in a default case that pick_one() never reaches",
    "badcheck": "MASTER check that a fixed probability table sums to 100; it always does",
}
# Functions that return a pointer to a static buffer, and which buffer.
STATIC_BUFFER_FUNCS = {
    "inv_name": "prbuf", "killname": "prbuf", "nothing": "prbuf",
    "set_mname": "set_mname.tbuf", "num": "num.numbuf", "ring_num": "ring_num.buf",
    "charge_str": "charge_str.buf", "unctrl": "ncurses.unctrl",
}


def ast(path, master):
    cfg = os.path.join(ROOT, "harness", "oracle", "build", "master" if master else "std")
    if not os.path.exists(os.path.join(cfg, "config.h")):
        sys.exit(f"missing {cfg}/config.h: run harness/oracle/build.sh first")
    cmd = ["clang", "-Xclang", "-ast-dump=json", "-fsyntax-only", "-w", "-std=gnu17",
           "-DHAVE_CONFIG_H", "-I", cfg, "-I", ROOT, path]
    if master:
        cmd.insert(1, "-DMASTER")
    out = subprocess.run(cmd, capture_output=True, check=False)
    if not out.stdout:
        sys.exit(f"clang failed on {path}: {out.stderr.decode()[:2000]}")
    return json.loads(out.stdout)


class Walker:
    """Pre-order walk that tracks the current file (clang omits unchanged 'file')."""

    def __init__(self, src_path):
        self.cur = None
        self.src_path = src_path

    def see_loc(self, loc):
        if not isinstance(loc, dict):
            return None
        if "spellingLoc" in loc or "expansionLoc" in loc:
            self.see_loc(loc.get("spellingLoc"))
            return self.see_loc(loc.get("expansionLoc"))
        if "file" in loc:
            self.cur = loc["file"]
        return self.cur

    def node_file(self, node):
        f = self.see_loc(node.get("loc"))
        rng = node.get("range", {})
        self.see_loc(rng.get("begin"))
        self.see_loc(rng.get("end"))
        return f


def text_of(src, node):
    rng = node.get("range", {})
    b, e = rng.get("begin", {}), rng.get("end", {})
    b = b.get("expansionLoc", b)
    e = e.get("expansionLoc", e)
    if "offset" not in b or "offset" not in e:
        return None
    return src[b["offset"]: e["offset"] + e.get("tokLen", 0)].decode("latin-1")


def line_of(node):
    loc = node.get("loc", {})
    loc = loc.get("expansionLoc", loc)
    if "line" in loc:
        return loc["line"]
    b = node.get("range", {}).get("begin", {})
    b = b.get("expansionLoc", b)
    return b.get("line")


def iter_nodes(node):
    stack = [node]
    while stack:
        n = stack.pop()
        yield n
        stack.extend(reversed(n.get("inner", []) or []))


def callee_name(call):
    """Name of a direct callee, or None for an indirect call."""
    inner = call.get("inner") or []
    if not inner:
        return None
    n = inner[0]
    while n.get("kind") in ("ImplicitCastExpr", "ParenExpr") and n.get("inner"):
        n = n["inner"][0]
    if n.get("kind") == "DeclRefExpr":
        ref = n.get("referencedDecl", {})
        if ref.get("kind") == "FunctionDecl":
            return ref.get("name")
    return None


def analyze_file(fname, master, db):
    path = os.path.join(ROOT, fname)
    src = open(path, "rb").read()
    tree = ast(path, master)
    w = Walker(path)
    lineno = 0
    for top in tree.get("inner", []):
        f = None
        # walk the whole subtree to keep the file tracker in sync
        for n in iter_nodes(top):
            nf = w.node_file(n)
            if n is top:
                f = nf
        if f is None or os.path.basename(f) != fname:
            continue
        kind = top.get("kind")
        if kind == "FunctionDecl" and any(c.get("kind") == "CompoundStmt" for c in top.get("inner", [])):
            analyze_function(fname, top, src, master, db)
        elif kind == "VarDecl":
            name = top["name"]
            key = (fname, name)
            init = None
            for c in top.get("inner", []) or []:
                init = text_of(src, c)
            db["vars"].setdefault(key, {
                "file": fname, "name": name, "type": top.get("type", {}).get("qualType"),
                "storage": top.get("storageClass", "global"), "line": line_of(top),
                "init": init, "master_only": master})
            if not master:
                db["vars"][key]["master_only"] = False


def analyze_function(fname, fn, src, master, db):
    name = fn["name"]
    info = db["funcs"].setdefault(name, {
        "file": fname, "line": line_of(fn), "type": fn.get("type", {}).get("qualType"),
        "static": fn.get("storageClass") == "static",
        "params": [p.get("name") for p in fn.get("inner", []) if p.get("kind") == "ParmVarDecl"],
        "master_only": master, "calls": set(), "indirect": [], "uses_seed": False,
        "fn_refs": set()})
    if not master:
        info["master_only"] = False
    body = next(c for c in fn["inner"] if c.get("kind") == "CompoundStmt")
    callee_refs = set()
    for n in iter_nodes(body):
        k = n.get("kind")
        if k == "CallExpr":
            c = callee_name(n)
            if c is None:
                info["indirect"].append(line_of(n))
            else:
                info["calls"].add(c)
                # remember the callee DeclRefExpr so it is not counted as a value use
                inner = n["inner"][0]
                while inner.get("kind") in ("ImplicitCastExpr", "ParenExpr") and inner.get("inner"):
                    inner = inner["inner"][0]
                callee_refs.add(id(inner))
            db["calls"].append((fname, name, n))
        elif k == "DeclRefExpr":
            ref = n.get("referencedDecl", {})
            if ref.get("kind") == "VarDecl" and ref.get("name") == RNG_GLOBAL:
                info["uses_seed"] = True
            if ref.get("kind") == "FunctionDecl" and id(n) not in callee_refs:
                info["fn_refs"].add(ref.get("name"))
        elif k == "VarDecl" and n.get("storageClass") == "static":
            init = None
            for c in n.get("inner", []) or []:
                init = text_of(src, c)
            key = (fname, f"{name}.{n['name']}")
            db["vars"].setdefault(key, {
                "file": fname, "name": n["name"], "function": name,
                "type": n.get("type", {}).get("qualType"), "storage": "static-local",
                "line": line_of(n), "init": init, "master_only": master})
            if not master:
                db["vars"][key]["master_only"] = False
    db["src"][fname] = src


def fixpoint(funcs, seeds, edges):
    reach = set(seeds)
    changed = True
    while changed:
        changed = False
        for f, outs in edges.items():
            if f not in reach and outs & reach:
                reach.add(f)
                changed = True
    return reach


def main():
    db = {"funcs": {}, "vars": {}, "calls": [], "src": {}}
    for master in (False, True):
        db["calls"] = [] if not master else db["calls"]
        for s in SRCS:
            analyze_file(s + ".c", master, db)
    funcs = db["funcs"]

    # edges: direct calls + indirect call sites -> targets
    edges = {f: set(i["calls"]) for f, i in funcs.items()}
    for (file, fn), targets in INDIRECT_TARGETS.items():
        edges.setdefault(fn, set()).update(targets)
    unknown_indirect = [(i["file"], f, i["indirect"]) for f, i in funcs.items()
                        if i["indirect"] and (i["file"], f) not in INDIRECT_TARGETS]

    blocking = fixpoint(funcs, INPUT_PRIMITIVES, {f: e for f, e in edges.items() if f not in PORT_NONBLOCKING})
    rng = fixpoint(funcs, {f for f, i in funcs.items() if i["uses_seed"]} | {"rnd", "roll"}, edges)
    blocking_game = sorted(f for f in blocking if f in funcs)
    rng_game = sorted(f for f in rng if f in funcs)

    # ---- audits over every call / operator expression
    unsequenced, aliasing = [], []
    seen = set()
    for (file, fn, call) in db["calls"]:
        pass  # calls are revisited below via the per-function walk
    for fname in db["src"]:
        src = db["src"][fname]
        for master in (False, True):
            tree = ast(os.path.join(ROOT, fname), master)
            w = Walker(fname)
            for top in tree.get("inner", []):
                f = None
                for n in iter_nodes(top):
                    nf = w.node_file(n)
                    if n is top:
                        f = nf
                if f is None or os.path.basename(f) != fname or top.get("kind") != "FunctionDecl":
                    continue
                for n in iter_nodes(top):
                    k = n.get("kind")
                    kids = n.get("inner") or []
                    groups = None
                    if k == "CallExpr":
                        groups = kids[1:]          # arguments
                    elif k in ("BinaryOperator", "CompoundAssignOperator") and n.get("opcode") not in ("&&", "||", ","):
                        groups = kids
                    if not groups:
                        continue
                    def calls_in(x):
                        return {callee_name(c) for c in iter_nodes(x) if c.get("kind") == "CallExpr"} - {None}
                    rng_groups = [g for g in groups if calls_in(g) & rng]
                    key = (fname, line_of(n), text_of(src, n))
                    if len(rng_groups) >= 2 and key not in seen:
                        seen.add(key)
                        unsequenced.append({"file": fname, "function": top["name"], "line": line_of(n),
                                            "expr": (text_of(src, n) or "")[:200]})
                    if k == "CallExpr":
                        bufs = []
                        for g in groups:
                            direct = g
                            while direct.get("kind") in ("ImplicitCastExpr", "ParenExpr", "CStyleCastExpr") and direct.get("inner"):
                                direct = direct["inner"][0]
                            if direct.get("kind") == "CallExpr" and callee_name(direct) in STATIC_BUFFER_FUNCS:
                                bufs.append(STATIC_BUFFER_FUNCS[callee_name(direct)])
                            elif direct.get("kind") == "DeclRefExpr" and direct.get("referencedDecl", {}).get("name") == "prbuf":
                                bufs.append("prbuf")
                        dup = {b for b in bufs if bufs.count(b) >= 2}
                        akey = ("alias",) + key
                        if dup and akey not in seen:
                            seen.add(akey)
                            aliasing.append({"file": fname, "function": top["name"], "line": line_of(n),
                                             "buffers": sorted(dup), "expr": (text_of(src, n) or "")[:200]})

    # ---- write outputs
    sym = {"functions": {}, "variables": []}
    for f, i in sorted(funcs.items()):
        sym["functions"][f] = {k: i[k] for k in ("file", "line", "type", "static", "params", "master_only")}
        sym["functions"][f]["platform"] = i["file"] in PLATFORM_FILES
        sym["functions"][f]["calls"] = sorted(i["calls"])
    for (file, key), v in sorted(db["vars"].items()):
        sym["variables"].append(v)
    json.dump(sym, open(os.path.join(ROOT, "tools", "symbols.json"), "w"), indent=1, sort_keys=True)

    blk = {
        "note": "Functions that can (transitively) wait for keyboard input. In the port each is a "
                "coroutine and every call to it must be awaited (tools/lint_await.py).",
        "input_primitives": sorted(INPUT_PRIMITIVES),
        "indirect_targets": {f"{k[0]}:{k[1]}": v for k, v in INDIRECT_TARGETS.items()},
        "port_nonblocking": PORT_NONBLOCKING,
        "blocking": blocking_game,
        "rng": rng_game,
    }
    json.dump(blk, open(os.path.join(ROOT, "tools", "blocking.json"), "w"), indent=1)

    with open(os.path.join(ROOT, "docs", "AUDIT.md"), "w") as out:
        out.write("# Static audits of the original C (generated by tools/callgraph.py)\n\n")
        out.write(f"- {len(funcs)} functions analyzed ({sum(1 for i in funcs.values() if i['master_only'])} MASTER-only).\n")
        out.write(f"- {len(blocking_game)} functions can block on input; {len(rng_game)} can consume RNG.\n\n")
        out.write("## Indirect (function-pointer) call sites\n\n")
        for (file, fn), t in INDIRECT_TARGETS.items():
            out.write(f"- `{file}:{fn}` → {', '.join(t)}\n")
        if unknown_indirect:
            out.write("\n**Unmapped indirect calls (must be reviewed):**\n\n")
            for file, fn, lines in unknown_indirect:
                out.write(f"- `{file}:{fn}` lines {lines}\n")
        out.write("\n## Unsequenced expressions with ≥2 RNG-consuming operands\n\n")
        out.write("C leaves the order unspecified; the oracle patch pins the stock gcc order and the port must match it.\n\n")
        for u in unsequenced:
            verdict = next((v for k, v in REVIEWED.items() if u["expr"].startswith(k)), "**UNREVIEWED**")
            out.write(f"- `{u['file']}:{u['line']}` in `{u['function']}`: `{u['expr']}` — {verdict}\n")
        if not unsequenced:
            out.write("- none\n")
        out.write("\n## Calls passing the same static buffer twice (aliasing)\n\n")
        out.write("C shows the last write in every position; a value-String port would not.\n\n")
        for a in aliasing:
            out.write(f"- `{a['file']}:{a['line']}` in `{a['function']}` ({', '.join(a['buffers'])}): `{a['expr']}`\n")
        if not aliasing:
            out.write("- none\n")
    print(f"functions={len(funcs)} blocking={len(blocking_game)} rng={len(rng_game)} "
          f"unsequenced={len(unsequenced)} aliasing={len(aliasing)} unmapped_indirect={len(unknown_indirect)}")


if __name__ == "__main__":
    main()
