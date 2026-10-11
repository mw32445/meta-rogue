#!/usr/bin/env bash
# Prepare a fresh machine or cloud session for this repository:
#   1. a Godot 4.7.2 editor binary at $GODOT_BIN (default /root/bin/godot).
#      It downloads the official Linux build when the network allows it,
#      otherwise it builds Godot from source (about 25 minutes on 4 cores).
#   2. the reference oracle (the original C game), std and MASTER builds.
#
# In a Claude Code cloud environment, use this as the environment's setup
# script so new sessions start with everything in place.
#
# usage: tools/setup_env.sh            (idempotent: skips what already exists)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="4.7.2-stable"
godot_bin="${GODOT_BIN:-/root/bin/godot}"

have_godot() {
    [ -x "$godot_bin" ] && "$godot_bin" --headless --version 2>/dev/null | grep -q "^4\.7\.2"
}

if have_godot; then
    echo "godot: $("$godot_bin" --headless --version 2>/dev/null) at $godot_bin"
else
    mkdir -p "$(dirname "$godot_bin")"
    tmp="$(mktemp -d)"
    url="https://github.com/godotengine/godot/releases/download/$version/Godot_v${version}_linux.x86_64.zip"
    echo "godot: trying the official build ($url)"
    if curl -fsSL --retry 3 -o "$tmp/godot.zip" "$url" && unzip -q -o "$tmp/godot.zip" -d "$tmp"; then
        install -m 755 "$tmp/Godot_v${version}_linux.x86_64" "$godot_bin"
    else
        echo "godot: download failed; building $version from source (this takes a while)"
        command -v scons > /dev/null || pip install --quiet scons
        src="${GODOT_SRC:-/root/godot-src}"
        [ -d "$src/.git" ] || git clone --depth 1 --branch "$version" \
            https://github.com/godotengine/godot.git "$src"
        # wayland=no: the Wayland scanner is not installed in the cloud image.
        (cd "$src" && nice scons platform=linuxbsd target=editor wayland=no -j"$(nproc)")
        install -m 755 "$src/bin/godot.linuxbsd.editor.x86_64" "$godot_bin"
    fi
    rm -rf "$tmp"
    have_godot || { echo "godot: setup failed" >&2; exit 1; }
    echo "godot: $("$godot_bin" --headless --version 2>/dev/null) at $godot_bin"
fi

for v in std master; do
    if [ ! -x "$root/harness/oracle/build/$v/rogue-oracle" ]; then
        "$root/harness/oracle/build.sh" "$v"
    fi
done
(cd "$root/godot" && "$godot_bin" --headless --path . --import > /dev/null 2>&1) || true
echo "setup: OK"
