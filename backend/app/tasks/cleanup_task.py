from datetime import datetime, timezone, timedelta
from sqlalchemy import delete, and_
from app.db.database import AsyncSessionLocal
from app.core.config import settings
from app.models.comic import Comic, ComicChapter, Page
from app.models.fanfic import Fanfic, FanficChapter
from app.models.scrape import ScrapeJob
from app.models.progress import ReadingProgress


async def cleanup_task(ctx):
    """Nightly ARQ cron: hard-delete rows past soft_delete_days retention."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=settings.soft_delete_days)

    async with AsyncSessionLocal() as db:
        for model in [Page, ComicChapter, Comic, FanficChapter, Fanfic, ScrapeJob]:
            await db.execute(
                delete(model).where(
                    and_(model.deleted_at.is_not(None), model.deleted_at < cutoff)
                )
            )
        await db.commit()
