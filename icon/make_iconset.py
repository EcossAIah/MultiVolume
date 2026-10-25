#!/usr/bin/env python3
"""
Builds AppIcon.iconset from a 1024px master.

Downsampling happens here with LANCZOS rather than at build time with sips,
because the small sizes are where an icon lives or dies and the better
resampling is visible at 32px and below.

Usage:  python3 make_iconset.py [master.png]
"""

import os
import shutil
import sys
from PIL import Image

OUT = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MASTER = os.path.join(OUT, "AppIcon-1024.png")

SPECS = [
    (16, "icon_16x16"),
    (32, "icon_16x16@2x"),
    (32, "icon_32x32"),
    (64, "icon_32x32@2x"),
    (128, "icon_128x128"),
    (256, "icon_128x128@2x"),
    (256, "icon_256x256"),
    (512, "icon_256x256@2x"),
    (512, "icon_512x512"),
    (1024, "icon_512x512@2x"),
]


def main():
    master_path = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_MASTER
    master = Image.open(master_path).convert("RGBA")

    # Keep the canonical master alongside the iconset when building from
    # an external file.
    if os.path.abspath(master_path) != DEFAULT_MASTER:
        shutil.copyfile(master_path, DEFAULT_MASTER)

    iconset = os.path.join(OUT, "AppIcon.iconset")
    shutil.rmtree(iconset, ignore_errors=True)
    os.makedirs(iconset)

    for size, name in SPECS:
        img = master.resize((size, size), Image.LANCZOS)
        img.save(os.path.join(iconset, f"{name}.png"))
        print(f"{name}.png  ({size}x{size})")

    print(f"\niconset ready: {iconset}")


if __name__ == "__main__":
    main()
