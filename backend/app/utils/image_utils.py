from pathlib import Path
from typing import Optional, tuple
from PIL import Image


def get_image_dimensions(file_path: str | Path) -> Optional[tuple[int, int]]:
    """Returns (width, height) or None if file is not a valid image."""
    try:
        with Image.open(file_path) as img:
            return img.size
    except Exception:
        return None


def generate_thumbnail(src_path: str | Path, dest_path: str | Path, size: tuple[int, int] = (300, 400)) -> bool:
    """Generate a thumbnail. Returns True on success."""
    try:
        with Image.open(src_path) as img:
            img.thumbnail(size, Image.LANCZOS)
            img.save(dest_path)
        return True
    except Exception:
        return False
