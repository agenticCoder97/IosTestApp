# FFNet Chapter Text Plaintext Normalization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make FFNet-scraped chapter content render cleanly in the iOS reader by stripping EPUB/XHTML markup down to paragraph-separated plain text, matching the AO3 scraper's output shape.

**Architecture:** One new helper module (`_html_to_text.py`) applied at the two FFNet entry points that currently produce raw markup — FicHub EPUB splitting and the FanFicFare runner. A one-shot backfill script cleans existing dirty rows in-place. No schema changes, no changes to iOS, AO3, or comic paths.

**Tech Stack:** Python 3.11, BeautifulSoup 4 + lxml (already used by AO3 scraper), SQLAlchemy async (existing pattern), pytest with `asyncio_mode = auto`.

**Linear:** [AST-41](https://linear.app/nnetraganti/issue/AST-41/normalize-ffnet-chapter-text-to-plain-text-strip-epubxhtml-markup)
**Spec:** [`docs/superpowers/specs/2026-04-20-ffnet-chapter-text-plaintext-design.md`](../specs/2026-04-20-ffnet-chapter-text-plaintext-design.md)

---

## File Structure

**Create:**
- `backend/app/scrapers/fanfic/_html_to_text.py` — single public function `html_to_paragraphs(raw: str) -> str`.
- `backend/tests/scrapers/fanfic/test_html_to_text.py` — unit tests for the helper.
- `backend/scripts/backfill_ffnet_chapter_text.py` — one-shot backfill for dirty rows.

**Modify:**
- `backend/app/scrapers/fanfic/_fichub.py` — wrap `item.get_content().decode(...)` in `_split_epub_bytes` with the helper.
- `backend/app/scrapers/fanfic/_fanficfare_runner.py` — wrap `adapter.getChapterText(...)` in `_fetch_sync` with the helper.

**Unchanged:**
- `backend/app/scrapers/fanfic/ao3.py` (already produces the same shape)
- `backend/app/tasks/fanfic_scrape_task.py` (`len(text.split())` word count still correct)
- `backend/app/models/fanfic.py`, migrations, iOS reader
- `backend/tests/scrapers/fanfic/test_fichub_client.py`, `test_fanficfare_runner.py` — existing integration-style tests may need fixture updates if they assert on raw-HTML output. Task 4 handles this.

---

## Task 1: Helper module `html_to_paragraphs`

**Files:**
- Create: `backend/app/scrapers/fanfic/_html_to_text.py`
- Test: `backend/tests/scrapers/fanfic/test_html_to_text.py`

Inside the worker container (`backend-arq_worker-1`), pytest runs with `asyncio_mode = auto` via the volume-mounted `pytest.ini`. Tests are sync functions with `def test_*`.

- [ ] **Step 1: Write the failing tests**

Create `backend/tests/scrapers/fanfic/test_html_to_text.py`:

```python
"""Unit tests for html_to_paragraphs — AST-41.

Pins that FFNet chapter text (EPUB XHTML from FicHub, fragment HTML from
FanFicFare) gets reduced to the same plain-text-paragraphs shape the iOS
reader expects (same format as AO3 scraper output).
"""
from app.scrapers.fanfic._html_to_text import html_to_paragraphs


def test_full_fichub_xhtml_document():
    raw = """<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
  <head/>
  <body><h2>Chapter One</h2><p/><div><p>First paragraph.</p><p>Second paragraph.</p></div></body>
</html>"""
    assert html_to_paragraphs(raw) == "First paragraph.\n\nSecond paragraph."


def test_fff_fragment_drops_h2():
    raw = "<h2>Chapter Title</h2><div><p>A</p><p>B</p></div>"
    assert html_to_paragraphs(raw) == "A\n\nB"


def test_self_closing_and_empty_blocks_filtered():
    raw = "<body><p/><div><p>Real content.</p></div><div> </div><div/></body>"
    assert html_to_paragraphs(raw) == "Real content."


def test_html_entities_decoded():
    raw = "<p>foo &amp; bar &#8212; baz</p>"
    assert html_to_paragraphs(raw) == "foo & bar — baz"


def test_inline_tags_stripped_to_text():
    raw = "<p><strong>bold</strong> and <em>ital</em></p>"
    assert html_to_paragraphs(raw) == "bold and ital"


def test_empty_input_returns_empty_string():
    assert html_to_paragraphs("") == ""
    assert html_to_paragraphs(None) == ""  # type: ignore[arg-type]


def test_body_without_paragraphs_falls_back():
    raw = "<body>Just a line<br/>Another line</body>"
    out = html_to_paragraphs(raw)
    # Fallback should still return the body text (non-empty).
    assert "Just a line" in out
    assert "Another line" in out


def test_scene_break_paragraph_preserved_as_text():
    raw = "<p><strong> - Keira - 15/08/1994 -</strong></p>"
    assert html_to_paragraphs(raw) == "- Keira - 15/08/1994 -"


def test_multiple_paragraphs_joined_with_double_newline():
    raw = "<body><p>One.</p><p>Two.</p><p>Three.</p></body>"
    assert html_to_paragraphs(raw) == "One.\n\nTwo.\n\nThree."
```

- [ ] **Step 2: Run tests to verify they fail**

Run from the repo root:

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    pytest tests/scrapers/fanfic/test_html_to_text.py -v
```

Expected: `ModuleNotFoundError: No module named 'app.scrapers.fanfic._html_to_text'` (collection failure — all 9 tests fail to import).

- [ ] **Step 3: Write the helper**

Create `backend/app/scrapers/fanfic/_html_to_text.py`:

```python
"""Chapter HTML/XHTML → plain-text-paragraph normalization.

FFNet scraping has two backends (FanFicFare primary, FicHub fallback) that
each emit a different HTML shape:

- FanFicFare: fragment like `<h2>Title</h2><div><p>...</p></div>`.
- FicHub: full XHTML document per EPUB item — XML prolog, DOCTYPE,
  namespaced `<html>` root, `<head/>`, `<body>`.

The iOS reader (FanficReaderView) only knows how to render plain text
with paragraphs separated by "\\n\\n" (same shape the AO3 scraper
already produces). This module normalizes both FFNet shapes to that
format so all fanfic sources render identically.

Inline formatting (bold, italic) is discarded — matches the AO3 scraper's
existing behaviour. Duplicate chapter-title headings (`<h1>`–`<h4>` at the
top of the body) are dropped: FicHub injects `<h2>{chapter_title}</h2>`
and FFF sometimes does the same, but the chapter title is already stored
in `fanfic_chapters.title`.
"""
from __future__ import annotations

from bs4 import BeautifulSoup


def html_to_paragraphs(raw: str) -> str:
    """Extract plain-text paragraphs from chapter HTML or XHTML.

    Returns paragraphs joined by `"\\n\\n"`, matching the AO3 scraper's
    output format. Accepts both full XHTML documents (FicHub EPUB items)
    and bare fragments (FanFicFare adapter output). Empty or falsy input
    returns `""`.
    """
    if not raw:
        return ""

    soup = BeautifulSoup(raw, "lxml")
    root = soup.body if soup.body else soup

    # Drop structural/metadata elements and duplicate chapter-title
    # headings (FicHub EPUBs inject <h2>{chapter_title}</h2>).
    for tag in root.find_all(["head", "script", "style", "h1", "h2", "h3", "h4"]):
        tag.decompose()

    paragraphs = [
        p.get_text(" ", strip=True)
        for p in root.find_all("p")
        if p.get_text(strip=True)
    ]
    if paragraphs:
        return "\n\n".join(paragraphs)

    # Rare: chapter body uses raw text + <br> with no <p> wrapping.
    # Preserve blank-line separators so the reader still gets paragraph
    # breaks where possible.
    return root.get_text("\n\n", strip=True)
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    pytest tests/scrapers/fanfic/test_html_to_text.py -v
```

Expected: all 9 tests PASS.

- [ ] **Step 5: Commit**

```bash
cd backend && cd ..
git add backend/app/scrapers/fanfic/_html_to_text.py backend/tests/scrapers/fanfic/test_html_to_text.py
git commit -m "$(cat <<'EOF'
[backend] AST-41 add html_to_paragraphs helper

New shared helper that reduces FFNet chapter HTML/XHTML to plain-text
paragraphs separated by \n\n, matching the AO3 scraper's output shape.
Call-sites wired in follow-up commits.
EOF
)"
```

---

## Task 2: Wire helper into FicHub EPUB splitting

**Files:**
- Modify: `backend/app/scrapers/fanfic/_fichub.py` (around lines 114–139, `_split_epub_bytes`)
- Test: `backend/tests/scrapers/fanfic/test_fichub_client.py` (if it has assertions on chapter HTML content)

- [ ] **Step 1: Inspect current test expectations**

```bash
grep -n "html\|content\|get_content\|xmlns\|DOCTYPE" \
    "backend/tests/scrapers/fanfic/test_fichub_client.py"
