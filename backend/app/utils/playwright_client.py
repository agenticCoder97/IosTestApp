import asyncio
import logging
from typing import Optional
from contextlib import asynccontextmanager

logger = logging.getLogger(__name__)

_semaphore: Optional[asyncio.Semaphore] = None
MAX_BROWSER_INSTANCES = 2


def get_semaphore() -> asyncio.Semaphore:
    global _semaphore
    if _semaphore is None:
        _semaphore = asyncio.Semaphore(MAX_BROWSER_INSTANCES)
    return _semaphore


@asynccontextmanager
async def acquire_browser():
    """Context manager that acquires a Playwright browser slot (max 2 concurrent)."""
    from playwright.async_api import async_playwright
    sem = get_semaphore()
    logger.info("acquire_browser waiting for slot | max_instances=%d", MAX_BROWSER_INSTANCES)
    async with sem:
        logger.info("acquire_browser slot acquired")
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            logger.info("acquire_browser browser launched")
            try:
                yield browser
            finally:
                await browser.close()
                logger.info("acquire_browser browser closed, slot released")
