# FFNet chapter text → plain text normalization

**Status:** Approved design, ready for implementation plan.
**Date:** 2026-04-20
**Scope:** Backend only (FFNet scraper paths + one-shot data backfill).
**Out of scope:** iOS reader, AO3 scraper, DB schema, Comic scrapers.

## Problem

Fanfic chapters scraped via the FFNet source contain raw EPUB/XHTML markup
when viewed in the iOS reader — users see literal text like:

```
<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" ...>
  <head/>
  <body><h2>Chapter Title</h2>...</body>
</html>
```

The iOS reader ([`FanficReaderView.swift:531-542`](../../../ios/Astral/Packages/FanficFeature/Sources/FanficFeature/Reader/FanficReaderView.swift:531))
splits `chapterContent` on `\n\n` and renders each block as a plain-text
paragraph. It does not parse HTML. AO3 chapters render correctly because
the AO3 scraper already extracts clean paragraph text
([`ao3.py:214-215`](../../../backend/app/scrapers/fanfic/ao3.py:214)):

```python
paragraphs = [p.get_text(separator=" ", strip=True) for p in content_div.find_all("p")]
return "\n\n".join(p for p in paragraphs if p)
```

FFNet has two scraping paths and both produce dirty output:

- **Primary (FanFicFare)** — [`_fanficfare_runner.py:119`](../../../backend/app/scrapers/fanfic/_fanficfare_runner.py:119)
  stores `adapter.getChapterText(...)` verbatim. FFF returns fragment HTML
  (typically `<h2>Title</h2><div><p>...</p></div>`), which leaks tags if
  any are inline.
- **Fallback (FicHub)** — [`_fichub.py:135`](../../../backend/app/scrapers/fanfic/_fichub.py:135)
  stores the raw `item.get_content().decode(...)` of each EPUB item. Each
  item is a complete XHTML document with XML prolog, DOCTYPE, namespaced
  `<html>` root, `<head/>`, and `<body>`.

## Goal

FFNet chapter content stored in `fanfic_chapters.content` matches the AO3
format: paragraphs separated by `\n\n`, no HTML tags, HTML entities
decoded, inline formatting (bold/italic) lost (acceptable — same as AO3).

## Design

### 1. New shared helper

**File:** `backend/app/scrapers/fanfic/_html_to_text.py`

```python
from bs4 import BeautifulSoup

def html_to_paragraphs(raw: str) -> str:
    """Extract plain-text paragraphs from chapter HTML/XHTML.

    Handles both full XHTML documents (FicHub EPUB items) and fragments
    (FanFicFare adapter output). Returns paragraphs joined by "\\n\\n",
    matching the AO3 scraper's output format so the iOS reader renders
    all fanfic sources identically.
    """
    if not raw:
        return ""
    soup = BeautifulSoup(raw, "lxml")
    root = soup.body if soup.body else soup

    # Drop structural elements and duplicate chapter-title headings.
    # FicHub injects <h2>{chapter_title}</h2> at the top of each body,
    # duplicating fanfic_chapters.title. FFF does similarly with <h2>.
    for tag in root.find_all(["head", "script", "style", "h1", "h2", "h3", "h4"]):
        tag.decompose()

    paragraphs = [
        p.get_text(" ", strip=True)
        for p in root.find_all("p")
        if p.get_text(strip=True)
    ]
    if paragraphs:
        return "\n\n".join(paragraphs)

    # Fallback: no <p> wrapping (rare). Collapse body text with blank-line
    # separators preserved.
    return root.get_text("\n\n", strip=True)
```

**Dependencies:** `bs4` + `lxml` — both already in use by the AO3 scraper.

### 2. Call-site edits (two lines)

**[`_fichub.py:130-137`](../../../backend/app/scrapers/fanfic/_fichub.py:130)** —
inside `_split_epub_bytes`:

```python
# before
html = item.get_content().decode("utf-8", errors="replace")

# after
from app.scrapers.fanfic._html_to_text import html_to_paragraphs
html = html_to_paragraphs(item.get_content().decode("utf-8", errors="replace"))
```

**[`_fanficfare_runner.py:117-120`](../../../backend/app/scrapers/fanfic/_fanficfare_runner.py:117)** —
inside `_fetch_sync`:

