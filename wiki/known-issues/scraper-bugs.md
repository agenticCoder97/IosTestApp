# Known Issue: Scraper Bugs

> Per-scraper bugs and missing functionality discovered during testing.

**Discovered:** 2026-03-28
**Source:** `scratchpad/claude-2026-03-28-scraping-improvements.md`

## Toongod Domain Change

- **Bug:** Domain changed from `toongod.com` → `toongod.org`
- **Impact:** CookieStore maps `"toongod"` → `"toongod.com"` — cookies won't match
- **Impact:** iOS browser URL hardcoded to `https://www.toongod.com`
- **Fix:** Update domain in CookieStore + browser source URLs

## Toongod Slug Extraction

- **Bug:** `_slug()` regex only handles `/webtoon/` URLs, crashes on `/manga/`
- **Impact:** iOS `evaluateCanScrape` allows both `/manga/` and `/webtoon/` but backend can't parse `/manga/` URLs
- **Fix:** Update regex to handle both patterns

## FFNet Missing Metadata — RESOLVED

- **Status:** Fixed (2026-04-07)
- **Was:** FFNetScraper only extracted title, author, description, total_chapters
- **Fix:** Rewrote metadata parsing to split `#profile_top span.xgray` on ` - ` into segments. Now extracts: rating, language, genre (as tags), characters, word count, Reviews (→ comments_count), Favs (→ kudos), Follows (→ bookmarks_count), dates from `span[data-xutime]`, completion status, fandom from breadcrumb (including crossovers).
- **Verified:** Playwright-tested against 3 FFNet stories with different structures (complete/ongoing, crossover, single-genre)

## Hentai20 Missing Authors/Tags

- **Bug:** CSS selectors don't match actual page structure (different WordPress theme)
- **Impact:** All 18 comics have empty authors[] and tags[]
- **Details:** See [empty-tables.md](empty-tables.md)

## AO3 — Verified Working

All CSS selectors verified correct as of 2026-03-28:
- `h2.title.heading` — title
- `h3.byline.heading a[rel='author']` — author
- `.summary blockquote` — summary
- `dd.rating.tags`, `dd.fandom.tags`, `dd.relationship.tags`, `dd.character.tags` — metadata
- `dd.warning.tags`, `dd.freeform.tags` — additional tags
- `dd.words`, `dd.published`, `dd.status`, `dd.chapters` — stats
