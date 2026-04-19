# AST-20 — AO3 Bulk Selector Fix + Short-Content Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [docs/superpowers/specs/2026-04-19-ast20-ao3-bulk-selector-design.md](../specs/2026-04-19-ast20-ao3-bulk-selector-design.md)

**Goal:** Fix the AO3 bulk-download parser that returns chapter summaries instead of chapter bodies, add a metadata-driven short-content guard so future regressions fail loud, and backfill the corrupted chapter content.

**Architecture:** Tighten two CSS selectors in `app/scrapers/fanfic/ao3.py` to target `div.userstuff[role='article']` instead of any `.userstuff` descendant. Add a pure-function guard `validate_chapter_content` in a new `app/scrapers/validation.py` module, called from `fanfic_scrape_task` after each chapter's text is computed. Add a `Fanfic.allow_short_chapters` opt-out column via Alembic. Provide a one-shot backfill script that resets short chapters to PENDING and triggers DELTA scrapes.

**Tech Stack:** Python 3.11+, FastAPI, SQLAlchemy 2.x async, Alembic, BeautifulSoup4 (lxml parser), pytest + pytest-asyncio, ARQ.

---

## File Structure

**Create:**
- `backend/app/scrapers/validation.py` — pure guard helper, no I/O
- `backend/alembic/versions/e1f2a3b4c5d6_add_fanfic_allow_short_chapters.py` — column migration
- `backend/scripts/rescrape_short_chapters.py` — one-shot backfill
- `backend/tests/scrapers/test_ao3_bulk_selector.py` — selector unit tests
- `backend/tests/scrapers/test_validation.py` — guard unit tests

**Modify:**
- `backend/app/scrapers/fanfic/ao3.py` — tighten selectors in `get_all_chapters_bulk` and `get_chapter_text`; add diagnostic logs
- `backend/app/core/constants.py` — add `SHORT_CHAPTER_RATIO_THRESHOLD`, `SHORT_CHAPTER_HARD_FLOOR`
- `backend/app/models/fanfic.py` — add `allow_short_chapters` mapped column, import `Boolean`
- `backend/app/tasks/fanfic_scrape_task.py` — call `validate_chapter_content` after computing word_count; branch on accept/reject

---

## Task 1: Investigation — verify HTML hypothesis (read-only, no commit)

**Goal:** Confirm before changing selectors that "Correctional Officer Arc" chapter 2's `?view_full_work=true` HTML actually contains a `<blockquote class="userstuff">` summary inside `div#chapter-2`, ahead of the `<div class="userstuff" role="article">` body.

**Files:** None — this is a one-shot investigation step.

- [ ] **Step 1: Find the source URL in the local DB**

Run from the project root:

```bash
docker compose -f backend/docker-compose.local.yml exec postgres \
  psql -U astral -d astral -c \
  "SELECT id, source_url, source_key, word_count, total_chapters
   FROM fanfics WHERE title ILIKE 'Correctional Officer Arc%';"
```

Expected output: one row with a `https://archiveofourown.org/works/...` URL.

If `docker compose` is unavailable or the work isn't in the local DB, **substitute any other AO3 work** with `total_chapters >= 3` for this verification — the selector behavior does not depend on the specific work.

- [ ] **Step 2: Fetch the bulk view and save HTML**

```bash
WORK_URL="<paste source_url from step 1>"
curl -sL -A "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15) AppleWebKit/605.1.15" \
  "${WORK_URL}?view_full_work=true&view_adult=true" \
  -o /tmp/ao3-cooa.html
wc -c /tmp/ao3-cooa.html
```

Expected: file size > 100,000 bytes (full work pages are large). If you get a small file (~5KB), AO3 served a guest-block page; pick a non-mature work for verification instead.

- [ ] **Step 3: Inspect the chapter-2 markup**

```bash
python3 -c "
from bs4 import BeautifulSoup
soup = BeautifulSoup(open('/tmp/ao3-cooa.html').read(), 'lxml')
for div in soup.select('div[id^=chapter-]')[:3]:
    print(f'=== {div.get(\"id\")} ===')
    for u in div.select('.userstuff'):
        # what tag is .userstuff and what's the first 80 chars
        print(f'  {u.name}.userstuff role={u.get(\"role\")!r} -> {u.get_text(strip=True)[:80]!r}')
"
```

Expected output for any chapter that has a summary:
```
=== chapter-1 ===
  div.userstuff role='article' -> 'Body of chapter one...'
=== chapter-2 ===
  blockquote.userstuff role=None -> 'Summary text...'         ← THE BUG
  blockquote.userstuff role=None -> 'Notes text...'           ← also matches
  div.userstuff role='article' -> 'Body of chapter two...'    ← what we want
```

