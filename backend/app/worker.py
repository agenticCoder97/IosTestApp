import logging
from arq import cron
from arq.connections import RedisSettings
from app.core.config import settings
from app.core.logging_config import configure_logging
from app.tasks.comic_scrape_task import comic_scrape_task
from app.tasks.fanfic_scrape_task import fanfic_scrape_task
from app.tasks.cleanup_task import cleanup_task

# Configure logging at import time — arq starts via CLI so main.py never runs
configure_logging()
logger = logging.getLogger(__name__)


async def startup(ctx: dict) -> None:
    logger.info(
        "arq_worker startup | max_jobs=%d job_timeout=%ds redis=%s",
        settings.arq_max_jobs,
        3600,
        settings.redis_url,
    )


async def shutdown(ctx: dict) -> None:
    logger.info("arq_worker shutdown")


class WorkerSettings:
    functions = [comic_scrape_task, fanfic_scrape_task]
    cron_jobs = [cron(cleanup_task, hour=3, minute=0)]
    on_startup = startup
    on_shutdown = shutdown
    max_jobs = settings.arq_max_jobs
    redis_settings = RedisSettings.from_dsn(settings.redis_url)
    job_timeout = 3600  # 1 hour — multi-chapter comics with 2s/image delays can easily exceed 300s
