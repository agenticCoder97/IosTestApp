# Core Package

> SwiftData @Model classes, app configuration, and shared utilities. No external dependencies.

## Entities

### SwiftData Models

| Name | File | Key Fields | Relationships |
|------|------|------------|---------------|
| LocalComic | `Packages/Core/.../Models/LocalComic.swift` | id (UUID), title, sourceKey, thumbnailPath, totalChapters, status, isFavorite, category, tagsJSON, authorsJSON, skipFirstNPages, lastReadChapterNumber, lastReadPageNumber, progressPercent, lastReadAt, completedAt | @Relationship(cascade) → [LocalComicChapter] |
| LocalComicChapter | `Packages/Core/.../Models/LocalComicChapter.swift` | id (UUID), comicId, chapterNumber (Double), totalPages, isDownloaded, scrapeStatus, localPagesPath | inverse → LocalComic |
| LocalFanfic | `Packages/Core/.../Models/LocalFanfic.swift` | id (UUID), title, sourceKey, summary, fandom, rating, completionStatus, wordCount, totalChapters, isFavorite, characters, pairing, warnings, publishedAt, completedAt | @Relationship(cascade) → [LocalFanficChapter] |
| LocalFanficChapter | `Packages/Core/.../Models/LocalFanficChapter.swift` | id (UUID), fanficId, chapterNumber (Double), wordCount, isDownloaded, localTextPath, scrapeStatus | inverse → LocalFanfic |
| LocalAuthor | `Packages/Core/.../Models/LocalAuthor.swift` | id (UUID), name, updatedAt | — |
| LocalScrapeJob | `Packages/Core/.../Models/LocalScrapeJob.swift` | id (UUID), contentType, storyId (polymorphic), status, chaptersScraped, chaptersFailed, totalChapters, sourceUrl, sourceKey, jobType, errorMessage, currentStep, lastErrorType | logical FK via storyId + contentType |
| LocalBookmark | `Packages/Core/.../Models/LocalBookmark.swift` | id (UUID), contentType, storyId, chapterNumber, pageNumber, scrollPercent, note, wordOffset, selectedText, heading | logical FK via storyId + contentType |
| LocalReadingSession | `Packages/Core/.../Models/LocalReadingSession.swift` | id (UUID), contentType, storyId, startedAt, endedAt, chaptersRead | logical FK via storyId + contentType |
| UserPreferences | `Packages/Core/.../Models/UserPreferences.swift` | comicScrollDirection, fanficFontSize, fanficLineHeight, fanficBackground, readerBrightness | singleton pattern |

### Utilities

| Name | Type | File | Description |
|------|------|------|-------------|
| AppConfig | Static enum | `Packages/Core/.../Utilities/AppConfig.swift` | apiBaseURL, staticBaseURL (conditional: simulator→localhost, debug→WiFi IP, release→duckdns). downloadLimitPerTabBytes, progressDebounceSeconds, cookieCacheTTLSeconds. |
| AstralLogger | Utility | `Packages/Core/.../Utilities/AstralLogger.swift` | Structured logging: .info(), .warning(), .error() with context strings |
| ContentType | Enum | `Packages/Core/.../Utilities/ContentType.swift` | .comic, .fanfic |
| TimeFilter | Enum | `Packages/Core/.../Utilities/TimeFilter.swift` | Time-based filtering for stats views |
| PreviewMocks | Factory | `Packages/Core/.../PreviewMocks.swift` | @MainActor factory for SwiftUI preview mock data |

## SwiftData Gotchas

- **Never name a @Model property `description`** — conflicts with `CustomStringConvertible`. Use `comicDescription`, `fanficDescription`.
- **`@Attribute(.unique)`** used instead of `#Unique` macro (iOS 17.2 compat).
- **`chapterNumber` is Double**, not Int — some sources use fractional chapter numbers (e.g., 10.5).
- **Polymorphic FKs** (storyId + contentType) — LocalScrapeJob, LocalBookmark, LocalReadingSession reference either comics or fanfics.

## Device Targeting (AppConfig)

```
#if targetEnvironment(simulator)  → localhost:8000
#elseif DEBUG                     → 192.168.0.108:8000 (Mac WiFi IP)
#else                             → astral-reader.duckdns.org
```
