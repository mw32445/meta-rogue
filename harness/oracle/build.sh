#!/usr/bin/env bash
# Build the reference oracle: the original Rogue 5.4.4 C sources from the repo
# root + oracle.patch (documented fidelity fixes, see docs/FIDELITY.md) +
# hooks.c (scripted input, step log, pinned environment) via -Wl,--wrap.
#
# usage: harness/oracle/build.sh [std|master|cov]   -> harness/oracle/build/<variant>/rogue-oracle
#   std     the default build (no wizard mode)               -O2
#   master  wizard mode compiled in (-DMASTER)               -O2
#   cov     default build with gcov instrumentation          -O0 --coverage
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
variant="${1:-std}"
out="$here/build/$variant"

rm -rf "$out"
mkdir -p "$out"
find "$root" -maxdepth 1 -type f ! -name '.*' -exec cp {} "$out"/ \;
cd "$out"
patch -p1 --quiet < "$here/oracle.patch"

conf=()
[ "$variant" = master ] && conf+=(--enable-wizardmode)
./configure "${conf[@]}" > configure.log 2>&1

common=(-g -std=gnu17 -fwrapv -ftrivial-auto-var-init=zero -fcommon -DHAVE_CONFIG_H -w)
case "$variant" in
    std|master) cflags=(-O2 "${common[@]}") ;;
    cov)        cflags=(-O0 --coverage "${common[@]}") ;;
    *) echo "unknown variant: $variant" >&2; exit 2 ;;
esac

srcs=(vers extern armor chase command daemon daemons fight init io list
      mach_dep main mdport misc monsters move new_level options pack passages
      potions rings rip rooms save scrolls state sticks things weapons wizard
      xcrypt)
for s in "${srcs[@]}"; do
    gcc "${cflags[@]}" -c "$s.c" -o "$s.o"
done
gcc "${cflags[@]}" -I. -c "$here/hooks.c" -o hooks.o

wraps=(wgetch wgetnstr fgets halfdelay nocbreak raw initscr delwin baudrate
       erasechar killchar time getpid md_getuid md_getusername md_gethomedir
       md_shellescape md_sleep md_crypt md_getpass free exit fopen unlink chmod
       md_getrealname getenv md_onsignal_default)
ldwrap=()
for w in "${wraps[@]}"; do ldwrap+=("-Wl,--wrap=$w"); done

gcc "${cflags[@]}" ./*.o "${ldwrap[@]}" -lncurses -o rogue-oracle
echo "built $out/rogue-oracle"
