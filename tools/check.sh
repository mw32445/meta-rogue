#!/usr/bin/env bash
# Compile GDScript and lint coroutine discipline (docs/CONVENTIONS.md §7).
#
#   tools/check.sh                    import + compile every script + lint
#   tools/check.sh --quick FILE...    compile only FILEs (no import: safe to run
#                                     concurrently) + lint everything
#                                     e.g. tools/check.sh --quick godot/rogue/fight.gd
# GODOT=/path/to/godot overrides the binary.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-$(command -v godot || echo /root/bin/godot)}"
cd "$root/godot"

filter() {
    grep -E "Parse Error|Compile Error|SCRIPT ERROR|FAILED|checked|at: GDScript::reload" \
        | grep -vE "GDScript backtrace" | head -80
}

if [ "${1:-}" = "--quick" ]; then
    shift
    status=0
    for f in "$@"; do
        rel="res://${f#godot/}"
        rel="${rel#res://$root/godot/}"
        out="$(timeout 120 "$godot" --headless --path . --check-only --script "$rel" 2>&1)"
        if echo "$out" | grep -qE "Parse Error|Compile Error|SCRIPT ERROR"; then
            echo "== $f"
            echo "$out" | filter
            status=1
        fi
    done
    [ $status -eq 0 ] && echo "compile: OK ($# file(s))" || echo "check: compile FAILED"
    python3 "$root/tools/lint_await.py" || status=1
    exit $status
fi

"$godot" --headless --path . --import > /dev/null 2>&1
out="$(timeout 300 "$godot" --headless --path . --script res://tests/check_all.gd 2>&1)"
status=$?
echo "$out" | filter
[ $status -eq 0 ] || { echo "check: compile FAILED (status $status)"; exit 1; }
python3 "$root/tools/lint_await.py" || exit 1
echo "check: OK"
