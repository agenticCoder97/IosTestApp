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

## FFNet Missing Metadata

- **Bug:** FFNetScraper only extracts: title, author, description, total_chapters
- **Missing:** Rating, language, genre (→ tags), characters, word count, published date, updated date, completion status
- **Impact:** FFNet fanfics appear in library with no fandom, rating, word count, dates
- **Note:** All this metadata IS present in the page's metadata line — scraper just doesn't parse it
- **Fix:** Parse the metadata line using the existing format (pipe-separated values)

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
