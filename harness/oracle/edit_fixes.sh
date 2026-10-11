#!/usr/bin/env bash
# Work on harness/oracle/fixes.patch, the C side of the port's bug fixes
# (RogueBase.fixes; docs/CHANGES.md lists them).
#
#   harness/oracle/edit_fixes.sh DIR          DIR/a: the C sources + oracle.patch
#                                             DIR/b: the same + fixes.patch; edit DIR/b
#   harness/oracle/edit_fixes.sh --diff DIR   rewrite fixes.patch as the diff a -> b
#
# The patch applies on top of oracle.patch (build.sh, variants fixed/fixedmaster).
# Fixes in hooks.c (built from harness/oracle, not patched) use #ifdef ORACLE_FIXES.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
if [ "${1:-}" = "--diff" ]; then
    dir="$(cd "$2" && pwd)"
    (cd "$dir" && diff -ruN -x '*.o' -x '*.orig' -x '*.rej' a b) > "$here/fixes.patch" || true
    echo "wrote $here/fixes.patch ($(grep -c '^@@' "$here/fixes.patch") hunks)"
    exit 0
fi
dir="$1"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
rm -rf "$dir/a" "$dir/b"
mkdir -p "$dir/a"
find "$root" -maxdepth 1 -type f -name '*.[ch]' -exec cp {} "$dir/a/" \;
(cd "$dir/a" && patch -p1 --quiet < "$here/oracle.patch")
cp -r "$dir/a" "$dir/b"
if grep -q '^@@' "$here/fixes.patch"; then (cd "$dir/b" && patch -p1 --quiet < "$here/fixes.patch"); fi
echo "edit $dir/b, then: $0 --diff $dir"
