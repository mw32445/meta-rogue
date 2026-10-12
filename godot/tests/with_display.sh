#!/usr/bin/env bash
# Run a command on a virtual display (Xvfb) with a window manager that handles
# fullscreen requests (godot/tests/mini_wm.py) and, unless --keep-data is given, an
# empty user data folder (XDG_DATA_HOME in a temporary folder, removed afterwards), so
# the UI tests neither see nor touch your saved game, scores and video settings.
#
#   godot/tests/with_display.sh [--screen=WxH ...] [--workarea=X,Y,W,H] [--keep-data]
#       -- COMMAND...
#
# The default is one 1920x1080 monitor. Several --screen options make one monitor per
# screen, side by side. --workarea publishes a desktop panel's usable area
# (_NET_WORKAREA, single monitor). The exit status is the command's.
# Example:
#   godot/tests/with_display.sh --workarea=0,0,1920,1040 -- /root/bin/godot \
#       --path godot --script res://tests/ui_video.gd -- --out=/tmp/video
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
screens=()
wm_args=()
keep=0
while [ $# -gt 0 ]; do
    case "$1" in
        --screen=*) screens+=("${1#--screen=}") ;;
        --workarea=*) wm_args+=("$1") ;;
        --keep-data) keep=1 ;;
        --) shift; break ;;
        *) echo "with_display.sh: unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
[ $# -gt 0 ] || { echo "usage: with_display.sh [options] -- COMMAND..." >&2; exit 2; }
[ ${#screens[@]} -gt 0 ] || screens=("1920x1080")
width=0
height=0
monitors=""
for s in "${screens[@]}"; do
    w="${s%x*}"
    h="${s#*x}"
    monitors+="${monitors:+,}${w}x${h}+${width}+0"
    width=$((width + w))
    [ "$h" -gt "$height" ] && height="$h"
done
[ ${#screens[@]} -gt 1 ] && wm_args+=("--monitors=$monitors")

data=""
if [ $keep -eq 0 ]; then
    data="$(mktemp -d "${TMPDIR:-/tmp}/rogue-ui.XXXXXX")"
    export XDG_DATA_HOME="$data"
fi
# Inside the display: the window manager (it returns once it manages the display and
# ends with the display), then the command. Arguments: the window manager's path, its
# option string, the command.
inner='python3 "$0" --daemon $1 || exit 2; shift; exec "$@"'
xvfb-run -a -s "-screen 0 ${width}x${height}x24" bash -c "$inner" "$here/mini_wm.py" \
    "${wm_args[*]:-}" "$@"
status=$?
[ -n "$data" ] && rm -rf "$data"
exit $status
