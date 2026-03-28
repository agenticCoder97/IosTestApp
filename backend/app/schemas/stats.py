from pydantic import BaseModel


class StatsResponse(BaseModel):
    total_comics: int
    total_fanfics: int
    comics_in_progress: int
    fanfics_in_progress: int
    total_pages_scraped: int
    total_chapters_scraped: int
    active_scrape_jobs: int
