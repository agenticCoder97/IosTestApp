import logging
import shutil
from pathlib import Path

from app.core.config import settings

logger = logging.getLogger(__name__)


async def comic_media_wipe_task(ctx, comic_id: str):
    """Best-effort rmtree of comic media directories.

    Wipes both the live path (`comics/{id}`) and the archive path
    (`archive/comics/{id}`) because archive_status is not known at
    wipe time. Never raises — any filesystem errors are logged and
    swallowed so the ARQ job always marks as complete.
    """
    media_root = Path(settings.block_volume_path)
    targets = [
        media_root / "comics" / comic_id,
        media_root / "archive" / "comics" / comic_id,
    ]
    for target in targets:
        try:
            shutil.rmtree(target, ignore_errors=True)
        except Exception as e:
            logger.warning(
                "comic_media_wipe_task rmtree failed | comic_id=%s target=%s error=%s",
                comic_id,
                target,
                e,
            )
    logger.info("comic_media_wipe_task done | comic_id=%s", comic_id)
