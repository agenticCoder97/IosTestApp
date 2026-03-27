import asyncio
from typing import Optional
from contextlib import asynccontextmanager

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
    async with get_semaphore():
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            try:
                yield browser
            finally:
                await browser.close()
