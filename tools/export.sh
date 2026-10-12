#!/usr/bin/env bash
# Export Meta-Rogue for Windows, macOS and Linux and pack the downloads:
#   dist/Meta-Rogue-<version>-windows.zip  Meta-Rogue/: Meta-Rogue.exe, guild_prices.txt,
#                                          README.txt, LICENSES.txt
#   dist/Meta-Rogue-<version>-macos.zip    Meta-Rogue.app (Intel and Apple Silicon, ad-hoc
#                                          signed), README.txt, LICENSES.txt
#   dist/Meta-Rogue-<version>-linux.zip    Meta-Rogue/: Meta-Rogue.x86_64, guild_prices.txt,
#                                          README.txt, LICENSES.txt
#   dist/SHA256SUMS.txt
# <version> is application/config/version in godot/project.godot; the presets are in
# godot/export_presets.cfg. README.txt is INSTALL.md. LICENSES.txt holds Rogue's
# licence, the font's, and Godot's with its third-party notices.
# tools/check_export.py checks the result.
#
# usage: tools/export.sh [--templates]
#   --templates  first install Godot's official export templates for this Godot
#                version (downloaded once to ~/.cache/meta-rogue and checked against
#                the release's SHA512-SUMS.txt; only the three needed are installed)
# GODOT=/path/to/godot overrides the binary (default: godot on PATH, else /root/bin/godot).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-$(command -v godot || echo /root/bin/godot)}"
proj="$root/godot"
dist="$root/dist"
stage="$dist/stage"
name="Meta-Rogue"
needed=(windows_release_x86_64.exe linux_release.x86_64 macos.zip)

die() { echo "export: $*" >&2; exit 1; }

version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$proj/project.godot")"
[ -n "$version" ] || die "godot/project.godot has no application/config/version"

# Godot's version, e.g. 4.7.2.stable.custom_build.ed1daf0bf: its templates are in
# export_templates/4.7.2.stable, from the release 4.7.2-stable.
gv="$("$GODOT" --headless --version 2>/dev/null | tail -1)"
[[ "$gv" =~ ^([0-9]+\.[0-9]+(\.[0-9]+)?)\.([a-z]+[0-9]*) ]] || die "can't read Godot's version ($gv)"
tdir="${BASH_REMATCH[1]}.${BASH_REMATCH[3]}"
tag="${BASH_REMATCH[1]}-${BASH_REMATCH[3]}"
templates="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$tdir"

install_templates() {
    local cache="${XDG_CACHE_HOME:-$HOME/.cache}/meta-rogue"
    local tpz="Godot_v${tag}_export_templates.tpz"
    local url="https://github.com/godotengine/godot/releases/download/$tag"
    local t have=1
    for t in version.txt "${needed[@]}"; do [ -f "$templates/$t" ] || have=0; done
    if [ $have = 1 ] && [ "$(cat "$templates/version.txt")" = "$tdir" ]; then
        echo "export: templates $tdir already installed"
        return
    fi
    mkdir -p "$cache" "$templates"
    curl -fsSL --retry 3 -o "$cache/SHA512-SUMS.txt" "$url/SHA512-SUMS.txt"
    if ! (cd "$cache" && grep " $tpz\$" SHA512-SUMS.txt | sha512sum -c --status 2>/dev/null); then
        echo "export: downloading $tpz (about 1.3 GB)"
        curl -fL --retry 3 -o "$cache/$tpz.part" "$url/$tpz"
        mv "$cache/$tpz.part" "$cache/$tpz"
        (cd "$cache" && grep " $tpz\$" SHA512-SUMS.txt | sha512sum -c --status) \
            || die "$tpz does not match the release's SHA512-SUMS.txt"
    fi
    unzip -q -o -j "$cache/$tpz" templates/version.txt "${needed[@]/#/templates/}" -d "$templates"
    [ "$(cat "$templates/version.txt")" = "$tdir" ] || die "the templates are for $(cat "$templates/version.txt"), not $tdir"
    echo "export: templates $tdir installed in $templates"
}

[ "${1:-}" = "--templates" ] && install_templates
for t in "${needed[@]}"; do
    [ -f "$templates/$t" ] || die "no $templates/$t (tools/export.sh --templates installs it)"
done

rm -rf "$dist"
mkdir -p "$stage"
"$GODOT" --headless --path "$proj" --import > "$stage/import.log" 2>&1 || { cat "$stage/import.log"; die "the import failed"; }

# The files each download holds besides the game.
cp "$root/INSTALL.md" "$stage/README.txt"
"$GODOT" --headless --path "$proj" --script "$root/tools/godot_licenses.gd" -- --out="$stage/godot.txt" \
    > /dev/null 2>&1 || die "tools/godot_licenses.gd failed"
{
    echo "Meta-Rogue $version"
    echo
    echo "Meta-Rogue is Rogue 5.4.4 ported to the Godot Engine. These are the licences of"
    echo "what it is made of."
    echo
    echo "==== 1. Rogue 5.4.4 ===="
    echo
    cat "$root/LICENSE.TXT"
    echo
    echo "==== 2. The font: DejaVu Sans Mono ===="
    echo
    cat "$proj/fonts/DejaVuSansMono-LICENSE.txt"
    echo
    echo "==== 3. Godot Engine $tag ===="
    echo
    cat "$stage/godot.txt"
} > "$stage/LICENSES.txt"

# export PRESET OUT: one release export; its warnings and errors are shown.
export_one() {
    local log="$stage/$1.log"
    mkdir -p "$(dirname "$2")"
    if ! "$GODOT" --headless --path "$proj" --export-release "$1" "$2" > "$log" 2>&1 || [ ! -s "$2" ]; then
        cat "$log"
        die "the $1 export failed"
    fi
    grep -E "ERROR|WARNING" "$log" || true
}

for os in windows linux; do
    exe="$name.exe"
    preset="Windows"
    if [ $os = linux ]; then exe="$name.x86_64"; preset="Linux"; fi
    dir="$stage/$os/$name"
    export_one "$preset" "$dir/$exe"
    cp "$proj/guild_prices.txt" "$stage/README.txt" "$stage/LICENSES.txt" "$dir/"
    (cd "$stage/$os" && zip -q -r -9 "$dist/$name-$version-$os.zip" "$name")
done

# macOS: Godot makes the zip (Meta-Rogue.app, signed); the README and licences join it.
export_one "macOS" "$stage/macos/$name.zip"
cp "$stage/macos/$name.zip" "$dist/$name-$version-macos.zip"
(cd "$stage" && zip -q -9 "$dist/$name-$version-macos.zip" README.txt LICENSES.txt)

rm -rf "$stage"
(cd "$dist" && sha256sum "$name-$version"-*.zip > SHA256SUMS.txt)
echo "export: Meta-Rogue $version with Godot $tag"
(cd "$dist" && ls -l --block-size=K "$name-$version"-*.zip SHA256SUMS.txt | awk '{print "  " $5 "  " $9}')
