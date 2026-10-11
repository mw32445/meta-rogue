#!/usr/bin/env python3
"""Lint: no name declared in our GDScript may be a Godot global (docs/CONVENTIONS.md §1).

Godot resolves an unqualified call f() to a built-in function before a class member,
so a module function named like one (sign, seed, exp, ...) can be silently bypassed; a
variable, parameter or local with such a name shadows the built-in in its scope. Every
declaration under godot/ (func, var, const, signal, enum, class, parameter, local,
for-loop variable) is checked against tools/godot_globals.json (generated from the
engine's API by tools/gen_godot_globals.py):
  - @GlobalScope/@GDScript functions, singletons, engine classes and built-in types;
  - the methods, properties, signals and constants of the script's native base class
    (overriding a virtual method such as _init or _ready is allowed).
Global constants (OK, KEY_DOWN, ...) are not checked: our curses constants keep their C
names on purpose, and inside our classes they resolve to ours before Godot's.

A clashing C name gets a trailing underscore: sign -> sign_, seed -> seed_.

usage: tools/lint_names.py [files...]   (default: every .gd under godot/)
exit status 1 on any clash.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
G = json.load(open(os.path.join(ROOT, "tools", "godot_globals.json")))
FUNCS = set(G["functions"])
SINGLETONS = set(G["singletons"])
CLASSES = G["classes"]

FUNC_RE = re.compile(r"\bfunc\b\s*(\w*)\s*\(")
VAR_RE = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(var|const)\s+(\w+)")
SIGNAL_RE = re.compile(r"^\s*signal\s+(\w+)\s*(\()?")
ENUM_RE = re.compile(r"^\s*enum\s*(\w*)\s*\{([^}]*)\}?")
CLASS_RE = re.compile(r"^(\s*)class\s+(\w+)(?:\s+extends\s+(\w+))?\s*:")
CLASS_NAME_RE = re.compile(r"^class_name\s+(\w+)")
EXTENDS_RE = re.compile(r"^extends\s+(\w+)")
FOR_RE = re.compile(r"\bfor\s+(\w+)\s+in\b")


def strip(line):
    """Remove string literals and comments."""
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


def params_of(text):
    """Parameter names in a parameter list (the text after the opening parenthesis)."""
    depth, cur, parts = 0, "", []
    for c in text:
        if c in "([{":
            depth += 1
        elif c in ")]}":
            if depth == 0:
                break
            depth -= 1
        if c == "," and depth == 0:
            parts.append(cur)
            cur = ""
        else:
            cur += c
    parts.append(cur)
    names = []
    for p in parts:
        m = re.match(r"\s*(\w+)", p)
        if m:
            names.append(m.group(1))
    return names


def project_classes(files):
    """class_name -> extends, over every script."""
    table = {}
    for path in files:
        name = base = None
        for line in open(path, encoding="utf-8"):
            m = CLASS_NAME_RE.match(line)
            if m:
                name = m.group(1)
            m = EXTENDS_RE.match(line)
            if m:
                base = m.group(1)
        if name:
            table[name] = base or "RefCounted"
    return table


def native_base(base, project):
    seen = set()
    while base in project and base not in seen:
        seen.add(base)
        base = project[base]
    return base or "RefCounted"


def members_of(native):
    names = set()
    while native:
        c = CLASSES.get(native)
        if c is None:
            break
        names |= set(c["members"])
        native = c["inherits"]
    return names


def clash(name, members, is_func):
    if name in FUNCS:
        return "a built-in function"
    if name in SINGLETONS:
        return "an engine singleton"
    if name in CLASSES:
        return "an engine class or built-in type"
    if name in members:
        if is_func and name.startswith("_"):
            return None	# overriding a virtual method
        return "a member of the native base class"
    return None


def lint(path, project):
    problems = []
    lines = open(path, encoding="utf-8").read().split("\n")
    script_base = "RefCounted"
    for line in lines:
        m = EXTENDS_RE.match(line)
        if m:
            script_base = m.group(1)
            break
    script_members = members_of(native_base(script_base, project))
    inner = None	# (indent, members) of the inner class being read
    for n, raw in enumerate(lines, 1):
        line = strip(raw)
        if not line.strip():
            continue
        indent = len(line) - len(line.lstrip())
        if inner is not None and indent <= inner[0]:
            inner = None
        members = inner[1] if inner else script_members
        found = []	# (kind, name, is_func)
        m = CLASS_RE.match(line)
        if m:
            found.append(("class", m.group(2), False))
            inner = (len(m.group(1)), members_of(native_base(m.group(3) or "RefCounted", project)))
        m = CLASS_NAME_RE.match(line)
        if m:
            found.append(("class_name", m.group(1), False))
        for fm in FUNC_RE.finditer(line):
            if fm.group(1):
                found.append(("function", fm.group(1), True))
            text = line[fm.end():]
            k = n
            while text.count("(") >= text.count(")") and ")" not in text and k < len(lines):
                text += strip(lines[k])
                k += 1
            for p in params_of(text):
                found.append(("parameter", p, False))
        m = VAR_RE.match(line)
        if m:
            found.append((m.group(1), m.group(2), False))
        m = SIGNAL_RE.match(line)
        if m:
            found.append(("signal", m.group(1), False))
            if m.group(2):
                for p in params_of(line[m.end():]):
                    found.append(("signal parameter", p, False))
        m = ENUM_RE.match(line)
        if m:
            if m.group(1):
                found.append(("enum", m.group(1), False))
            for e in m.group(2).split(","):
                e = e.split("=")[0].strip()
                if e:
                    found.append(("enum value", e, False))
        for fm in FOR_RE.finditer(line):
            found.append(("loop variable", fm.group(1), False))
        for kind, name, is_func in found:
            why = clash(name, members, is_func)
            if why:
                problems.append(f"{os.path.relpath(path, ROOT)}:{n}: {kind} '{name}' "
                                f"has the same name as {why} (add a trailing _)")
    return problems


def main():
    files = sys.argv[1:]
    if not files:
        for d, _, fs in os.walk(os.path.join(ROOT, "godot")):
            if "/." in d:
                continue
            files += [os.path.join(d, f) for f in fs if f.endswith(".gd")]
    every = []
    for d, _, fs in os.walk(os.path.join(ROOT, "godot")):
        if "/." not in d:
            every += [os.path.join(d, f) for f in fs if f.endswith(".gd")]
    project = project_classes(every)
    problems = []
    for f in sorted(files):
        problems += lint(f, project)
    for p in problems:
        print(p)
    if problems:
        print(f"lint_names: {len(problems)} clash(es) with Godot names")
        return 1
    print(f"lint_names: OK ({len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
