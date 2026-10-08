#!/usr/bin/env python3
"""Builds Resources/AppIcon.icns from Resources/Brand/logo-square.png (full-bleed 1024x1024).

Follows the macOS icon grid: an 824px squircle body centred on a 1024px canvas with a soft
drop shadow, so macOS 26 treats it as a standard icon instead of placing it on a gray plate.

    python3 scripts/make-icon.py      # requires Pillow
"""
import io
import struct
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "Resources/Brand/logo-square.png"
OUTPUT = ROOT / "Resources/AppIcon.icns"

CANVAS, BODY = 1024, 824
SUPERSAMPLE = 4
EXPONENT = 5.0  # superellipse ≈ Apple's continuous-corner squircle

# (OSType, pixel size) — PNG-based entries.
ENTRIES = [
    ("icp4", 16), ("icp5", 32), ("ic11", 32), ("ic12", 64), ("ic07", 128),
    ("ic13", 256), ("ic08", 256), ("ic14", 512), ("ic09", 512), ("ic10", 1024),
]


def squircle_mask(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    half = big / 2
    points = []
    steps = 2048
    import math
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        x = half + half * math.copysign(abs(c) ** (2 / EXPONENT), c)
        y = half + half * math.copysign(abs(s) ** (2 / EXPONENT), s)
        points.append((x, y))
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def master() -> Image.Image:
    logo = Image.open(SOURCE).convert("RGBA").resize((BODY, BODY), Image.LANCZOS)
    mask = squircle_mask(BODY)
    logo.putalpha(ImageChops.multiply(logo.getchannel("A"), mask))

    offset = (CANVAS - BODY) // 2
    shadow_alpha = Image.new("L", (CANVAS, CANVAS), 0)
    shadow_alpha.paste(mask, (offset, offset + 10))
    shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(14)).point(lambda v: int(v * 0.35))
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.putalpha(shadow_alpha)
    canvas.alpha_composite(logo, (offset, offset))
    return canvas


def icns(image: Image.Image) -> bytes:
    body = b""
    cache = {}
    for ostype, pixels in ENTRIES:
        if pixels not in cache:
            buf = io.BytesIO()
            image.resize((pixels, pixels), Image.LANCZOS).save(buf, "PNG", optimize=True)
            cache[pixels] = buf.getvalue()
        png = cache[pixels]
        body += ostype.encode() + struct.pack(">I", 8 + len(png)) + png
    return b"icns" + struct.pack(">I", 8 + len(body)) + body


if __name__ == "__main__":
    image = master()
    image.save(ROOT / "Resources/Brand/AppIcon-1024.png")
    OUTPUT.write_bytes(icns(image))
    print(f"Wrote {OUTPUT.relative_to(ROOT)}")