If the order is `blockquote, blockquote, div` then `select_one('.userstuff')` returns the summary blockquote → confirms hypothesis. Proceed to Task 2.

If the structure differs (e.g., AO3 has switched the body wrapper away from `role='article'`), revise Task 4's selector choice to `:scope > div.userstuff` (direct child of the chapter container) before applying.

- [ ] **Step 4: Save observed structure to scratchpad**

Per project AI agent rules, log this investigation:

```bash
cat > scratchpad/claude-2026-04-19-ast20-investigation.md <<'EOF'
# AST-20 — AO3 bulk-selector investigation

## Hypothesis
`div.select_one(".userstuff")` in `get_all_chapters_bulk` returns the chapter
summary blockquote (~30-100 words) instead of the chapter body div.

## Observed (from /tmp/ao3-cooa.html)
[paste output of step 3 here]

## Conclusion
[confirmed | not confirmed — fall back to :scope > div.userstuff]
EOF
```

No commit for this task — investigation artifacts are scratchpad-only.

---

## Task 2: Add diagnostic logs to AO3 bulk parser

**Goal:** Get visibility into per-chapter parse output before we change behavior, so any regression is immediately diagnosable.

**Files:**
- Modify: `backend/app/scrapers/fanfic/ao3.py`

- [ ] **Step 1: Add a per-chapter log line inside the bulk parser loop**

In [backend/app/scrapers/fanfic/ao3.py](backend/app/scrapers/fanfic/ao3.py), find the loop in `get_all_chapters_bulk` around line 238–260:

```python
        if chapter_divs:
            for div in chapter_divs:
                ch_id = div.get("id", "")
                m = re.search(r"chapter-(\d+)", ch_id)
                if not m:
                    continue
                chapter_num = float(m.group(1))

                content = div.select_one(".userstuff")
                if not content:
                    continue

                for h in content.select("h3.landmark"):
                    h.decompose()
                for n in content.select(".end-notes"):
                    n.decompose()

                paragraphs = [p.get_text(separator=" ", strip=True) for p in content.find_all("p")]
                text = "\n\n".join(p for p in paragraphs if p)
                if text:
                    chapters[chapter_num] = text
```

Replace with (changes: `if not content` now logs a warning; after building `text`, log structured info):

```python
        if chapter_divs:
            for div in chapter_divs:
                ch_id = div.get("id", "")
                m = re.search(r"chapter-(\d+)", ch_id)
                if not m:
                    continue
                chapter_num = float(m.group(1))

                content = div.select_one(".userstuff")
                if not content:
                    logger.warning(
                        "get_all_chapters_bulk no .userstuff in %s | container_chars=%d",
                        ch_id, len(div.get_text(strip=True)),
                    )
                    continue

                for h in content.select("h3.landmark"):
                    h.decompose()
                for n in content.select(".end-notes"):
                    n.decompose()

                paragraphs = [p.get_text(separator=" ", strip=True) for p in content.find_all("p")]
                text = "\n\n".join(p for p in paragraphs if p)
                logger.info(
                    "get_all_chapters_bulk parsed | chapter=%.1f selector=%s "
                    "matched_tag=%s paragraphs=%d final_chars=%d final_words=%d",
                    chapter_num, ".userstuff", content.name,
                    len(paragraphs), len(text), len(text.split()),
                )
                if text:
                    chapters[chapter_num] = text
```

The `selector=` and `matched_tag=` fields will let us see, post-fix, that `matched_tag=div` (correct) instead of `matched_tag=blockquote` (the bug).

- [ ] **Step 2: Run the existing scraper test suite to confirm no regression**

```bash
cd backend && python -m pytest tests/scrapers/ -v
```

Expected: existing `test_base_scraper.py` tests all pass.

- [ ] **Step 3: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add backend/app/scrapers/fanfic/ao3.py
git commit -m "$(cat <<'EOF'
[backend] AST-20 add diagnostic logs to AO3 bulk parser

Logs per-chapter parse output (selector matched, tag name, paragraph
count, char/word counts) so future regressions in get_all_chapters_bulk
are visible immediately in worker stdout. Lands first so the next change
(selector tightening) can be validated against the same logs.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add failing tests for the AO3 bulk + per-chapter selectors

**Goal:** Pin the selector behavior with hand-crafted HTML fixtures so the bug is reproducible and the fix is verifiable.

**Files:**
- Create: `backend/tests/scrapers/test_ao3_bulk_selector.py`

- [ ] **Step 1: Write the new test file**

Create `backend/tests/scrapers/test_ao3_bulk_selector.py`:

