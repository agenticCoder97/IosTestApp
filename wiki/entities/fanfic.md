# Entity: Fanfic

> Traces the Fanfic entity across every layer of the stack.

## Layer Map

| Layer | Type | File |
|-------|------|------|
| Backend ORM | Fanfic (SQLAlchemy) | `backend/app/models/fanfic.py` |
| Backend Schema | FanficResponse (Pydantic) | `backend/app/schemas/fanfic.py` |
| iOS DTO | FanficResponse (Codable) | `Packages/Networking/.../DTOs/FanficDTOs.swift` |
| iOS Model | LocalFanfic (@Model) | `Packages/Core/.../Models/LocalFanfic.swift` |
| iOS Views | FanficDetailView, FanficReaderView | `Packages/FanficFeature/.../Library/`, `Reader/` |
| iOS ViewModel | FanficLibraryViewModel | `Packages/FanficFeature/.../ViewModels/FanficLibraryViewModel.swift` |

## Data Flow

```mermaid
graph LR
    ORM[Fanfic ORM<br/>backend DB] -->|service query| SCHEMA[FanficResponse<br/>Pydantic schema]
    SCHEMA -->|JSON| DTO[FanficResponse<br/>iOS DTO]
    DTO -->|ViewModel upsert| MODEL[LocalFanfic<br/>SwiftData @Model]
    MODEL -->|bind| VIEW[FanficDetailView /<br/>FanficReaderView]
```

## Field Mapping

| Concept | Backend ORM | iOS DTO | iOS @Model |
|---------|------------|---------|------------|
| Identity | id (UUID PK) | id | id |
| Title | title | title | title |
| Source | source_key | sourceKey | sourceKey |
| Summary | summary | summary | summary |
| Fandom | fandom | fandom | fandom |
| Rating | rating | rating | rating |
| Status | completion_status | completionStatus | completionStatus |
| Word count | word_count | wordCount | wordCount |
| Total chapters | total_chapters | totalChapters | totalChapters |
| Characters | characters | characters | characters |
| Pairing | pairing | pairing | pairing |
| Warnings | warnings | warnings | warnings |
| Published | published_at | publishedAt | publishedAt |
| Authors | fanfic_authors → authors | authors | — (stored on detail view) |
| Chapters | relationship → [FanficChapter] | chapters | @Relationship → [LocalFanficChapter] |
| Favorite | — | — | isFavorite (local-only) |

## Key Observations

- Fanfics have richer metadata than comics (fandom, rating, characters, pairing, warnings, word count).
- **Server-side filtering** supported: fandom, rating, completion_status, sort — passed as query params from FanficFilterView.
- Chapter content (full text) stored in `FanficChapter.content` column in the database, not as files.
- Sources: AO3Scraper, FFNetScraper. FFNet currently missing most metadata fields.
