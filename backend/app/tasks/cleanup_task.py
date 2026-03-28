import logging
from datetime import datetime, timezone, timedelta
from sqlalchemy import delete, and_
from app.db.database import AsyncSessionLocal
from app.core.config import settings
from app.models.comic import Comic, ComicChapter, Page
from app.models.fanfic import Fanfic, FanficChapter
from app.models.scrape import ScrapeJob
from app.models.progress import ReadingProgress

logger = logging.getLogger(__name__)


async def cleanup_task(ctx):
    """Nightly ARQ cron: hard-delete rows past soft_delete_days retention."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=settings.soft_delete_days)
    logger.info("cleanup_task started | cutoff=%s retention_days=%d", cutoff.isoformat(), settings.soft_delete_days)

    async with AsyncSessionLocal() as db:
        for model in [Page, ComicChapter, Comic, FanficChapter, Fanfic, ScrapeJob]:
            result = await db.execute(
                delete(model).where(
                    and_(model.deleted_at.is_not(None), model.deleted_at < cutoff)
                )
            )
            logger.info("cleanup_task deleted | model=%s rows=%d", model.__tablename__, result.rowcount)
        await db.commit()
    logger.info("cleanup_task complete")
