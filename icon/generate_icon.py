#!/usr/bin/env python3
"""
Renders the MultiVolume app icon master (AppIcon-1024.png).

A speaker feeding three output nodes on a blue squircle plate. Drawn at 4x
and downsampled with LANCZOS so edges stay clean without a vector renderer.

Usage:  python3 generate_icon.py            # writes AppIcon-1024.png
        python3 make_iconset.py             # then rebuilds AppIcon.iconset

Requires Pillow.
"""

import math
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.dirname(os.path.abspath(__file__))

CANVAS = 1024                         # final master size
S = 4                                 # supersample factor
PLATE = 832                           # icon plate within the 1024 canvas
PLATE_ORIGIN = (CANVAS - PLATE) // 2
PLATE_RADIUS = int(PLATE * 0.2237)    # Big Sur+ squircle approximation

WHITE = (255, 255, 255, 255)
BLUE = ((0x1D, 0x4E, 0xD8), (0x0E, 0xA5, 0xE9))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def diagonal_gradient(size, top_left, bottom_right):
    """Diagonal linear gradient, drawn small then upscaled."""
    small = Image.new("RGB", (64, 64))
    px = small.load()
    for y in range(64):
        for x in range(64):
            t = (x / 63 + y / 63) / 2
            px[x, y] = lerp(top_left, bottom_right, t)
    return small.resize((size, size), Image.LANCZOS)


def make_plate(top_left, bottom_right):
    """Rounded-rectangle icon plate with a soft drop shadow and sheen."""
    canvas = Image.new("RGBA", (CANVAS * S, CANVAS * S), (0, 0, 0, 0))

    plate_px = PLATE * S
    radius_px = PLATE_RADIUS * S
    origin = PLATE_ORIGIN * S

    mask = Image.new("L", (plate_px, plate_px), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, plate_px - 1, plate_px - 1], radius=radius_px, fill=255
    )

    shadow = Image.new("RGBA", (CANVAS * S, CANVAS * S), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 90), (origin, origin + int(18 * S)), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=14 * S))
    canvas = Image.alpha_composite(canvas, shadow)

    fill = diagonal_gradient(plate_px, top_left, bottom_right).convert("RGBA")

    sheen = Image.new("RGBA", (plate_px, plate_px), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).ellipse(
        [-plate_px // 3, -plate_px // 2, plate_px, plate_px // 2],
        fill=(255, 255, 255, 34),
    )
    sheen = sheen.filter(ImageFilter.GaussianBlur(radius=30 * S))
    fill = Image.alpha_composite(fill, sheen)

    plate = Image.new("RGBA", (CANVAS * S, CANVAS * S), (0, 0, 0, 0))
    plate.paste(fill, (origin, origin), mask)
    return Image.alpha_composite(canvas, plate)


def speaker(draw, cx, cy, u, colour=WHITE):
    """Speaker body: rectangular neck plus a cone, drawn around (cx, cy)."""
    neck = [cx - 2.05 * u, cy - 0.62 * u, cx - 1.15 * u, cy + 0.62 * u]
    draw.rounded_rectangle(neck, radius=0.16 * u, fill=colour)
    cone = [
        (cx - 1.30 * u, cy - 0.62 * u),
        (cx - 0.05 * u, cy - 1.62 * u),
        (cx - 0.05 * u, cy + 1.62 * u),
        (cx - 1.30 * u, cy + 0.62 * u),
    ]
    draw.polygon(cone, fill=colour)


def thick_line(draw, x1, y1, x2, y2, width, colour):
    """Line with round caps, which PIL does not provide natively."""
    draw.line([x1, y1, x2, y2], fill=colour, width=int(width))
    r = width / 2
    for px, py in ((x1, y1), (x2, y2)):
        draw.ellipse([px - r, py - r, px + r, py + r], fill=colour)


def render(spread=41, reach=2.22, node=0.35, line=0.23):
    img = make_plate(*BLUE)
    d = ImageDraw.Draw(img)
    cx, cy = CANVAS * S // 2, CANVAS * S // 2
    u = 106 * S

    speaker(d, cx - 0.80 * u, cy, u)
    hub = (cx - 0.70 * u, cy)

    for angle in (-spread, 0, spread):
        rad = math.radians(angle)
        nx = hub[0] + reach * u * math.cos(rad)
        ny = hub[1] + reach * u * math.sin(rad)
        thick_line(d, hub[0], hub[1], nx, ny, line * u, WHITE)
        r = node * u
        d.ellipse([nx - r, ny - r, nx + r, ny + r], fill=WHITE)

    return img.resize((CANVAS, CANVAS), Image.LANCZOS)


def main():
    path = os.path.join(OUT, "AppIcon-1024.png")
    render().save(path)
    print(f"wrote {path}")


if __name__ == "__main__":
    main()
