# Networking Package

> APIClient, endpoint definitions, cookie management, and all DTO types. Depends on Core.

## Entities

### Core Networking

| Name | Type | File | Description |
|------|------|------|-------------|
| APIClient | Actor (singleton) | `Packages/Networking/.../APIClient.swift` | async/await URLSession wrapper. `request<T: Decodable>()` and `requestVoid()`. JSON decoding with snake_case key strategy. Handles 428 (cookie refresh), 404, 429, 5xx. |
| APIError | Enum | `Packages/Networking/.../APIClient.swift` | invalidResponse, cookieRefreshNeeded, notFound, rateLimited, serverError, httpError(Int), encodingFailed, invalidURL |
| Endpoint | Struct | `Packages/Networking/.../Endpoints.swift` | method (HTTPMethod), path, queryItems, body. `urlRequest()` builds full URL from AppConfig.apiBaseURL + path. |
| HTTPMethod | Enum | `Packages/Networking/.../Endpoints.swift` | GET, POST, PUT, PATCH, DELETE |
| CookieStore | Class (singleton) | `Packages/Networking/.../CookieStore.swift` | sourceDomains mapping dict ("ao3" → "archiveofourown.org"). storeCookies/getCookies/filterCookies. UserDefaults persistence with TTL enforcement. |

### Endpoint Catalog

| Group | Static Method | HTTP | Path | Body/Query |
|-------|-------------|------|------|------------|
| Comics | `.comics(page:pageSize:sort:)` | GET | `/comics` | page, page_size, sort |
| Comics | `.comicDetail(id:)` | GET | `/comics/{id}` | — |
| Comics | `.chapterPages(comicId:chapterId:)` | GET | `/comics/{comicId}/chapters/{chapterId}/pages` | — |
| Comics | `.updateComic(id:body:)` | PATCH | `/comics/{id}` | ComicUpdateRequest |
| Comics | `.deleteComic(id:)` | DELETE | `/comics/{id}` | — |
| Fanfic | `.fanfics(page:pageSize:fandom:rating:completionStatus:sort:)` | GET | `/fanfic` | page, page_size, fandom, rating, completion_status, sort |
| Fanfic | `.fanficDetail(id:)` | GET | `/fanfic/{id}` | — |
| Fanfic | `.fanficChapter(fanficId:chapterId:)` | GET | `/fanfic/{fanficId}/chapters/{chapterId}` | — |
| Fanfic | `.deleteFanfic(id:)` | DELETE | `/fanfic/{id}` | — |
| Authors | `.authorDetail(id:)` | GET | `/authors/{id}` | — |
| Scrape | `.initiateScrape(_:)` | POST | `/scrape/comic` or `/scrape/fanfic` | ScrapeRequest |
| Scrape | `.scrapeStatus(jobId:)` | GET | `/scrape/{jobId}` | — |
| Scrape | `.retryScrape(jobId:)` | POST | `/scrape/{jobId}/retry` | — |
| Scrape | `.deltaUpdate(storyId:)` | POST | `/scrape/{storyId}/update` | — |
| Scrape | `.allScrapeJobs(page:pageSize:)` | GET | `/scrape` | page, page_size |
| Scrape | `.scrapeJobLogs(jobId:)` | GET | `/scrape/{jobId}/logs` | — |
| Progress | `.updateComicProgress(storyId:body:)` | PUT | `/progress/comic/{storyId}` | ComicProgressRequest |
| Progress | `.updateFanficProgress(storyId:body:)` | PUT | `/progress/fanfic/{storyId}` | FanficProgressRequest |
| Progress | `.getProgress(type:storyId:)` | GET | `/progress/{type}/{storyId}` | — |
| Progress | `.allProgress(contentType:)` | GET | `/progress` | content_type |
| Health | `.health` | GET | `/health` | — |

### DTOs (Codable Structs)

| Name | File | Direction | Key Fields |
|------|------|-----------|------------|
| ComicResponse | `DTOs/ComicDTOs.swift` | Backend→iOS | id, title, sourceKey, sourceUrl, thumbnailPath, totalChapters, status, category, authors, tags, chapters |
| ComicChapterResponse | `DTOs/ComicDTOs.swift` | Backend→iOS | id, chapterNumber, totalPages, scrapeStatus |
| PageResponse | `DTOs/ComicDTOs.swift` | Backend→iOS | id, filePath, pageNumber, widthPx, heightPx |
| ComicUpdateRequest | `DTOs/ComicDTOs.swift` | iOS→Backend | isFavorite, category, skipFirstNPages |
| TagResponse | `DTOs/ComicDTOs.swift` | Backend→iOS | id, name, tagType |
| FanficResponse | `DTOs/FanficDTOs.swift` | Backend→iOS | id, title, sourceKey, sourceUrl, summary, fandom, rating, completionStatus, wordCount, totalChapters, characters, pairing, warnings, authors, chapters |
| FanficChapterResponse | `DTOs/FanficDTOs.swift` | Backend→iOS | id, chapterNumber, wordCount, content (optional) |
| ScrapeRequest | `DTOs/ScrapeDTOs.swift` | iOS→Backend | url, sourceKey, cookies, userAgent, contentType |
| ScrapeJobResponse | `DTOs/ScrapeDTOs.swift` | Backend→iOS | id, contentType, storyId, status, chaptersScraped, chaptersFailed, totalChapters, sourceUrl, sourceKey, jobType, errorMessage, currentStep, lastErrorType |
| ScrapeLogEntry | `DTOs/ScrapeDTOs.swift` | Backend→iOS | timestamp, level, message, step, errorType |
| CookieDTO | `DTOs/CookieDTO.swift` | iOS→Backend | name, value, domain |
| ComicProgressRequest | `DTOs/ProgressDTOs.swift` | iOS→Backend | lastChapterNumber, lastPageNumber |
| FanficProgressRequest | `DTOs/ProgressDTOs.swift` | iOS→Backend | lastChapterNumber, scrollOffsetPercent |
| ProgressResponse | `DTOs/ProgressDTOs.swift` | Backend→iOS | storyId, contentType, lastChapterNumber, lastPageNumber, scrollOffsetPercent |
| PaginatedResponse\<T\> | `DTOs/SharedDTOs.swift` | Backend→iOS | items, total, page, pageSize, totalPages, hasNext |
| AuthorResponse | `DTOs/SharedDTOs.swift` | Backend→iOS | id, name |
| HealthResponse | `DTOs/SharedDTOs.swift` | Backend→iOS | status |

## Relationships

| From | To | Type | Description |
|------|-----|------|-------------|
| APIClient | Endpoint | uses | Builds URLRequest via endpoint.urlRequest() |
| APIClient | AppConfig | reads | apiBaseURL for all requests |
| Endpoint | AppConfig | reads | apiBaseURL in urlRequest() |
| CookieStore | UserDefaults | persists | "com.astral.cookies" suite |
| ComicFeature | APIClient | calls | All comic API operations |
| FanficFeature | APIClient | calls | All fanfic API operations |
| BrowserViews | CookieStore | writes | On every webView didFinish navigation |
