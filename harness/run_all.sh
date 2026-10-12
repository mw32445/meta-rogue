#!/usr/bin/env bash
# The whole verification suite in one command:
#   - rebuild the oracle (the original C game, std and MASTER);
#   - compile every GDScript file and lint coroutine discipline;
#   - the curses differential fuzzer (emulation vs real ncurses);
#   - the regression corpus (harness/corpus), a seed sweep of level
#     generation, random key scripts (standard and wizard mode) and
#     save/restore chains, each diffed step by step against the oracle.
#     Every batch runs many games in one Godot process, so it also checks
#     that RogueBase.reset() starts each game from a clean state;
#   - the same batches with the port's bug fixes on (RogueBase.fixes) against
#     the "fixed" oracle (C + harness/oracle/fixes.patch), plus the
#     expectations ("# expect-...") of the per-bug scripts in harness/corpus/fixes;
#   - the tests of what the oracle cannot judge: the Fighters' Guild
#     (godot/tests/guild_test.gd), the item menus and the status line's next-level
#     experience (godot/tests/menus_test.gd), the
#     fixes' UI checks (godot/tests/fixes_test.gd), the user data folder
#     (godot/tests/user_data_test.gd), and smoke runs of random games
#     with every switch on (difftest.py smoke: no script error, no hang);
#   - the downloads, when Godot's export templates are installed: tools/export.sh,
#     then tools/check_export.py (with --run under Xvfb).
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
# all of them first: difftest's lazy build would race between parallel runs
for v in std master fixed fixedmaster; do "$root/harness/oracle/build.sh" "$v" || fail=1; done

step "GDScript compile + await lint"
"$root/tools/check.sh" || fail=1

step "the Fighters' Guild (godot/tests/guild_test.gd)"
out="$("$GODOT" --headless --path "$root/godot" --script res://tests/guild_test.gd 2>&1)" || fail=1
echo "$out" | grep -E "^(FAIL|guild_test:)"

step "the Guild's price file (godot/tests/prices_test.gd)"
out="$("$GODOT" --headless --path "$root/godot" --script res://tests/prices_test.gd 2>&1)" || fail=1
echo "$out" | grep -E "^(FAIL|prices_test:)"

step "the item menus (godot/tests/menus_test.gd)"
out="$("$GODOT" --headless --path "$root/godot" --script res://tests/menus_test.gd 2>&1)" || fail=1
echo "$out" | grep -E "^(FAIL|menus_test:)"

step "the video settings (godot/tests/settings_test.gd)"
out="$("$GODOT" --headless --path "$root/godot" --script res://tests/settings_test.gd 2>&1)" || fail=1
echo "$out" | grep -E "^(FAIL|settings_test:)"

# The video settings in a real window (fullscreen, F10, Alt+Enter), when Xvfb is there.
if command -v Xvfb > /dev/null && command -v xvfb-run > /dev/null; then
    step "the video settings in a window (godot/tests/ui_video.gd, 1920x1080)"
    "$root/godot/tests/with_display.sh" --workarea=0,0,1920,1040 -- "$GODOT" --path "$root/godot" \
        --script res://tests/ui_video.gd 2>&1 | grep -E "FAIL|ui_video|PASS.*total" | tail -3
    [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
fi

step "the user data folder and its migration (godot/tests/user_data_test.gd)"
out="$("$GODOT" --headless --path "$root/godot" --script res://tests/user_data_test.gd 2>&1)" || fail=1
echo "$out" | grep -E "^(FAIL|user_data_test:)"

step "the fixes' UI checks (godot/tests/fixes_test.gd)"
out="$("$GODOT" --headless --path "$root/godot" --script res://tests/fixes_test.gd 2>&1)" || fail=1
echo "$out" | grep -E "FAIL|fixes_test"

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

# The bug fixes (RogueBase.fixes) against the fixed C.
if [ -d "$root/harness/corpus" ]; then
    step "fixed: regression corpus"
    python3 "$root/harness/difftest.py" corpus --fixes || fail=1
fi

step "fixed: level generation, $seeds seeds"
python3 "$root/harness/difftest.py" seeds --fixes --count "$seeds" || fail=1

step "fixed: random key scripts, $fuzz runs"
python3 "$root/harness/difftest.py" fuzz --fixes --count "$fuzz" --len 1000 --first-seed 400000 || fail=1

step "fixed: wizard-mode random key scripts, $wiz runs"
python3 "$root/harness/difftest.py" fuzz --fixes --wizard --count "$wiz" --len 1500 --first-seed 500000 || fail=1

step "fixed: save/restore chains, $saves runs"
python3 "$root/harness/difftest.py" saves --fixes --count "$saves" --len 500 --first-seed 600000 || fail=1

# Every switch on (the playable game), the port alone: no script error, no hang.
step "smoke: the playable game's switches, $fuzz runs"
python3 "$root/harness/difftest.py" smoke --fixes --guild --menus --expnext --count "$fuzz" --len 1000 --first-seed 800000 || fail=1
python3 "$root/harness/difftest.py" smoke --fixes --guild --menus --expnext --wizard --count "$wiz" --len 1500 --first-seed 900000 || fail=1

# The downloads (Windows, macOS, Linux), when Godot's export templates are installed
# (tools/export.sh --templates): built and checked, the Linux one played in a window.
tv="$("$GODOT" --headless --version 2>/dev/null | tail -1 | sed -E 's/^([0-9.]+)\.([a-z]+[0-9]*).*/\1.\2/')"
if [ -f "${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$tv/macos.zip" ]; then
    step "the downloads (tools/export.sh, tools/check_export.py)"
    "$root/tools/export.sh" > "$root/harness/out/export.log" 2>&1 || { tail -20 "$root/harness/out/export.log"; fail=1; }
    run=""
    command -v xvfb-run > /dev/null && run="--run"
    python3 "$root/tools/check_export.py" $run --shots="$root/harness/out/export_shots" 2>&1 | tail -3
    [ "${PIPESTATUS[0]}" -eq 0 ] || fail=1
else
    step "the downloads: skipped (no export templates; tools/export.sh --templates installs them)"
fi

echo
if [ $fail -eq 0 ]; then echo "run_all: ALL OK"; else echo "run_all: FAILURES (see above)"; fi
exit $fail
