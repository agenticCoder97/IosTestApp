import logging

logger = logging.getLogger(__name__)


async def fanfic_media_wipe_task(ctx, fanfic_id: str):
    """Placeholder for per-fanfic asset cleanup.

    Fanfic currently has no per-fanfic media directory — thumbnails come from
    a shared pre-seeded pool and must NOT be deleted. This task exists for
    symmetry with comic_media_wipe_task and to accommodate future per-fanfic
    assets (e.g. scraped hero images, cached covers). Enqueuing it from
    permanent_delete_fanfic keeps the pipeline symmetric and safe — it's a
    no-op today.
    """
    logger.info("fanfic_media_wipe_task noop | fanfic_id=%s", fanfic_id)
