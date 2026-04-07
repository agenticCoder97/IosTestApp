# Architecture Overview

> Astral is a private, single-user iOS reading app for manga/manhwa comics and fan fiction. Backend runs on OCI Free Tier.

## System Diagram

```mermaid
graph TB
    subgraph "iOS App — SwiftUI + SwiftData"
        APP[AstralApp] --> RV[RootView]
        RV --> CT[ComicTabView]
        RV --> FT[FanficTabView]

        CT --> CLV[ComicLibraryView]
        CT --> CRV[ComicReaderView]
        CT --> CBV[ComicBrowserView]
        CT --> CSV[ComicScrapesView]
        CT --> STV[StatsView]

        FT --> FLV[FanficLibraryView]
        FT --> FRV[FanficReaderView]
        FT --> FBV[FanficBrowserView]
        FT --> FSV[FanficScrapesView]
        FT --> FSTV[FanficStatsView]

        CLV --> CLVM[ComicLibraryViewModel]
        FLV --> FLVM[FanficLibraryViewModel]

        CLVM --> API[APIClient]
        FLVM --> API
        CBV --> CS[CookieStore]
        FBV --> CS
        CBV --> API
        FBV --> API

        CLVM --> SD[(SwiftData)]
        FLVM --> SD
    end

    API -->|HTTPS| NGINX[Nginx :443]

    subgraph "Backend — FastAPI + ARQ on OCI ARM VM"
        NGINX -->|proxy| FA[FastAPI :8000]
        FA --> CR[comics router]
        FA --> FR[fanfic router]
        FA --> SR[scrape router]
        FA --> PR[progress router]
        FA --> STR[stats router]

        CR --> CSvc[comic_service]
        FR --> FSvc[fanfic_service]
        SR --> SSvc[scrape_service]
        PR --> PSvc[progress_service]

        CSvc --> DB[(Oracle ADB / Postgres)]
        FSvc --> DB
        SSvc --> DB
        PSvc --> DB

        SSvc -->|enqueue| REDIS[(Redis)]
        REDIS -->|dequeue| WORKER[ARQ Worker]

        WORKER --> CSCRAPE[comic_scrape_task]
        WORKER --> FSCRAPE[fanfic_scrape_task]
        WORKER --> CLEANUP[cleanup_task]
        WORKER --> AUTO[auto_update_task]

        CSCRAPE --> SCRAPERS{Scrapers}
        FSCRAPE --> SCRAPERS

        SCRAPERS --> NH[NhentaiScraper]
        SCRAPERS --> TG[ToongodScraper]
        SCRAPERS --> H20[Hentai20Scraper]
        SCRAPERS --> AO3[AO3Scraper]
        SCRAPERS --> FFN[FFNetScraper]

        CSCRAPE -->|images| BV[(Block Volume /static/)]
    end

    NGINX -->|serve static| BV
```

## Tech Stack

| Component | Stack |
|-----------|-------|
| iOS App | SwiftUI, iOS 17.2+, SwiftData, URLSession (async/await) |
| Backend API | Python 3.11+, FastAPI, Uvicorn, Nginx |
| Task Queue | ARQ + Redis |
| Database | Oracle ADB Free Tier (prod) / PostgreSQL (local) |
| DB Driver | python-oracledb thin mode (pure Python, ARM64 native) |
| File Storage | OCI Block Volume (200GB) served as `/static/` |
| TLS | Let's Encrypt + DuckDNS subdomain |
| Scraping | curl_cffi (TLS impersonation) + Playwright ARM64 fallback |
| iOS Cookies | WKWebView harvests CF cookies → sent to backend with scrape requests |

## Deployment Topology

- **Single OCI Ampere A1 VM** (4 cores, 24GB RAM)
- **Two Docker Compose stacks:**
  - `docker-compose.yml`: FastAPI + Nginx + Certbot
  - `docker-compose.worker.yml`: ARQ worker + Redis
- **Block volume** mounted at `/mnt/astral-media`, served by Nginx at `/static/`
- **iOS app** sideloaded via Xcode (free Apple developer account, 7-day cert)

## Single-User Trust Model

No authentication layer. The backend is accessible only from the personal iPhone and local dev machine. This is intentional for a private sideloaded app.

## Key Architecture Decisions

| Decision | Rationale |
|----------|-----------|
| Cookie-Harvest scraping | iOS WKWebView (real Safari) passes Cloudflare natively. Cookies reused server-side. |
| ARQ over Celery | Scraping is I/O-bound. ARQ is asyncio-native, uses Redis only, lighter than Celery. |
| Block Volume over Object Storage | OCI Object Storage free tier caps at 20GB. Block volume gives 200GB. |
| SwiftData for local state | Native SwiftUI integration. Server DB is always source of truth. |
| Per-chapter scrape_status | Replaced single integer checkpoint. Handles non-linear failures correctly. |
| HTTPS from day one | Free with Let's Encrypt + DuckDNS. No ATS exceptions needed. |
