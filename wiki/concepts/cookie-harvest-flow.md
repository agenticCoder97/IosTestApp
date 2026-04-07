# Cookie Harvest Flow

> How iOS WKWebView cookies are extracted and reused by backend scrapers to bypass Cloudflare.

## Why

Manga/fanfic sites use Cloudflare (or similar) protection. Datacenter IPs are blocked immediately. iOS WKWebView is real Safari — it passes Cloudflare challenges natively. The harvested `cf_clearance` cookie + user-agent lets the backend impersonate that Safari session.

## Flow

```mermaid
sequenceDiagram
    participant User
    participant WKWebView
    participant CookieStore
    participant APIClient
    participant Backend
    participant Redis
    participant Scraper

    User->>WKWebView: Browse source site
    WKWebView->>WKWebView: Cloudflare challenge (auto-solve)
    WKWebView->>CookieStore: webView(_:didFinish:) → filterCookies()
    Note over CookieStore: Maps source key → domain<br/>"ao3" → "archiveofourown.org"
    CookieStore->>CookieStore: Persist to UserDefaults

    User->>APIClient: Tap Scrape button
    APIClient->>Backend: POST /scrape with ScrapeRequest<br/>{url, sourceKey, cookies, userAgent}
    Backend->>Redis: Store cookies:{source_key} with TTL 24h
    Backend->>Backend: Enqueue ARQ task

    Scraper->>Redis: _get_cookies(source_key)
    Scraper->>Scraper: _fetch(url) with cookies + UA via curl_cffi
    Note over Scraper: TLS impersonation: chrome120<br/>(safari17_2 unsupported in curl_cffi 0.7.4)

    alt Cookies expired mid-scrape
        Scraper->>Backend: CookieExpiredError
        Backend->>APIClient: HTTP 428
        APIClient->>User: "Browser refresh needed" banner
    end
```

## Key Components

| Component | File | Role |
|-----------|------|------|
| CookieStore | `Packages/Networking/.../CookieStore.swift` | iOS-side: extracts and persists cookies per source domain |
| ScrapeRequest | `Packages/Networking/.../DTOs/ScrapeDTOs.swift` | DTO carrying cookies + userAgent to backend |
| scrape_service | `backend/app/services/scrape_service.py` | Stores cookies in Redis |
| BaseScraper._fetch() | `backend/app/scrapers/base.py` | Reads cookies from Redis, attaches to requests |
| BaseScraper._fetch_via_browser() | `backend/app/scrapers/base.py` | Playwright fallback on repeated 403 |

## Cookie Extraction Trigger

Cookies are extracted on **every** `webView(_:didFinish:)` navigation — not only when the user taps Scrape. This ensures fresh cookies are always available.

## CookieStore Domain Mapping

```swift
// CookieStore.sourceDomains
"nhentai"  → "nhentai.net"
"toongod"  → "toongod.com"   // BUG: should be .org
"hentai20" → "hentai20.io"
"ao3"      → "archiveofourown.org"
"ffnet"    → "fanfiction.net"
```

## TTL

`COOKIE_CACHE_TTL_SECS=86400` (24 hours). After TTL expiry, the next scrape attempt will fail with CookieExpiredError, prompting the user to re-browse and refresh cookies.