```python
"""
Unit tests for AO3Scraper selector behavior — bulk and per-chapter.

These pin the regression in AST-20: select_one('.userstuff') used to
return the chapter SUMMARY blockquote instead of the chapter BODY div.

All HTTP is monkeypatched out — no network.
"""
import pytest
from app.scrapers.fanfic.ao3 import AO3Scraper


# Bulk-view HTML with a known bug-trigger:
# - chapter-1: only a body div (no summary) — happy path
# - chapter-2: body div PRECEDED by summary blockquote and notes blockquote
# - chapter-3: body div PRECEDED only by notes blockquote
BULK_FIXTURE = """
<html><body>
<div id="chapter-1" class="chapter">
  <div class="userstuff module" role="article">
    <h3 class="landmark">Chapter Text</h3>
    <p>BODY1_MARKER chapter one body content goes here.</p>
    <p>Second paragraph of chapter one body.</p>
  </div>
</div>
<div id="chapter-2" class="chapter">
  <div class="summary module">
    <h3 class="heading">Summary:</h3>
    <blockquote class="userstuff">
      <p>SUMMARY2_MARKER chapter two summary text only.</p>
    </blockquote>
  </div>
  <div class="notes module">
    <h3 class="heading">Notes:</h3>
    <blockquote class="userstuff">
      <p>NOTES2_MARKER author notes for chapter two.</p>
    </blockquote>
  </div>
  <div class="userstuff module" role="article">
    <h3 class="landmark">Chapter Text</h3>
    <p>BODY2_MARKER chapter two body content begins here. Many more words follow in a real chapter.</p>
    <p>Another paragraph in the body of chapter two.</p>
  </div>
</div>
<div id="chapter-3" class="chapter">
  <div class="notes module">
    <h3 class="heading">Notes:</h3>
    <blockquote class="userstuff">
      <p>NOTES3_MARKER author notes for chapter three.</p>
    </blockquote>
  </div>
  <div class="userstuff module" role="article">
    <p>BODY3_MARKER chapter three body content.</p>
  </div>
</div>
</body></html>
"""


# Single-chapter (per-chapter) view HTML — same trap, different wrapper.
PER_CHAPTER_FIXTURE = """
<html><body>
<div id="chapters">
  <div class="summary module">
    <blockquote class="userstuff">
      <p>SUMMARY_MARKER work summary.</p>
    </blockquote>
  </div>
  <div class="userstuff module" role="article">
    <h3 class="landmark">Chapter Text</h3>
    <p>BODY_MARKER per-chapter body text content.</p>
  </div>
</div>
</body></html>
"""


def _patch_fetch(monkeypatch, html: str) -> None:
    async def fake_fetch(self, url):
        return html
    monkeypatch.setattr(AO3Scraper, "_fetch", fake_fetch)


@pytest.mark.asyncio
async def test_bulk_picks_chapter_body_not_summary(monkeypatch):
    _patch_fetch(monkeypatch, BULK_FIXTURE)
    result = await AO3Scraper().get_all_chapters_bulk(
        "https://archiveofourown.org/works/12345"
    )
    # All three chapters parsed
    assert set(result.keys()) == {1.0, 2.0, 3.0}
    # Chapter 1 (no summary) — happy path
    assert "BODY1_MARKER" in result[1.0]
    # Chapter 2 — the bug case. Body must win over summary AND notes.
    assert "BODY2_MARKER" in result[2.0]
    assert "SUMMARY2_MARKER" not in result[2.0]
    assert "NOTES2_MARKER" not in result[2.0]
    # Chapter 3 — body must win over notes.
    assert "BODY3_MARKER" in result[3.0]
    assert "NOTES3_MARKER" not in result[3.0]


@pytest.mark.asyncio
async def test_get_chapter_text_picks_body_not_summary(monkeypatch):
    _patch_fetch(monkeypatch, PER_CHAPTER_FIXTURE)
    text = await AO3Scraper().get_chapter_text(
        "https://archiveofourown.org/works/12345/chapters/1"
    )
    assert "BODY_MARKER" in text
    assert "SUMMARY_MARKER" not in text


@pytest.mark.asyncio
async def test_bulk_handles_chapter_without_summary(monkeypatch):
    """Regression guard: chapter-1-only fixture should still parse."""
    minimal = """
    <html><body>
    <div id="chapter-1" class="chapter">
      <div class="userstuff module" role="article">
        <p>Just the body. Nothing else.</p>
      </div>
    </div>
    </body></html>
    """
    _patch_fetch(monkeypatch, minimal)
    result = await AO3Scraper().get_all_chapters_bulk(
        "https://archiveofourown.org/works/12345"
    )
    assert result == {1.0: "Just the body. Nothing else."}
```

- [ ] **Step 2: Run the new tests to verify they FAIL with the current selector**

```bash
cd backend && python -m pytest tests/scrapers/test_ao3_bulk_selector.py -v
```

