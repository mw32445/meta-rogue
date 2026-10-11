#!/usr/bin/env bash
# Compile GDScript and lint coroutine discipline (docs/CONVENTIONS.md §7).
#
#   tools/check.sh                    import + compile every script + lint
#   tools/check.sh --quick FILE...    compile in an isolated copy of the project in
#                                     which every godot/rogue module NOT named is
#                                     restored from the last commit (so other
#                                     people's half-edited files cannot break your
#                                     check); then lint everything
#                                     e.g. tools/check.sh --quick godot/rogue/fight.gd
# GODOT=/path/to/godot overrides the binary.
set -uo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
godot="${GODOT:-$(command -v godot || echo /root/bin/godot)}"

filter() {
    grep -E "Parse Error|Compile Error|SCRIPT ERROR|FAILED|checked|at: GDScript::reload" \
        | grep -vE "GDScript backtrace" | head -80
}

if [ "${1:-}" = "--quick" ]; then
    shift
    tmp="$(mktemp -d /tmp/rogue-check.XXXXXX)"
    trap 'rm -rf "$tmp"' EXIT
    cp -r "$root/godot" "$tmp/godot"
    rm -rf "$tmp/godot/.godot"
    declare -A keep=()
    for f in "$@"; do keep["$(basename "$f")"]=1; done
    for f in "$root"/godot/rogue/*.gd; do
        b="$(basename "$f")"
        if [ -z "${keep[$b]:-}" ] && git -C "$root" cat-file -e "HEAD:godot/rogue/$b" 2>/dev/null; then
            git -C "$root" show "HEAD:godot/rogue/$b" > "$tmp/godot/rogue/$b"
        fi
    done
    (cd "$tmp/godot" && "$godot" --headless --path . --import > /dev/null 2>&1)
    out="$(cd "$tmp/godot" && timeout 300 "$godot" --headless --path . --script res://tests/check_all.gd 2>&1)"
    status=$?
    echo "$out" | grep -q "SCRIPT ERROR" && status=1
    echo "$out" | filter
    [ $status -eq 0 ] && echo "compile: OK ($# file(s) checked in isolation)" || echo "check: compile FAILED"
    python3 "$root/tools/lint_await.py" "$@" || status=1
    exit $status
fi

cd "$root/godot"
"$godot" --headless --path . --import > /dev/null 2>&1
out="$(timeout 300 "$godot" --headless --path . --script res://tests/check_all.gd 2>&1)"
status=$?
echo "$out" | grep -q "SCRIPT ERROR" && status=1
echo "$out" | filter
[ $status -eq 0 ] || { echo "check: compile FAILED (status $status)"; exit 1; }
python3 "$root/tools/lint_await.py" || exit 1
echo "check: OK"
