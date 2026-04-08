from enum import Enum


class SourceKey(str, Enum):
    NHENTAI = "nhentai"
    TOONGOD = "toongod"
    HENTAI20 = "hentai20"
    AO3 = "ao3"
    FFNET = "ffnet"


class ContentType(str, Enum):
    COMIC = "comic"
    FANFIC = "fanfic"


class ScrapeStatus(str, Enum):
    PENDING = "pending"
    SCRAPED = "scraped"
    FAILED = "failed"


class JobStatus(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    PARTIAL = "partial"
    COMPLETE = "complete"
    FAILED = "failed"


class JobType(str, Enum):
    INITIAL = "initial"
    DELTA = "delta"
    RETRY = "retry"


class ArchiveStatus(str, Enum):
    NONE = "none"
    ARCHIVING = "archiving"
    ARCHIVED = "archived"
    UNARCHIVING = "unarchiving"


SOURCE_RATE_CONFIG: dict[str, dict] = {
    SourceKey.NHENTAI:  {"delay": 1.5, "max_retries": 3, "requires_browser": False},
    SourceKey.TOONGOD:  {"delay": 1.0, "max_retries": 3, "requires_browser": False},
    SourceKey.HENTAI20: {"delay": 2.0, "max_retries": 3, "requires_browser": True},
    SourceKey.AO3:      {"delay": 2.0, "max_retries": 3, "requires_browser": False},
    SourceKey.FFNET:    {"delay": 1.5, "max_retries": 3, "requires_browser": False},
}

COOKIE_CACHE_KEY_PREFIX = "cookies:"
