from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field
from pathlib import Path
from typing import Optional


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str
    oracle_wallet_path: Optional[str] = None
    oracle_wallet_password: Optional[str] = None

    redis_url: str = "redis://localhost:6379/0"
    block_volume_path: str = "/tmp/astral-media"
    static_base_url: str = "http://localhost:8000/static"

    duckdns_token: Optional[str] = None
    duckdns_domain: Optional[str] = None

    arq_max_jobs: int = 3
    soft_delete_days: int = 5
    cookie_cache_ttl_secs: int = 86400
    log_level: str = "INFO"

    # Scrape concurrency — chapters and pages downloaded in parallel
    scrape_chapter_concurrency: int = 4   # how many chapters scraped at once
    scrape_page_concurrency: int = 8      # how many page images downloaded at once per chapter

    @property
    def oracle_wallet_dir(self) -> Optional[Path]:
        if self.oracle_wallet_path:
            return Path(self.oracle_wallet_path).parent
        return None

    @property
    def is_oracle(self) -> bool:
        return self.database_url.startswith("oracle+oracledb://")


settings = Settings()