```python
# before
html = adapter.getChapterText(chap_url) or ""

# after
from app.scrapers.fanfic._html_to_text import html_to_paragraphs
html = html_to_paragraphs(adapter.getChapterText(chap_url) or "")
```

No other task/model changes needed. `fanfic_scrape_task` already calls
`len(text.split())` on scraper output for word count — cleaned text
yields an accurate count.

### 3. One-shot backfill

**File:** `backend/scripts/backfill_ffnet_chapter_text.py`

Invoked manually inside the worker container:

```bash
docker compose -f docker-compose.local.yml exec arq_worker \
    python -m scripts.backfill_ffnet_chapter_text
```

Behaviour:
- Opens an `AsyncSessionLocal`, streams
  `SELECT id, content FROM fanfic_chapters
   WHERE deleted_at IS NULL
     AND (content LIKE '<?xml%' OR content LIKE '<!DOCTYPE%' OR content LIKE '<html%')`.
- For each row: `new_text = html_to_paragraphs(content)`,
  `new_word_count = len(new_text.split())`.
- Updates `content` and `word_count` in the same row. Commits every 100 rows.
- Prints a summary: rows scanned, rows updated, median word-count before/after.
- Idempotent — cleaned rows no longer match the `LIKE` filter on re-run.
- Safe to interrupt — partial progress persists thanks to batched commits.

No migration, no schema change.

### 4. Tests

**File:** `backend/tests/scrapers/fanfic/test_html_to_text.py`

Cases:
1. Full FicHub XHTML doc with `<?xml>`/`<!DOCTYPE>`/`<html xmlns=...>` →
   returns paragraphs joined by `\n\n`, no tags, `<h2>` dropped.
2. FFF-style fragment (`<h2>Title</h2><div><p>A</p><p>B</p></div>`) →
   `"A\n\nB"`, `<h2>` dropped.
3. Self-closing `<p/>` and trailing empty `<div>` filtered out.
4. HTML entities decoded: `<p>foo &amp; bar &#8212; baz</p>` →
   `"foo & bar — baz"`.
5. Inline tags stripped to text: `<p><strong>bold</strong> and <em>ital</em></p>` →
   `"bold and ital"`.
6. Empty input (`""`, `None`) → `""`.
7. Body with no `<p>` tags, only raw text + `<br>` → fallback path returns
   the body text.
8. Scene/time break paragraph preserved as text:
   `<p><strong> - Keira - 15/08/1994 -</strong></p>` → `"- Keira - 15/08/1994 -"`.

Tests run via existing pytest setup (`pytest.ini` is already volume-mounted).

## Behavioural changes

| Scenario | Before | After |
|---|---|---|
| New FFNet scrape (FFF path) | Fragment HTML stored | Plain text stored |
| New FFNet scrape (FicHub path) | Full XHTML doc stored | Plain text stored |
| Existing FFNet chapter in DB | Markup visible in reader | Backfill cleans after run |
| AO3 scrape | Plain text (unchanged) | Plain text (unchanged) |
| Comic chapters | N/A (uses pages table) | N/A |
| Word count on new scrapes | Inflated by tag tokens (`xmlns`, etc.) | Accurate |
| `validate_chapter_content` rejections | Rare false-passes from tag noise | Accurate against prose |

## Known limitations (explicit non-goals)

- Inline formatting (bold, italic, underline) is discarded — consistent
  with AO3 today.
- `<hr>` scene-break tags produce no text equivalent — consistent with
  AO3. Authors who use `***` or `---` in-text still get scene-break
  detection in the reader.
- FFNet "Author's Notes" at chapter end are not stripped. FFNet has no
  reliable marker distinguishing AN from prose. AO3 only strips AN
  because it is explicitly marked as `.end-notes`.
- `<h2>`/`<h3>`/`<h4>` used mid-chapter by the author (rare on FFNet;
  FFNet's rich-text editor does not support them) would be dropped.

## Risks

- **BeautifulSoup parse cost** — adds ~1–5 ms per chapter. Negligible
  against per-chapter fetch times (seconds).
- **Backfill duration** — linear in dirty-row count. Expected to be a
  few thousand rows max; batched commits keep memory bounded.
- **Irreversible** — backfill overwrites source HTML. Mitigated by the
  scrape job model: users can always re-scrape, and the source is
  preserved in FicHub / FFNet itself. Acceptable.