```

If any test asserts that `ChapterText.html` contains raw HTML tags (e.g. `<p>`, `<body>`, `<?xml`, `xmlns`), note those — they will need updating in Step 4. If tests only assert structural things (chapter count, ordering, titles), nothing to change.

- [ ] **Step 2: Write/update a test that pins plain-text output**

Add this test to `backend/tests/scrapers/fanfic/test_fichub_client.py` (append at file end, not replacing existing tests):

```python
def test_split_epub_bytes_strips_xhtml_to_plain_paragraphs(tmp_path):
    """AST-41: each ChapterText.html returned from _split_epub_bytes is
    plain-text paragraphs joined by \\n\\n, not raw XHTML."""
    from ebooklib import epub
    from app.scrapers.fanfic._fichub import _split_epub_bytes

    book = epub.EpubBook()
    book.set_identifier("test")
    book.set_title("T")
    book.set_language("en")
    chap = epub.EpubHtml(title="Chapter 1", file_name="c1.xhtml", lang="en")
    chap.content = (
        "<?xml version='1.0' encoding='utf-8'?>"
        "<!DOCTYPE html><html xmlns='http://www.w3.org/1999/xhtml'>"
        "<head/><body><h2>Chapter 1</h2>"
        "<div><p>Alpha paragraph.</p><p>Bravo paragraph.</p></div>"
        "</body></html>"
    ).encode("utf-8")
    book.add_item(chap)
    book.spine = [chap]

    out_path = tmp_path / "test.epub"
    epub.write_epub(str(out_path), book)
    epub_bytes = out_path.read_bytes()

    chapters = _split_epub_bytes(epub_bytes)
    assert len(chapters) == 1
    assert chapters[0].html == "Alpha paragraph.\n\nBravo paragraph."
    assert "<?xml" not in chapters[0].html
    assert "<p>" not in chapters[0].html
