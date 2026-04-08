# Data Flow

> End-to-end flow of content from external sources through the backend into the iOS app.

## Scrape-to-Library Flow

```mermaid
graph LR
    subgraph "iOS"
        WK[WKWebView] -->|cookies + UA| BR[BrowserView]
        BR -->|POST /scrape| API[APIClient]
    end

    subgraph "Backend API"
        API -->|ScrapeRequest| SR[scrape router]
        SR --> SS[scrape_service]
        SS -->|create placeholder| DB[(Database)]
        SS -->|store cookies| REDIS[(Redis)]
        SS -->|enqueue job_id| ARQ[ARQ Queue]
    end

    subgraph "ARQ Worker"
        ARQ --> TASK[scrape_task]
        TASK -->|get cookies| REDIS
        TASK -->|fetch HTML| EXT[External Site]
        TASK -->|parse| BS4[BeautifulSoup]
        TASK -->|download images| BV[(Block Volume)]
        TASK -->|persist metadata| DB
        TASK -->|update status| DB
    end

    subgraph "iOS Library"
        LIB[LibraryViewModel] -->|GET /comics or /fanfic| API2[APIClient]
        API2 -->|response| LIB
        LIB -->|upsert| SD[(SwiftData)]
        LIB --> VIEW[LibraryView]
    end

    subgraph "iOS Reader"
        VIEW -->|navigate| READER[ReaderView]
        READER -->|GET .../pages| API3[APIClient]
        API3 -->|PageResponse| READER
        READER -->|AsyncImage| NGINX[Nginx /static/]
        NGINX --> BV
    end
```

## Reading Progress Flow

```mermaid
graph LR
    READER[ReaderView] -->|write locally| SD[(SwiftData)]
    READER -->|PUT /progress/:id| API[APIClient]
    API --> PS[progress_service]
    PS -->|upsert| DB[(Database)]

    LIB[LibraryViewModel] -->|GET /progress| API
    API --> PS
    PS -->|query| DB
    LIB -->|hydrate| SD
```

**Known gap:** ComicReaderView and FanficReaderView write progress to SwiftData locally but the PUT call to the backend is not consistently wired up. See [known-issues/empty-tables.md](../known-issues/empty-tables.md).

## Image Serving Flow

1. Backend scrape task downloads images to block volume at `/mnt/astral-media/comics/{comic_id}/{chapter_id}/page_{n}.jpg`
2. Nginx serves `/static/` mapped to the block volume
3. iOS `ComicPageView` constructs URL: `AppConfig.staticBaseURL + page.filePath`
4. `AsyncImage` loads from that URL

**Critical:** `AppConfig.staticBaseURL` must end with a trailing `/` — without it, URLs become `/staticcomics/...` (404).

## Cookie Lifecycle

1. User opens BrowserView → WKWebView loads source site
2. On every `webView(_:didFinish:)`, cookies are extracted via `WKWebView.configuration.websiteDataStore`
3. `CookieStore.filterCookies()` maps source key (e.g., "ao3") to domain ("archiveofourown.org")
4. When user taps Scrape, cookies + user-agent are sent in `ScrapeRequest`
5. Backend stores cookies in Redis with TTL (`COOKIE_CACHE_TTL_SECS=86400`)
6. Scraper's `_fetch()` reads cookies from Redis, attaches to curl_cffi requests
7. If cookies expire mid-scrape, `CookieExpiredError` → HTTP 428 → iOS shows "Browser refresh needed"
