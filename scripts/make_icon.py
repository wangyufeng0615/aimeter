#!/usr/bin/env python3
"""
Build macOS AppIcon.icns from a source image.

Pipeline:
  1. Floodfill background from corners → transparent (removes the beige canvas
     around Lovart-generated squircles without touching the subject)
  2. Auto-crop to non-transparent bounding box
  3. Pad to square, resize to 1024×1024
  4. Generate the 10-size iconset
  5. iconutil → .icns

Usage: scripts/make_icon.py <source_image> <output_icns>
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ICON_SIZES = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

FLOODFILL_THRESHOLD = 50  # RGB Euclidean tolerance for matching the background


def strip_background(img: Image.Image) -> Image.Image:
    rgba = img.convert("RGBA")
    w, h = rgba.size
    transparent = (0, 0, 0, 0)
    for corner in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(rgba, corner, transparent, thresh=FLOODFILL_THRESHOLD)
    return rgba


def crop_to_content(img: Image.Image) -> Image.Image:
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def pad_to_square(img: Image.Image) -> Image.Image:
    w, h = img.size
    side = max(w, h)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(img, ((side - w) // 2, (side - h) // 2), img)
    return canvas


def build_icns(src: Path, dst: Path) -> None:
    img = Image.open(src)
    cleaned = strip_background(img)
    cropped = crop_to_content(cleaned)
    square = pad_to_square(cropped)
    master = square.resize((1024, 1024), Image.LANCZOS)

    with tempfile.TemporaryDirectory() as tmpdir:
        iconset = Path(tmpdir) / "AppIcon.iconset"
        iconset.mkdir()
        for size, scale in ICON_SIZES:
            px = size * scale
            suffix = f"{size}x{size}" if scale == 1 else f"{size}x{size}@2x"
            (master.resize((px, px), Image.LANCZOS)
                   .save(iconset / f"icon_{suffix}.png"))

        # Also drop the master 1024 PNG next to the .icns for previewing.
        preview = dst.with_name("AppIcon-preview.png")
        master.save(preview)

        dst.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            ["iconutil", "-c", "icns", str(iconset), "-o", str(dst)],
            check=True,
        )


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    src = Path(sys.argv[1])
    dst = Path(sys.argv[2])
    if not src.exists():
        print(f"source not found: {src}", file=sys.stderr)
        return 1
    if shutil.which("iconutil") is None:
        print("iconutil not found — install Xcode Command Line Tools", file=sys.stderr)
        return 1
    build_icns(src, dst)
    print(f"✓ {dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