```

- [ ] **Step 3: Run the new test to confirm it fails**

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    pytest tests/scrapers/fanfic/test_fichub_client.py::test_split_epub_bytes_strips_xhtml_to_plain_paragraphs -v
```

Expected: FAIL because `_split_epub_bytes` currently stores the full XHTML document in `ChapterText.html`.

- [ ] **Step 4: Patch `_split_epub_bytes` to use the helper**

Current body of the function in `backend/app/scrapers/fanfic/_fichub.py`:

```python
def _split_epub_bytes(epub_bytes: bytes) -> list[ChapterText]:
    """Synchronous EPUB → list[ChapterText]. Pulled out for unit testability.

    `ebooklib.epub.read_epub` only accepts a filesystem path, so we round-trip
    through a NamedTemporaryFile rather than a BytesIO.
    """
    import tempfile
    from ebooklib import epub, ITEM_DOCUMENT

    with tempfile.NamedTemporaryFile(suffix=".epub", delete=True) as tf:
        tf.write(epub_bytes)
        tf.flush()
        book = epub.read_epub(tf.name)

    chapters: list[ChapterText] = []
    chapter_num = 0
    for item in book.get_items_of_type(ITEM_DOCUMENT):
        name = (item.get_name() or "").lower()
        if "nav" in name or "cover" in name or "title" in name:
            continue
        chapter_num += 1
        html = item.get_content().decode("utf-8", errors="replace")
        title = item.title or f"Chapter {chapter_num}"
        chapters.append(ChapterText(number=chapter_num, title=title, html=html))

    return chapters
```

Replace the one `html = ...` line with a helper call. Edit target:

```python
# before
        html = item.get_content().decode("utf-8", errors="replace")

# after
        html = html_to_paragraphs(item.get_content().decode("utf-8", errors="replace"))
```

