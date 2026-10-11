#!/usr/bin/env bash
# The whole verification suite in one command:
#   - rebuild the oracle (the original C game, std and MASTER);
#   - compile every GDScript file and lint coroutine discipline;
#   - the curses differential fuzzer (emulation vs real ncurses);
#   - the regression corpus (harness/corpus), a seed sweep of level
#     generation, and a batch of random key scripts, each diffed step by step
#     against the oracle.
# Exit status 0 only if everything is identical.
#
# usage: harness/run_all.sh [--quick]     (--quick: smaller sweeps)
# GODOT=/path/to/godot overrides the binary (default: godot on PATH, else /root/bin/godot).
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
export GODOT="${GODOT:-$(command -v godot || echo /root/bin/godot)}"
seeds=500; fuzz=300; cfuzz=1000
if [ "${1:-}" = "--quick" ]; then seeds=100; fuzz=60; cfuzz=200; fi
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
python3 "$root/harness/difftest.py" fuzz --count "$fuzz" --first-seed 100000 || fail=1

echo
if [ $fail -eq 0 ]; then echo "run_all: ALL OK"; else echo "run_all: FAILURES (see above)"; fi
exit $fail
