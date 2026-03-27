import logging
from pathlib import Path
from typing import Optional, tuple
from PIL import Image

logger = logging.getLogger(__name__)


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