And add this import near the other module-level imports at the top of the file (after `import httpx`, before the `logger = logging.getLogger(__name__)` line):

```python
from app.scrapers.fanfic._html_to_text import html_to_paragraphs
```

- [ ] **Step 5: Run the full fichub test file and verify all pass**

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    pytest tests/scrapers/fanfic/test_fichub_client.py -v
```

Expected: the new test PASSES. All pre-existing tests also PASS. If any pre-existing test fails because it asserted on raw HTML (e.g. asserted `"<p>" in chapter.html`), update that assertion to match the plain-text shape (e.g. remove the `<p>` check, or replace with `assert chapter.html == "expected plain text"`). Do NOT change the behaviour being tested — only update expectations to reflect the new output format.

- [ ] **Step 6: Commit**

```bash
git add backend/app/scrapers/fanfic/_fichub.py backend/tests/scrapers/fanfic/test_fichub_client.py
git commit -m "$(cat <<'EOF'
[backend] AST-41 strip EPUB XHTML to plain text in FicHub path

_split_epub_bytes now runs each EPUB item through html_to_paragraphs
so ChapterText.html holds plain paragraphs joined by \n\n, matching
the AO3 scraper shape the iOS reader expects.
EOF
)"
```

---

## Task 3: Wire helper into FanFicFare runner

**Files:**
- Modify: `backend/app/scrapers/fanfic/_fanficfare_runner.py` (around lines 109–122, `_fetch_sync`)
- Test: `backend/tests/scrapers/fanfic/test_fanficfare_runner.py` (if it asserts chapter HTML shape)

- [ ] **Step 1: Inspect current test expectations**

```bash
grep -n "html\|chapter_text\|getChapterText\|ChapterText" \
    "backend/tests/scrapers/fanfic/test_fanficfare_runner.py"
```

Note any assertion on the shape of `ChapterText.html` — those will need updating in Step 4.

- [ ] **Step 2: Write a pinning test for the runner**

Append to `backend/tests/scrapers/fanfic/test_fanficfare_runner.py`:

```python
def test_fetch_sync_returns_plain_text_chapters(monkeypatch):
    """AST-41: _fetch_sync returns ChapterText.html as plain-text
    paragraphs (helper applied), regardless of the HTML fragment FFF's
    adapter.getChapterText returns."""
    from app.scrapers.fanfic import _fanficfare_runner

    class _FakeStory:
        def getMetadata(self, key, default=None):
            return {
                "title": "Test Story",
                "author": "A",
                "storyId": "1",
                "numChapters": 1,
                "numWords": 10,
                "status": "Complete",
            }.get(key, default)

        def getChapters(self):
            return [["chap-url-1", "Chapter 1"]]

    class _FakeAdapter:
        story = _FakeStory()

        def getStoryMetadataOnly(self):
            return None

        def getChapterText(self, url):
            return "<h2>Chapter 1</h2><div><p>Hello.</p><p>World.</p></div>"

    monkeypatch.setattr(
        _fanficfare_runner, "_get_adapter",
        lambda url, cookies, ua: _FakeAdapter(),
    )

    meta, chapters = _fanficfare_runner._fetch_sync(
        "https://m.fanfiction.net/s/1/1/Story", [], "ua",
    )
    assert meta.title == "Test Story"
    assert len(chapters) == 1
    assert chapters[0].html == "Hello.\n\nWorld."
    assert "<p>" not in chapters[0].html
    assert "<h2>" not in chapters[0].html
```

- [ ] **Step 3: Run the new test to confirm it fails**

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    pytest tests/scrapers/fanfic/test_fanficfare_runner.py::test_fetch_sync_returns_plain_text_chapters -v
```

Expected: FAIL — `chapters[0].html` is still the raw fragment `"<h2>Chapter 1</h2>..."`.

- [ ] **Step 4: Patch `_fetch_sync` to use the helper**

Current loop body in `backend/app/scrapers/fanfic/_fanficfare_runner.py::_fetch_sync`:

```python
    chapter_texts: list[ChapterText] = []
    for i, record in enumerate(adapter.story.getChapters(), start=1):
        chap_url, chap_title = record[0], record[1]
        html = adapter.getChapterText(chap_url) or ""
        chapter_texts.append(ChapterText(number=i, title=chap_title or f"Chapter {i}", html=html))
```

