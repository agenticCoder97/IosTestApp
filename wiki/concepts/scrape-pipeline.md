# Scrape Pipeline

> Complete lifecycle of a scrape job from user tap to content appearing in the library.

## End-to-End Flow

```mermaid
graph TB
    subgraph "1. Initiation (iOS)"
        BROWSE[User browses source in BrowserView] --> COOKIES[Cookies extracted on every page load]
        COOKIES --> TAP[User taps Scrape]
        TAP --> POST[POST /scrape/comic or /fanfic<br/>ScrapeRequest: url, sourceKey, cookies, userAgent]
    end

    subgraph "2. Job Creation (Backend API)"
        POST --> SS[scrape_service.initiate_scrape]
        SS --> PLACEHOLDER[Create placeholder Comic/Fanfic if new]
        SS --> STORE_COOKIES[Store cookies in Redis]
        SS --> CREATE_JOB[Create ScrapeJob, status=queued]
        SS --> ENQUEUE[Enqueue ARQ task]
        SS --> RESPONSE[Return ScrapeJobResponse to iOS]
    end

    subgraph "3. Execution (ARQ Worker)"
        ENQUEUE --> WORKER[Worker picks up job]
        WORKER --> REGISTRY[SCRAPER_REGISTRY[source_key]]
        REGISTRY --> META[scraper.get_story_metadata]
        META --> PERSIST[Persist: title, thumbnail, metadata → ORM]
        PERSIST --> AUTHORS[Upsert authors]
        AUTHORS --> TAGS[Upsert tags]
        TAGS --> CH_LIST[scraper.get_chapter_list]
        CH_LIST --> CH_ROWS[Create chapter rows, scrape_status=pending]
        CH_ROWS --> PARALLEL[Parallel per-chapter loop]
    end

    subgraph "4a. Comic Chapter Scraping"
        PARALLEL --> PAGES[scraper.get_chapter_pages]
        PAGES --> DOWNLOAD[Download images to block volume]
        DOWNLOAD --> PAGE_ROWS[Create Page ORM rows with file_path]
    end

    subgraph "4b. Fanfic Chapter Scraping"
        PARALLEL --> TEXT[scraper.get_chapter_text]
        TEXT --> CONTENT[Store text in FanficChapter.content]
    end

    subgraph "5. Completion"
        PAGE_ROWS --> STATUS[Update chapter scrape_status]
        CONTENT --> STATUS
        STATUS --> JOB_UPDATE[Update ScrapeJob counters]
        JOB_UPDATE --> LOG[Write ScrapeLog entries]
        LOG --> FINAL[Set final status: complete/partial/failed]
    end

    subgraph "6. Library Refresh (iOS)"
        FINAL --> POLL[iOS polls or opens library]
        POLL --> FETCH[GET /comics or /fanfic]
        FETCH --> UPSERT[ViewModel upserts into SwiftData]
        UPSERT --> DISPLAY[Content appears in library]
    end
```

## Concurrency Control

- `chapter_sem`: asyncio.Semaphore limiting parallel chapter scraping
- `page_sem`: asyncio.Semaphore limiting parallel page downloads within a chapter
- Configured via `SCRAPE_CHAPTER_CONCURRENCY` and `SCRAPE_PAGE_CONCURRENCY` env vars

## Per-Chapter Checkpointing

Each chapter has its own `scrape_status` (pending/scraped/failed). This means:
- If chapter 10 fails but 11-15 succeed, only chapter 10 is retried
- No redundant re-scraping of already-scraped chapters
- Retry queries: `WHERE scrape_status IN ('failed', 'pending')`

## Job Types

| Type | When | What happens |
|------|------|-------------|
| initial | First scrape of a story | All chapters scraped |
| delta | auto_update_task or manual | Only new chapters (not yet in DB) |
| retry | User hits retry | Only failed/pending chapters |

## Error Handling

| Error | Response | iOS Behavior |
|-------|----------|-------------|
| CookieExpiredError | HTTP 428 | "Browser refresh needed" banner |
| Rate limited (429/503) | Exponential backoff + jitter | Job continues after backoff |
| Max retries exhausted | ScraperError | Chapter marked failed, job continues |
| Fatal error | Job status = failed | User can retry from ScrapesView |
