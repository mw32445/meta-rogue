#!/usr/bin/env python3
"""Generate tools/godot_globals.json, the Godot names tools/lint_names.py checks against.

  godot --headless --doctool DIR          (dumps the engine's API reference as XML)
  tools/gen_godot_globals.py DIR          (writes tools/godot_globals.json)

The file lists:
  functions   @GlobalScope utility functions and @GDScript functions (sign, seed, exp, ...)
  constants   @GlobalScope and @GDScript constants (OK, KEY_DOWN, PI, ...)
  singletons  @GlobalScope members (OS, Engine, Input, ...)
  classes     every engine class and built-in type, with its parent and, for the native
              classes our scripts extend (and their ancestors), its methods, properties,
              signals and constants.
Regenerate it when the engine version changes.
"""
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Native classes our scripts extend; their ancestors are added automatically.
BASES = ["RefCounted", "Control", "SceneTree", "Node", "Resource"]


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    classes = {}
    functions, constants, singletons = set(), set(), set()
    for path in glob.glob(os.path.join(sys.argv[1], "**", "*.xml"), recursive=True):
        root = ET.parse(path).getroot()
        if root.tag != "class":
            continue
        name = root.get("name")
        members = set()
        for tag in ("methods/method", "members/member", "signals/signal", "constants/constant"):
            members |= {e.get("name") for e in root.findall(tag)}
        if name in ("@GlobalScope", "@GDScript"):
            functions |= {e.get("name") for e in root.findall("methods/method")}
            constants |= {e.get("name") for e in root.findall("constants/constant")}
            singletons |= {e.get("name") for e in root.findall("members/member")}
            continue
        classes[name] = {"inherits": root.get("inherits"), "members": members}
    keep = set()
    for b in BASES:
        while b:
            keep.add(b)
            b = classes[b]["inherits"]
    out = {
        "functions": sorted(functions),
        "constants": sorted(constants),
        "singletons": sorted(singletons),
        "classes": {n: {"inherits": c["inherits"],
                        "members": sorted(c["members"]) if n in keep else []}
                    for n, c in sorted(classes.items())},
    }
    dst = os.path.join(ROOT, "tools", "godot_globals.json")
    with open(dst, "w") as f:
        json.dump(out, f, indent=0, sort_keys=True)
        f.write("\n")
    print(f"wrote {dst}: {len(functions)} functions, {len(constants)} constants, "
          f"{len(singletons)} singletons, {len(classes)} classes")


if __name__ == "__main__":
    main()