Expected: `test_bulk_picks_chapter_body_not_summary` and `test_get_chapter_text_picks_body_not_summary` both **FAIL** with assertions like `assert "SUMMARY2_MARKER" not in result[2.0]`. `test_bulk_handles_chapter_without_summary` should pass (it doesn't hit the bug).

If both bug tests pass already, the hypothesis is wrong — re-do Task 1 step 3 against a different work, or check the fixture html against AO3's actual markup.

- [ ] **Step 3: Do NOT commit yet — the failing tests stay until Task 4 lands the fix together with them**

(One commit for `red + green` keeps history clean.)

---

## Task 4: Tighten the AO3 selectors so the new tests pass

**Goal:** Change `.userstuff` lookups to target the chapter body specifically.

**Files:**
- Modify: `backend/app/scrapers/fanfic/ao3.py`

- [ ] **Step 1: Update the bulk parser selector**

In [backend/app/scrapers/fanfic/ao3.py](backend/app/scrapers/fanfic/ao3.py) line ~245, change:

```python
                content = div.select_one(".userstuff")
```

to:

```python
                content = div.select_one("div.userstuff[role='article']")
```

Also update the diagnostic log added in Task 2 to reflect the new selector — replace the `selector=".userstuff"` string with `selector="div.userstuff[role='article']"` in the `logger.info` call below it.

- [ ] **Step 2: Update the per-chapter selector**

In `get_chapter_text` at line ~199, change:

```python
        content_div = soup.select_one("#chapters .userstuff") or soup.select_one(".userstuff")
```

to:

```python
        content_div = (
            soup.select_one("#chapters div.userstuff[role='article']")
            or soup.select_one("div.userstuff[role='article']")
        )
```

- [ ] **Step 3: Update the single-chapter fallback inside the bulk parser**

In `get_all_chapters_bulk` at the bottom (~line 263), change:

```python
        content = soup.select_one("#chapters .userstuff") or soup.select_one(".userstuff")
```

to:

```python
        content = (
            soup.select_one("#chapters div.userstuff[role='article']")
            or soup.select_one("div.userstuff[role='article']")
        )
```

- [ ] **Step 4: Run the new tests — they MUST pass now**

```bash
cd backend && python -m pytest tests/scrapers/test_ao3_bulk_selector.py -v
```

Expected: all three tests pass.

- [ ] **Step 5: Run the full scraper test suite for regressions**

```bash
cd backend && python -m pytest tests/scrapers/ -v
```

Expected: every test passes.

- [ ] **Step 6: Commit selector fix + tests together**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add backend/app/scrapers/fanfic/ao3.py backend/tests/scrapers/test_ao3_bulk_selector.py
git commit -m "$(cat <<'EOF'
[backend] AST-20 fix AO3 bulk and per-chapter selectors

Tighten .userstuff selectors to div.userstuff[role='article'] so they
target the chapter body div instead of returning the first matching
descendant — which on chapters with a summary or notes was the
<blockquote class="userstuff"> wrapper above the body.

Adds unit tests with hand-crafted fixtures covering the bug case
(chapter with summary AND notes preceding body), the happy path
(body-only chapter), and the per-chapter view.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add SHORT_CHAPTER constants and Fanfic.allow_short_chapters column

**Goal:** Wire the database column and constants used by the smart guard. No behavior change yet.

**Files:**
- Modify: `backend/app/core/constants.py`
- Modify: `backend/app/models/fanfic.py`
- Create: `backend/alembic/versions/e1f2a3b4c5d6_add_fanfic_allow_short_chapters.py`

- [ ] **Step 1: Add constants**

Append to [backend/app/core/constants.py](backend/app/core/constants.py):

```python
# Short-content guard (AST-20). Per-chapter validation in fanfic_scrape_task.
# A chapter is rejected if its word_count is below RATIO * (fanfic.word_count /
# fanfic.total_chapters), or below HARD_FLOOR regardless of metadata.
SHORT_CHAPTER_RATIO_THRESHOLD = 0.30
SHORT_CHAPTER_HARD_FLOOR = 50
```

- [ ] **Step 2: Add `allow_short_chapters` to the Fanfic model**

In [backend/app/models/fanfic.py](backend/app/models/fanfic.py), update the import line at the top:

```python
from sqlalchemy import String, Integer, Float, Text, DateTime, ForeignKey, UniqueConstraint, func
```

to add `Boolean`:

```python
from sqlalchemy import String, Integer, Float, Boolean, Text, DateTime, ForeignKey, UniqueConstraint, func
```

Then in the `Fanfic` class, after the `bookmarks_count` line (~line 33) and before `thumbnail_path`, add:

```python
    allow_short_chapters: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False, server_default="false")
```

- [ ] **Step 3: Create the Alembic migration file**

Create `backend/alembic/versions/e1f2a3b4c5d6_add_fanfic_allow_short_chapters.py`:

```python
"""add allow_short_chapters column to fanfics

Revision ID: e1f2a3b4c5d6
Revises: d0e1f2a3b4c5
Create Date: 2026-04-19 12:00:00.000000
"""
from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa


revision: str = 'e1f2a3b4c5d6'
down_revision: Union[str, None] = 'd0e1f2a3b4c5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'fanfics',
        sa.Column(
            'allow_short_chapters',
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )


def downgrade() -> None:
    op.drop_column('fanfics', 'allow_short_chapters')
```

- [ ] **Step 4: Apply the migration locally and verify**

```bash
cd backend && alembic upgrade head
```

Expected: prints `Running upgrade d0e1f2a3b4c5 -> e1f2a3b4c5d6, add allow_short_chapters column to fanfics`.

If `alembic` isn't on PATH, use:

```bash
cd backend && python -m alembic upgrade head
```

Verify the column exists:

```bash
docker compose -f backend/docker-compose.local.yml exec postgres \
  psql -U astral -d astral -c \
  "SELECT column_name, data_type, column_default FROM information_schema.columns
   WHERE table_name='fanfics' AND column_name='allow_short_chapters';"
```

Expected output: one row showing `allow_short_chapters | boolean | false`.

- [ ] **Step 5: Run the existing service tests to confirm the new column doesn't break anything**

```bash
cd backend && python -m pytest tests/services/ -v
```

Expected: all tests pass. (The in-memory SQLite test DB rebuilds tables from `Base.metadata.create_all`, so it picks up the new column automatically.)

- [ ] **Step 6: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add backend/app/core/constants.py backend/app/models/fanfic.py backend/alembic/versions/e1f2a3b4c5d6_add_fanfic_allow_short_chapters.py
git commit -m "$(cat <<'EOF'
[backend] AST-20 add allow_short_chapters column to fanfics

Boolean opt-out flag for the upcoming smart short-content guard.
Default false. Used to bypass the heuristic for legitimate
edge cases (e.g., works where AO3 omits word_count metadata).

Adds SHORT_CHAPTER_RATIO_THRESHOLD (0.30) and SHORT_CHAPTER_HARD_FLOOR
(50) constants. No behavior change in this commit — the guard wiring
lands next.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Write failing tests for `validate_chapter_content`

**Goal:** TDD-red the smart guard helper.

**Files:**
- Create: `backend/tests/scrapers/test_validation.py`

- [ ] **Step 1: Write the test file**

Create `backend/tests/scrapers/test_validation.py`:

```python
"""
Unit tests for the short-content validation helper used by the fanfic
scrape pipeline. Pure function — no DB, no network.
"""
from app.scrapers.validation import validate_chapter_content


def test_rejects_below_ratio_threshold():
    # expected_avg = 10000/10 = 1000; threshold = 1000 * 0.30 = 300
    accept, reason = validate_chapter_content(
        word_count=200,
        fanfic_word_count=10000,
        fanfic_total_chapters=10,
        allow_short=False,
    )
    assert accept is False
    assert reason is not None and "200" in reason


def test_accepts_above_ratio_threshold():
    accept, reason = validate_chapter_content(
        word_count=4000,
        fanfic_word_count=10000,
        fanfic_total_chapters=10,
        allow_short=False,
    )
    assert accept is True
    assert reason is None


def test_rejects_below_hard_floor_even_when_metadata_missing():
    accept, reason = validate_chapter_content(
        word_count=30,
        fanfic_word_count=None,
        fanfic_total_chapters=None,
        allow_short=False,
    )
    assert accept is False
    assert reason is not None and "50" in reason


def test_bypassed_by_allow_short_flag():
    accept, reason = validate_chapter_content(
        word_count=10,  # below the hard floor and below ratio
        fanfic_word_count=10000,
        fanfic_total_chapters=10,
        allow_short=True,
    )
    assert accept is True
    assert reason is None


def test_accepts_when_metadata_missing_and_above_floor():
    accept, reason = validate_chapter_content(
        word_count=100,
        fanfic_word_count=None,
        fanfic_total_chapters=None,
        allow_short=False,
    )
    assert accept is True
    assert reason is None


def test_rejects_below_ratio_with_single_chapter_work():
    # expected_avg = 5000/1 = 5000; threshold = 5000 * 0.30 = 1500
    accept, reason = validate_chapter_content(
        word_count=200,
        fanfic_word_count=5000,
        fanfic_total_chapters=1,
        allow_short=False,
    )
    assert accept is False
    assert reason is not None


def test_accepts_when_total_chapters_zero():
    # Edge: total_chapters=0 would divmod-error. Helper should treat as missing.
    accept, reason = validate_chapter_content(
        word_count=100,
        fanfic_word_count=10000,
        fanfic_total_chapters=0,
        allow_short=False,
    )
    assert accept is True
    assert reason is None
```

- [ ] **Step 2: Run the new tests — they MUST fail with ImportError**

```bash
cd backend && python -m pytest tests/scrapers/test_validation.py -v
```

Expected: all tests fail with `ModuleNotFoundError: No module named 'app.scrapers.validation'`. This proves the test file is wired up but the helper doesn't exist yet.

- [ ] **Step 3: Do NOT commit yet — green test + impl together in Task 7**

---

## Task 7: Implement `validate_chapter_content` and wire it into the scrape task

**Goal:** Make the failing tests pass and have the scrape task use the helper.

**Files:**
- Create: `backend/app/scrapers/validation.py`
- Modify: `backend/app/tasks/fanfic_scrape_task.py`

- [ ] **Step 1: Implement the pure helper**

Create `backend/app/scrapers/validation.py`:

```python
"""
Per-chapter content validation for fanfic scrapes.

Pure function — no DB, no I/O. Called by fanfic_scrape_task after each
chapter's text is fetched. Catches partial scrapes (e.g., a selector bug
that returns the chapter summary instead of the body) by comparing the
extracted word count against the work's expected per-chapter average.
"""
from app.core.constants import SHORT_CHAPTER_RATIO_THRESHOLD, SHORT_CHAPTER_HARD_FLOOR


def validate_chapter_content(
    word_count: int,
    fanfic_word_count: int | None,
    fanfic_total_chapters: int | None,
    allow_short: bool,
) -> tuple[bool, str | None]:
    """
    Decide whether a scraped chapter's content is plausible.

    Returns (accept, rejection_reason). rejection_reason is None when accepted.
    """
    if allow_short:
        return True, None

    if word_count < SHORT_CHAPTER_HARD_FLOOR:
        return (
            False,
            f"Got {word_count} words, below hard floor of {SHORT_CHAPTER_HARD_FLOOR}",
        )

    if fanfic_word_count and fanfic_total_chapters:
        expected_avg = fanfic_word_count / fanfic_total_chapters
        threshold = expected_avg * SHORT_CHAPTER_RATIO_THRESHOLD
        if word_count < threshold:
            return (
                False,
                f"Got {word_count} words, expected >= {int(threshold)} "
                f"(avg {int(expected_avg)} per chapter)",
            )

    return True, None
```

- [ ] **Step 2: Run the validation tests — they MUST pass now**

```bash
cd backend && python -m pytest tests/scrapers/test_validation.py -v
```

Expected: all 7 tests pass.

- [ ] **Step 3: Wire the helper into `fanfic_scrape_task`**

In [backend/app/tasks/fanfic_scrape_task.py](backend/app/tasks/fanfic_scrape_task.py), add the import near the top (with the other `from app.scrapers...` imports around line 13–16):

```python
from app.scrapers.validation import validate_chapter_content
```

Then locate the per-chapter loop body (lines ~256–320). The current accept path is:

```python
                    chapter.content = text
                    chapter.word_count = len(text.split())
                    chapter.scrape_status = ScrapeStatus.SCRAPED
                    job.chapters_scraped += 1
                    dur = int((time.perf_counter() - ch_start) * 1000)
                    _add_log(db, job_uuid, "info", ch_label,
                             f"Scraped {chapter.word_count} words",
                             duration_ms=dur, chapter_number=chapter.chapter_number)
                    await db.commit()
                    logger.info(
                        "fanfic_scrape_task chapter ok | job_id=%s chapter=%.1f [%d/%d] words=%d elapsed_ms=%d",
                        job_id, chapter.chapter_number, ch_idx, total_chapters,
                        chapter.word_count, dur,
                    )
```

Replace it with the gated version:

```python
                    word_count = len(text.split())
                    accept, rejection_reason = validate_chapter_content(
                        word_count=word_count,
                        fanfic_word_count=fanfic.word_count if fanfic else None,
                        fanfic_total_chapters=fanfic.total_chapters if fanfic else None,
                        allow_short=fanfic.allow_short_chapters if fanfic else False,
                    )
                    dur = int((time.perf_counter() - ch_start) * 1000)
                    if accept:
                        chapter.content = text
                        chapter.word_count = word_count
                        chapter.scrape_status = ScrapeStatus.SCRAPED
                        job.chapters_scraped += 1
                        _add_log(db, job_uuid, "info", ch_label,
                                 f"Scraped {word_count} words",
                                 duration_ms=dur, chapter_number=chapter.chapter_number)
                        await db.commit()
                        logger.info(
                            "fanfic_scrape_task chapter ok | job_id=%s chapter=%.1f [%d/%d] words=%d elapsed_ms=%d",
                            job_id, chapter.chapter_number, ch_idx, total_chapters,
                            word_count, dur,
                        )
                    else:
                        chapter.content = None
                        chapter.word_count = None
                        chapter.scrape_status = ScrapeStatus.FAILED
                        job.chapters_failed += 1
                        job.last_error_type = "ShortContent"
                        job.error_message = rejection_reason
                        _add_log(db, job_uuid, "error", ch_label,
                                 f"Rejected short content: {rejection_reason}",
                                 error_type="ShortContent",
                                 duration_ms=dur, chapter_number=chapter.chapter_number)
                        await db.commit()
                        logger.warning(
                            "fanfic_scrape_task chapter rejected | job_id=%s chapter=%.1f [%d/%d] reason=%s elapsed_ms=%d",
                            job_id, chapter.chapter_number, ch_idx, total_chapters,
                            rejection_reason, dur,
                        )
```

Note: the inner code references a `fanfic` variable. The existing task already loaded `fanfic` at line ~202 (after the chapter-list update) and that variable remains in scope at the per-chapter loop. No additional fetch is needed — `fanfic.word_count`, `fanfic.total_chapters`, and the new `fanfic.allow_short_chapters` are all populated from that single SELECT.

- [ ] **Step 4: Run the full backend test suite for regressions**

```bash
cd backend && python -m pytest -v
```

Expected: all tests pass — `test_validation.py`, `test_ao3_bulk_selector.py`, and the existing services/api/scrapers tests.

- [ ] **Step 5: Commit guard impl + wiring + tests together**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add backend/app/scrapers/validation.py \
        backend/app/tasks/fanfic_scrape_task.py \
        backend/tests/scrapers/test_validation.py
git commit -m "$(cat <<'EOF'
[backend] AST-20 add short-content guard with per-fanfic opt-out

After computing each chapter's word_count, validate against the work's
expected per-chapter average (fanfic.word_count / fanfic.total_chapters)
times SHORT_CHAPTER_RATIO_THRESHOLD (0.30), with a SHORT_CHAPTER_HARD_FLOOR
of 50 words below which everything fails. Bypassed when
fanfic.allow_short_chapters is true.

Rejected chapters get scrape_status=FAILED, content/word_count NULL,
job.last_error_type=ShortContent, and a structured ScrapeLog row. The
job continues to the next chapter; final job status becomes PARTIAL.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Backfill script for chapters already corrupted by the bug

**Goal:** Re-scrape every fanfic that currently has any chapter under 500 words, using the now-fixed selector and validated by the new guard.

**Files:**
- Create: `backend/scripts/rescrape_short_chapters.py`

- [ ] **Step 1: Write the script**

Create `backend/scripts/rescrape_short_chapters.py`:

```python
#!/usr/bin/env python3
"""
Backfill: re-scrape every fanfic that has any chapter under 500 words.

Resets the affected chapter rows to scrape_status='pending' with
content/word_count cleared, then enqueues a DELTA scrape job per fanfic.
The DELTA task picks up only PENDING/FAILED chapters (existing behavior
in fanfic_scrape_task).

Usage:
    docker compose -f docker-compose.local.yml exec api \\
      python scripts/rescrape_short_chapters.py [--dry-run]
"""
import argparse
import asyncio
import sys
from sqlalchemy import select, update, text

# Allow `python scripts/...` from the backend root.
sys.path.insert(0, ".")

from app.db.database import AsyncSessionLocal
from app.models.fanfic import Fanfic, FanficChapter
from app.services.scrape_service import delta_update


SHORT_THRESHOLD_WORDS = 500


async def find_affected_fanfic_ids(db) -> list:
    """Distinct fanfic IDs that have at least one short, non-deleted chapter."""
    rows = await db.execute(
        text(
            "SELECT DISTINCT c.fanfic_id "
            "FROM fanfic_chapters c "
            "JOIN fanfics f ON f.id = c.fanfic_id "
            "WHERE c.deleted_at IS NULL "
            "  AND f.deleted_at IS NULL "
            "  AND c.content IS NOT NULL "
            "  AND array_length(string_to_array(c.content, ' '), 1) < :threshold"
        ),
        {"threshold": SHORT_THRESHOLD_WORDS},
    )
    return [r[0] for r in rows]


async def reset_short_chapters(db, fanfic_id) -> int:
    """Reset short chapters on this fanfic to PENDING. Returns row count."""
    result = await db.execute(
        text(
            "UPDATE fanfic_chapters "
            "   SET scrape_status='pending', content=NULL, word_count=NULL "
            " WHERE fanfic_id = :fid "
            "   AND deleted_at IS NULL "
            "   AND content IS NOT NULL "
            "   AND array_length(string_to_array(content, ' '), 1) < :threshold"
        ),
        {"fid": fanfic_id, "threshold": SHORT_THRESHOLD_WORDS},
    )
    return result.rowcount or 0


async def main(dry_run: bool) -> None:
    async with AsyncSessionLocal() as db:
        affected = await find_affected_fanfic_ids(db)
        print(f"Found {len(affected)} fanfics with chapters under {SHORT_THRESHOLD_WORDS} words.")
        if dry_run:
            for fid in affected:
                print(f"  - {fid}")
            print("[dry-run] no changes made.")
            return

        total_reset = 0
        for fid in affected:
            n = await reset_short_chapters(db, fid)
            total_reset += n
            await db.commit()
            try:
                await delta_update(db, fid)
                print(f"  - {fid}: reset {n} chapters, DELTA job enqueued")
            except Exception as e:
                print(f"  - {fid}: reset {n} chapters, BUT enqueue failed: {e}")

        print(f"\nDone. Queued {len(affected)} fanfics, reset {total_reset} chapters.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="List affected fanfics without changing anything.")
    args = parser.parse_args()
    asyncio.run(main(args.dry_run))
```

- [ ] **Step 2: Smoke-test the script with --dry-run**

If the docker stack is up locally:

```bash
docker compose -f backend/docker-compose.local.yml exec api \
  python scripts/rescrape_short_chapters.py --dry-run
```

Expected: prints `Found N fanfics with chapters under 500 words.` followed by a list of UUIDs, then `[dry-run] no changes made.`

If the stack isn't up, this is a deferred verification. The script body is mechanical and follows the same pattern as `seed_fanfic_thumbnails.py`; commit it and the user runs it post-deploy.

- [ ] **Step 3: Commit**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git add backend/scripts/rescrape_short_chapters.py
git commit -m "$(cat <<'EOF'
[backend] AST-20 add rescrape_short_chapters backfill script

One-shot script. Finds every fanfic that has any chapter under 500
words, resets those chapter rows to scrape_status='pending' with
content/word_count cleared, and enqueues a DELTA scrape job per
fanfic. The DELTA task re-fetches only PENDING/FAILED chapters using
the corrected AO3 selectors and the new short-content guard.

Run after the selector fix and guard land in development.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Final verification

**Goal:** Confirm the whole branch is healthy and ready for PR.

**Files:** None.

- [ ] **Step 1: Run the entire backend test suite**

```bash
cd backend && python -m pytest -v
```

Expected: all tests green.

- [ ] **Step 2: Confirm the branch state**

```bash
cd "/Users/nicknetraganti/Desktop/Developer Stuff/IosApp/IosTestApp"
git log --oneline origin/development..HEAD
```

Expected: 5 commits, in order:
1. `[docs] AST-20 add design spec…`
2. `[backend] AST-20 add diagnostic logs to AO3 bulk parser`
3. `[backend] AST-20 fix AO3 bulk and per-chapter selectors`
4. `[backend] AST-20 add allow_short_chapters column to fanfics`
5. `[backend] AST-20 add short-content guard with per-fanfic opt-out`
6. `[backend] AST-20 add rescrape_short_chapters backfill script`

(That's 6 commits — including the spec commit landed in the brainstorming step.)

- [ ] **Step 3: Confirm no stray uncommitted changes**

```bash
git status --short
```

Expected: only the same `?? .claire/`, `?? .claude/`, `?? .playwright-mcp/` untracked dirs that were there at session start. No tracked-file changes.

- [ ] **Step 4: Stop here. Do NOT push or open a PR**

The user explicitly handles branch pushes and PR creation themselves per the project's branch protection rules.

---

## Self-review notes

Spec coverage check:
- §1 Investigation → Task 1 ✓
- §2 AO3 selector fix → Tasks 3 + 4 ✓
- §3 Smart guard with opt-out → Tasks 5 (column/constants) + 6 + 7 (helper + wiring) ✓
- §4 Diagnostic logs → Task 2 ✓
- §5 Backfill script → Task 8 ✓
- §6 Alembic migration → Task 5 step 3 ✓
- §7 Tests → Task 3 (selectors) + Task 6 (validation) ✓

Type / signature consistency:
- `validate_chapter_content(word_count, fanfic_word_count, fanfic_total_chapters, allow_short)` is the same signature across the helper, the test file, and the call site in the scrape task ✓
- The new column `allow_short_chapters` is referenced consistently in the model, the migration, the helper call site, and the backfill script ✓
- `ScrapeStatus.FAILED` and `ScrapeStatus.SCRAPED` are existing enum values (verified in `app/core/constants.py`) ✓

No placeholders, no "TBD", no "similar to Task N" without code shown.
