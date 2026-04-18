#!/usr/bin/env python3
"""
Seed 50 fanfic thumbnail JPGs into the astral_media volume.
Usage: python scripts/seed_fanfic_thumbnails.py [--force] [--output-dir /path]

Requires: Pillow (`pip install pillow`)

This script is a deploy-time step — run once inside the backend container:
  docker compose exec backend python scripts/seed_fanfic_thumbnails.py

Re-run with --force to overwrite existing files (e.g. when replacing with curated art).

TODO: Replace generated gradient images with curated manga/book-cover art by dropping
      real 400x600 JPGs named 1.jpg–50.jpg into the volume and re-running with --force.
"""
import argparse
import os
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

COLORS = [
    (0x2A, 0x2A, 0x4A),  # deep indigo
    (0x4A, 0x2A, 0x2A),  # deep burgundy
    (0x2A, 0x4A, 0x34),  # deep forest
    (0x40, 0x32, 0x4A),  # deep plum
    (0x32, 0x40, 0x44),  # deep teal
    (0x3A, 0x3A, 0x2A),  # deep olive
]
GLYPHS = ["📖", "📜", "✒️", "🌟", "📚", "🖊️", "🌙", "⭐"]
WIDTH, HEIGHT = 400, 600
COUNT = 50


def make_gradient(color_top, color_bot, size=(WIDTH, HEIGHT)):
    img = Image.new("RGB", size)
    for y in range(size[1]):
        t = y / size[1]
        r = int(color_top[0] * (1 - t) + color_bot[0] * t)
        g = int(color_top[1] * (1 - t) + color_bot[1] * t)
        b = int(color_top[2] * (1 - t) + color_bot[2] * t)
        ImageDraw.Draw(img).line([(0, y), (size[0], y)], fill=(r, g, b))
    return img


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--output-dir", default="/mnt/astral-media/fanfic-thumbnails")
    args = parser.parse_args()

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    for n in range(1, COUNT + 1):
        dest = out / f"{n}.jpg"
        if dest.exists() and not args.force:
            print(f"  skip {dest.name} (exists)")
            continue
        color_a = COLORS[(n - 1) % len(COLORS)]
        color_b = COLORS[n % len(COLORS)]
        img = make_gradient(color_a, color_b)
        # Overlay glyph at 30% opacity
        draw = ImageDraw.Draw(img, "RGBA")
        glyph = GLYPHS[(n - 1) % len(GLYPHS)]
        draw.text(
            (WIDTH // 2, HEIGHT // 2),
            glyph,
            fill=(255, 255, 255, 77),
            anchor="mm",
            font=ImageFont.load_default(size=80),
        )
        img.save(dest, "JPEG", quality=70, optimize=True)
        print(f"  wrote {dest.name}")

    print(f"Done — {COUNT} thumbnails in {out}")


if __name__ == "__main__":
    main()
