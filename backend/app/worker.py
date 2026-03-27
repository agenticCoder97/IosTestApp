from arq import cron
from arq.connections import RedisSettings
from app.core.config import settings
from app.tasks.comic_scrape_task import comic_scrape_task
from app.tasks.fanfic_scrape_task import fanfic_scrape_task
from app.tasks.cleanup_task import cleanup_task


class WorkerSettings:
    functions = [comic_scrape_task, fanfic_scrape_task]
    cron_jobs = [cron(cleanup_task, hour=3, minute=0)]
    max_jobs = settings.arq_max_jobs
    redis_settings = RedisSettings.from_dsn(settings.redis_url)
