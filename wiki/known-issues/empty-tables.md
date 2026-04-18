# Known Issue: Empty Database Tables

> Four tables have 0 records: reading_progress, comic_authors, comic_tags, tags.

**Discovered:** 2026-03-29
**Source:** `scratchpad/claude-2026-03-29-empty-tables-investigation.md`

## Affected Tables

| Table | Records | Expected |
|-------|---------|----------|
| reading_progress | 0 | Should have entries for every story read |
| comic_authors | 0 | Should have author links for scraped comics |
| comic_tags | 0 | Should have tag links for scraped comics |
| tags | 0 | Should have tag entries from comic scrapes |

## Current State

- 18 comics in DB, all from hentai20, all status=complete
- 6 authors exist in `authors` table (all from fanfic scrapes, not comics)
- Scrape logs confirm: `authors=0 tags=0` for every hentai20 metadata fetch

## Root Causes

### 1. comic_authors, comic_tags, tags: Hentai20 CSS Selector Mismatch

The Hentai20Scraper assumes Madara WordPress theme selectors:
- `.author-content a` for authors
- `.genres-content a` and `.tags-content a` for tags

But hentai20.io uses a **different WordPress theme**:
- Author is in `<table class="infotable"> → <span itemprop="author"><i itemprop="name">...</i></span>`
- Genres are not on the manga detail page

**Fix needed:** Update `Hentai20Scraper.get_story_metadata()`:
```python
# Author
soup.select_one('span[itemprop="author"] i[itemprop="name"]')
# Genres: may not exist on detail page — investigate
```

After fix, re-scrape existing comics to populate metadata.

### 2. reading_progress: Partially Fixed

Backend endpoints work:
- `PUT /progress/comic/{story_id}` → progress_service.upsert
- `PUT /progress/fanfic/{story_id}` → progress_service.upsert

**Comic progress:** ComicReaderView.loadPages() now calls `updateComicProgress` on chapter open (fire-and-forget). Page-level progress synced on chapter open.

**Fanfic progress:** FanficReaderView calls `updateFanficProgress` on both `onAppear` and `onDisappear`, syncing chapter number + scroll offset percent.

**Remaining gap:** Neither reader debounces mid-chapter page turns (comic) or scroll position changes (fanfic) to the backend. Only chapter-open and chapter-close events trigger syncs. The 5s debounce rule from CLAUDE.md is not yet implemented for continuous reading.

## Impact

- **reading_progress empty:** Progress is only stored locally. If SwiftData is wiped, all progress is lost. The GET /progress hydration path works but there's nothing to hydrate from.
- **comic metadata empty:** Comics in library show no authors or tags. Filtering/search by tags doesn't work for comics.