Edit target — wrap the `adapter.getChapterText(...)` call:

```python
# before
        html = adapter.getChapterText(chap_url) or ""

# after
        html = html_to_paragraphs(adapter.getChapterText(chap_url) or "")
```

And add the import at the top of the file, alongside the existing `from app.scrapers.base import StoryMetadata` line:

```python
from app.scrapers.fanfic._html_to_text import html_to_paragraphs
```

- [ ] **Step 5: Run full runner test file**

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    pytest tests/scrapers/fanfic/test_fanficfare_runner.py -v
```

Expected: new test PASSES, all pre-existing tests PASS. Update any pre-existing assertions that pinned the old raw-HTML shape with the plain-text equivalent.

- [ ] **Step 6: Run the complete fanfic scraper test suite as a regression check**

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    pytest tests/scrapers/fanfic -v
```

Expected: all tests PASS. `test_ffnet_scraper.py` uses `_fanficfare_runner` and `_fichub` as dependencies, so any fixture that asserts chapter HTML needs updating too. If tests under `test_ffnet_scraper.py` fail, update their expectations to match the plain-text shape (same rule as Step 5).

- [ ] **Step 7: Commit**

```bash
git add backend/app/scrapers/fanfic/_fanficfare_runner.py backend/tests/scrapers/fanfic/
git commit -m "$(cat <<'EOF'
[backend] AST-41 strip FFF chapter HTML to plain text

_fetch_sync now runs adapter.getChapterText through html_to_paragraphs
so both FFNet scraping paths (FFF primary, FicHub fallback) store
paragraphs joined by \n\n in fanfic_chapters.content.
EOF
)"
```

---

## Task 4: Backfill script for existing dirty rows

**Files:**
- Create: `backend/scripts/backfill_ffnet_chapter_text.py`
- Uses: `app.scrapers.fanfic._html_to_text.html_to_paragraphs`, `app.db.database.AsyncSessionLocal`

- [ ] **Step 1: Write the script**

Create `backend/scripts/backfill_ffnet_chapter_text.py`:

```python
#!/usr/bin/env python3
"""AST-41 backfill: normalize FFNet chapter content to plain text.

Finds every fanfic_chapters row whose `content` begins with an XML
prolog, a DOCTYPE, or an `<html>` tag — the fingerprint of the pre-fix
FicHub EPUB output — runs it through `html_to_paragraphs`, and updates
the row in place with the cleaned text and a recomputed `word_count`.

Idempotent: cleaned rows no longer match the LIKE filter on re-run.
Safe to interrupt: commits every 100 rows so partial progress persists.

Usage:
    docker compose -f docker-compose.local.yml exec arq_worker \\
        python scripts/backfill_ffnet_chapter_text.py [--dry-run]
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import sys

from sqlalchemy import text

sys.path.insert(0, ".")

from app.db.database import AsyncSessionLocal
from app.scrapers.fanfic._html_to_text import html_to_paragraphs

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger("backfill_ffnet")

BATCH_SIZE = 100

SELECT_SQL = text(
    """
    SELECT id, content, word_count
    FROM fanfic_chapters
    WHERE deleted_at IS NULL
      AND content IS NOT NULL
      AND (
          content LIKE '<?xml%'
          OR content LIKE '<!DOCTYPE%'
          OR content LIKE '<html%'
      )
    ORDER BY id
    """
)

UPDATE_SQL = text(
    """
    UPDATE fanfic_chapters
    SET content = :content, word_count = :word_count
    WHERE id = :id
    """
)


async def backfill(dry_run: bool) -> None:
    scanned = 0
    updated = 0
    async with AsyncSessionLocal() as db:
        result = await db.execute(SELECT_SQL)
        rows = result.fetchall()
        logger.info("scanning %d dirty rows (dry_run=%s)", len(rows), dry_run)

        for row in rows:
            scanned += 1
            old_text = row.content or ""
            new_text = html_to_paragraphs(old_text)
            new_word_count = len(new_text.split())

            if new_text == old_text:
                # Paranoia: helper is a no-op here → nothing to update.
                continue

            if dry_run:
                logger.info(
                    "would update id=%s | old_words≈%d new_words=%d old_chars=%d new_chars=%d",
                    row.id,
                    row.word_count or 0,
                    new_word_count,
                    len(old_text),
                    len(new_text),
                )
            else:
                await db.execute(
                    UPDATE_SQL,
                    {"id": row.id, "content": new_text, "word_count": new_word_count},
                )
            updated += 1

            if not dry_run and updated % BATCH_SIZE == 0:
                await db.commit()
                logger.info("committed batch | updated=%d scanned=%d", updated, scanned)

        if not dry_run:
            await db.commit()

    logger.info("done | scanned=%d updated=%d dry_run=%s", scanned, updated, dry_run)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--dry-run", action="store_true", help="Log changes without writing"
    )
    args = parser.parse_args()
    asyncio.run(backfill(args.dry_run))


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Dry-run the script against the local DB**

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    python scripts/backfill_ffnet_chapter_text.py --dry-run
```

