import logging
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.comic import Comic, Page
from app.models.comic import ComicChapter
from app.models.fanfic import Fanfic
from app.models.fanfic import FanficChapter
from app.models.scrape import ScrapeJob
from app.schemas.stats import StatsResponse

logger = logging.getLogger(__name__)


async def get_stats(db: AsyncSession) -> StatsResponse:
    logger.info("get_stats called")

    total_comics = (await db.execute(
        select(func.count()).select_from(Comic).where(Comic.deleted_at.is_(None))
    )).scalar_one()

    total_fanfics = (await db.execute(
        select(func.count()).select_from(Fanfic).where(Fanfic.deleted_at.is_(None))
    )).scalar_one()

    comics_in_progress = (await db.execute(
        select(func.count()).select_from(Comic).where(
            Comic.deleted_at.is_(None),
            Comic.status == "partial",
        )
    )).scalar_one()

    fanfics_in_progress = (await db.execute(
        select(func.count()).select_from(Fanfic).where(
            Fanfic.deleted_at.is_(None),
            Fanfic.completion_status == "ongoing",
        )
    )).scalar_one()

    total_pages_scraped = (await db.execute(
        select(func.count()).select_from(Page)
    )).scalar_one()

    total_chapters_scraped = (await db.execute(
        select(func.count()).select_from(ComicChapter).where(
            ComicChapter.scrape_status == "scraped",
            ComicChapter.deleted_at.is_(None),
        )
    )).scalar_one() + (await db.execute(
        select(func.count()).select_from(FanficChapter).where(
            FanficChapter.scrape_status == "scraped",
            FanficChapter.deleted_at.is_(None),
        )
    )).scalar_one()

    active_scrape_jobs = (await db.execute(
        select(func.count()).select_from(ScrapeJob).where(
            ScrapeJob.deleted_at.is_(None),
            ScrapeJob.status.in_(["queued", "running"]),
        )
    )).scalar_one()

    logger.info(
        "get_stats result | comics=%d fanfics=%d pages=%d chapters=%d active_jobs=%d",
        total_comics, total_fanfics, total_pages_scraped,
        total_chapters_scraped, active_scrape_jobs,
    )

    return StatsResponse(
        total_comics=total_comics,
        total_fanfics=total_fanfics,
        comics_in_progress=comics_in_progress,
        fanfics_in_progress=fanfics_in_progress,
        total_pages_scraped=total_pages_scraped,
        total_chapters_scraped=total_chapters_scraped,
        active_scrape_jobs=active_scrape_jobs,
    )
