#!/usr/bin/env bash
# The whole verification suite in one command:
#   - rebuild the oracle (the original C game, std and MASTER);
#   - compile every GDScript file and lint coroutine discipline;
#   - the curses differential fuzzer (emulation vs real ncurses);
#   - the regression corpus (harness/corpus), a seed sweep of level
#     generation, random key scripts (standard and wizard mode) and
#     save/restore chains, each diffed step by step against the oracle.
#     Every batch runs many games in one Godot process, so it also checks
#     that RogueBase.reset() starts each game from a clean state.
# Exit status 0 only if everything is identical.
#
# usage: harness/run_all.sh [--quick]     (--quick: smaller sweeps)
# GODOT=/path/to/godot overrides the binary (default: godot on PATH, else /root/bin/godot).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export GODOT="${GODOT:-$(command -v godot || echo /root/bin/godot)}"
seeds=500; fuzz=300; wiz=200; saves=100; cfuzz=1000
if [ "${1:-}" = "--quick" ]; then seeds=100; fuzz=60; wiz=40; saves=20; cfuzz=200; fi
fail=0

step() { echo; echo "=== $*"; }

step "oracle builds"
for v in std master; do "$root/harness/oracle/build.sh" "$v" || fail=1; done

step "GDScript compile + await lint"
"$root/tools/check.sh" || fail=1

step "curses emulation vs ncurses ($cfuzz scripts)"
python3 "$root/harness/curses_fuzz/run.py" --count "$cfuzz" --godot "$GODOT" || fail=1

if [ -d "$root/harness/corpus" ]; then
    step "regression corpus"
    python3 "$root/harness/difftest.py" corpus || fail=1
fi

step "level generation, $seeds seeds"
python3 "$root/harness/difftest.py" seeds --count "$seeds" || fail=1

step "random key scripts, $fuzz runs"
python3 "$root/harness/difftest.py" fuzz --count "$fuzz" --len 1000 --first-seed 100000 || fail=1

step "wizard-mode random key scripts, $wiz runs"
python3 "$root/harness/difftest.py" fuzz --wizard --count "$wiz" --len 1500 --first-seed 200000 || fail=1

step "save/restore chains, $saves runs"
python3 "$root/harness/difftest.py" saves --count "$saves" --len 500 --first-seed 300000 || fail=1

echo
if [ $fail -eq 0 ]; then echo "run_all: ALL OK"; else echo "run_all: FAILURES (see above)"; fi
exit $fail