Expected output includes a `scanning N dirty rows` line with N > 0 (the FFNet chapters we saw earlier), followed by `would update id=... old_words≈... new_words=...` lines where `new_words` is substantially smaller than `old_words` (tag tokens removed), and a final `done | scanned=N updated=N dry_run=True` summary.

- [ ] **Step 3: Pick one dry-run row and verify the cleaning looks right**

Take one of the `id=...` values from Step 2. Inspect its cleaned output:

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker python -c "
import asyncio
from sqlalchemy import text
from app.db.database import AsyncSessionLocal
from app.scrapers.fanfic._html_to_text import html_to_paragraphs

ID = 'PASTE_UUID_HERE'

async def main():
    async with AsyncSessionLocal() as db:
        r = await db.execute(text('SELECT content FROM fanfic_chapters WHERE id = :id'), {'id': ID})
        raw = r.scalar_one()
        cleaned = html_to_paragraphs(raw)
        print('--- FIRST 400 CHARS ---')
        print(cleaned[:400])
        print('--- LAST 200 CHARS ---')
        print(cleaned[-200:])
        print('--- TAG CHECK ---')
        for marker in ('<?xml', '<html', '<body', '<p>', '<div'):
            assert marker not in cleaned, f'still contains {marker}'
        print('no HTML markers present ✓')

asyncio.run(main())
"
```

Expected: prose text only, no `<?xml`, no `<html`, no `<p>`, no `<div`. The "no HTML markers present ✓" line confirms.

- [ ] **Step 4: Run the real backfill**

```bash
cd backend && docker compose -f docker-compose.local.yml exec arq_worker \
    python scripts/backfill_ffnet_chapter_text.py
```

Expected: same `scanned=N updated=N` summary as the dry run, without `dry_run=True`.

- [ ] **Step 5: Verify zero dirty rows remain**

```bash
cd backend && docker compose -f docker-compose.local.yml exec postgres \
    psql -U astral -d astral -c "
SELECT COUNT(*) AS dirty_rows
FROM fanfic_chapters
WHERE deleted_at IS NULL
  AND content IS NOT NULL
  AND (content LIKE '<?xml%' OR content LIKE '<!DOCTYPE%' OR content LIKE '<html%');
"
```

Expected: `dirty_rows | 0`.

- [ ] **Step 6: Spot-check a cleaned chapter in the DB**

```bash
cd backend && docker compose -f docker-compose.local.yml exec postgres \
    psql -U astral -d astral -c "
SELECT f.title, fc.chapter_number, LEFT(fc.content, 200) AS sample, fc.word_count
FROM fanfic_chapters fc JOIN fanfics f ON f.id = fc.fanfic_id
WHERE f.source_key = 'ffnet' AND fc.content IS NOT NULL
ORDER BY fc.updated_at DESC NULLS LAST, fc.created_at DESC
LIMIT 3;
"
```

Expected: `sample` column shows plain prose — no `<?xml`, no `<!DOCTYPE`, no `<p>`. `word_count` is a plausible value for prose (hundreds–low thousands per chapter).

- [ ] **Step 7: Commit**

```bash
git add backend/scripts/backfill_ffnet_chapter_text.py
git commit -m "$(cat <<'EOF'
[backend] AST-41 backfill script for dirty FFNet chapter content

