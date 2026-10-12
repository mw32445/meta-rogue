#!/usr/bin/env python3
"""Draw Meta-Rogue's icon, godot/icon.png: the hero, a yellow '@' in the game's own
font (godot/fonts/DejaVuSansMono.ttf), on a dark rounded tile, 1024 x 1024.

The project uses it for the window (application/config/icon); the exports turn it
into the Windows .exe's icon and the macOS app's. Needs Pillow.

usage: tools/make_icon.py [OUT.png]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT = os.path.join(ROOT, "godot", "fonts", "DejaVuSansMono.ttf")
SIZE = 1024
TILE = (20, 22, 28, 255)
EDGE = (88, 74, 40, 255)
HERO = (244, 196, 64, 255)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "godot", "icon.png")
    # drawn at 4x and scaled down, for smooth edges
    s = SIZE * 4
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    m = s // 16
    d.rounded_rectangle((m, m, s - m, s - m), radius=s // 6, fill=TILE, outline=EDGE, width=s // 64)
    font = ImageFont.truetype(FONT, int(s * 0.78))
    l, t, r, b = d.textbbox((0, 0), "@", font=font)
    d.text(((s - (r - l)) / 2 - l, (s - (b - t)) / 2 - t), "@", font=font, fill=HERO)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(out, optimize=True)
    print(out)


if __name__ == "__main__":
    main()
