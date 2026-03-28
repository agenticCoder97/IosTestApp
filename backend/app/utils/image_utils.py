import logging
import random
from pathlib import Path
from typing import Optional, tuple
from PIL import Image, ImageDraw, ImageFont

logger = logging.getLogger(__name__)

FANFIC_COVER_COUNT = 5
FANFIC_COVER_DIR = "fanfic-covers"
FANFIC_COVER_COLORS = [
    (42, 42, 74),    # deep indigo
    (74, 42, 42),    # deep burgundy
    (42, 74, 52),    # deep forest
    (64, 50, 74),    # deep plum
    (50, 64, 74),    # deep teal
]


def ensure_fanfic_covers(base_path: str) -> list[str]:
    """Generate simple placeholder cover images for fanfics if they don't exist.
    Returns list of relative paths."""
    cover_dir = Path(base_path) / FANFIC_COVER_DIR
    cover_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for i in range(FANFIC_COVER_COUNT):
        rel_path = f"{FANFIC_COVER_DIR}/cover_{i + 1}.jpg"
        full_path = Path(base_path) / rel_path
        paths.append(rel_path)
        if full_path.exists():
            continue
        color = FANFIC_COVER_COLORS[i % len(FANFIC_COVER_COLORS)]
        img = Image.new("RGB", (300, 400), color)
        draw = ImageDraw.Draw(img)
        # Draw a simple book icon (rectangle + spine line)
        bx, by, bw, bh = 100, 120, 100, 140
        draw.rectangle([bx, by, bx + bw, by + bh], outline=(200, 200, 200), width=2)
        draw.line([(bx + 10, by), (bx + 10, by + bh)], fill=(200, 200, 200), width=2)
        # Horizontal lines for text placeholder
        for ly in range(by + 30, by + bh - 20, 18):
            draw.line([(bx + 22, ly), (bx + bw - 12, ly)], fill=(160, 160, 160), width=1)
        img.save(full_path, "JPEG", quality=85)
        logger.info("ensure_fanfic_covers created | path=%s", rel_path)
    return paths


def random_fanfic_cover() -> str:
    """Return a random fanfic cover relative path."""
    i = random.randint(1, FANFIC_COVER_COUNT)
    return f"{FANFIC_COVER_DIR}/cover_{i}.jpg"


def get_image_dimensions(file_path: str | Path) -> Optional[tuple[int, int]]:
    """Returns (width, height) or None if file is not a valid image."""
    try:
        with Image.open(file_path) as img:
            dims = img.size
            logger.debug("get_image_dimensions | path=%s width=%d height=%d", file_path, dims[0], dims[1])
            return dims
    except Exception as e:
        logger.warning("get_image_dimensions failed | path=%s error=%s", file_path, e)
        return None


def generate_thumbnail(src_path: str | Path, dest_path: str | Path, size: tuple[int, int] = (300, 400)) -> bool:
    """Generate a thumbnail. Returns True on success."""
    logger.info("generate_thumbnail starting | src=%s dest=%s size=%s", src_path, dest_path, size)
    try:
        with Image.open(src_path) as img:
            img.thumbnail(size, Image.LANCZOS)
            img.save(dest_path)
        logger.info("generate_thumbnail success | src=%s dest=%s", src_path, dest_path)
        return True
    except Exception as e:
        logger.error("generate_thumbnail failed | src=%s dest=%s error=%s", src_path, dest_path, e)
        return False