Scans fanfic_chapters for rows whose content still begins with an XML
prolog, DOCTYPE, or <html> tag and reruns them through
html_to_paragraphs. Idempotent and safe to interrupt (commits every
100 rows).
EOF
)"
```

---

## Task 5: End-to-end verification with a fresh scrape

This is a manual smoke test. No new files. The goal is to confirm that a newly-issued scrape lands plain text in the DB (not just the backfill cleaning old rows).

- [ ] **Step 1: Find one completed FFNet fanfic to re-scrape**

```bash
cd backend && docker compose -f docker-compose.local.yml exec postgres \
    psql -U astral -d astral -c "
SELECT id, title, source_url FROM fanfics
WHERE source_key = 'ffnet' AND deleted_at IS NULL
  AND title NOT IN ('Pending scrape...', 'Unknown Title')
ORDER BY updated_at DESC LIMIT 3;
"
```

Pick one. Note the `source_url`.

- [ ] **Step 2: Trigger a delta scrape from the iOS app OR by enqueueing directly**

Easiest path is from iOS: open the fanfic detail page and pull-to-refresh / hit the sync button.

Alternatively, enqueue a delta job via the backend API:

```bash
curl -X POST http://localhost:8000/scrape/fanfic/delta-update \
    -H 'Content-Type: application/json' \
    -d '{"story_id": "PASTE_FANFIC_UUID_HERE"}'
```

(Swap the endpoint if your `scrape_service.delta_update` is exposed under a different route — check `backend/app/routes/scrape.py`.)

- [ ] **Step 3: Watch the worker log until the job finishes**

```bash
cd backend && docker compose -f docker-compose.local.yml logs -f arq_worker --tail=20
```

Wait for `fanfic_scrape_task finished | ... status=JobStatus.COMPLETE` (or PARTIAL). Ctrl-C out.

- [ ] **Step 4: Inspect a freshly-scraped chapter**

```bash
cd backend && docker compose -f docker-compose.local.yml exec postgres \
    psql -U astral -d astral -c "
SELECT f.title, fc.chapter_number, LEFT(fc.content, 300) AS sample, fc.word_count, fc.created_at
FROM fanfic_chapters fc JOIN fanfics f ON f.id = fc.fanfic_id
WHERE f.id = 'PASTE_FANFIC_UUID_HERE'
ORDER BY fc.chapter_number
LIMIT 3;
"
```

Expected: `sample` is plain prose. No `<?xml`, no `<p>`, no `<h2>`. `word_count` roughly matches the visible text.

- [ ] **Step 5: Open the fanfic in the iOS reader**

Launch the app (simulator or device), open the fanfic, open a chapter. The text should render as normal paragraphs with no visible tags, no XML prolog, no `</p>` fragments.

If this passes, AST-41 is done. If not, capture the iOS reader content (screenshot plus DB sample) and file a follow-up.

- [ ] **Step 6: No commit for this task**

This task only verifies. If Step 5 surfaced a bug, add a new task to the plan rather than silently editing the helper.

---

## Self-review

Ran the three self-review checks against the spec:

**Spec coverage:**
- ✅ New helper module (spec §1) → Task 1.
- ✅ `_fichub.py` call-site edit (spec §2) → Task 2.
- ✅ `_fanficfare_runner.py` call-site edit (spec §2) → Task 3.
- ✅ Backfill script (spec §3) → Task 4.
- ✅ Unit tests (spec §4, cases 1–8) → Task 1 Step 1 (plus integration-style tests in Tasks 2–3).

**Placeholder scan:**
- No TBDs, TODOs, or "add error handling" stand-ins.
- Every code step includes the exact code to write.
- Every run step includes the exact command and expected output.
- The only `PASTE_..._HERE` placeholders are in Task 4 Step 3 and Task 5 Steps 2/4, where the engineer must substitute a UUID from the previous step's output — that's unavoidable runtime data, not a planning gap.

**Type/name consistency:**
- Helper name `html_to_paragraphs` used identically across Tasks 1–4.
- Import path `app.scrapers.fanfic._html_to_text` identical across Tasks 2, 3, 4.
- `ChapterText.html` / `fanfic_chapters.content` references consistent with current models (verified against `backend/app/scrapers/fanfic/_fichub.py` and `backend/app/models/fanfic.py`).
- Test file paths follow the existing `backend/tests/scrapers/fanfic/` convention.

No gaps. Plan is ready for execution.
