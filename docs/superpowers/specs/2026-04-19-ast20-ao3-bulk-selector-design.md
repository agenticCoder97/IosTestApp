# AST-20 — AO3 fanfic chapters scraped with only 15-150 words

Linear: [AST-20](https://linear.app/nnetraganti/issue/AST-20/scrape-fanfic-chapters-scraped-with-only-15-150-words-incomplete)

## Problem

Fanfic chapters are being persisted to `fanfic_chapters.content` with only 15–150 words instead of the full chapter body (which should be thousands of words). The user-reported reproduction case is "Correctional Officer Arc" on AO3: chapter 1 is full-length, chapters 2+ are truncated. This pattern points squarely at the AO3 bulk-download path — `get_all_chapters_bulk` in [backend/app/scrapers/fanfic/ao3.py](backend/app/scrapers/fanfic/ao3.py) — which fetches the entire work in a single request via `?view_full_work=true` and parses each chapter's body out of the resulting HTML.

The bulk parser currently does:

```python
for div in chapter_divs:                         # div#chapter-N
    content = div.select_one(".userstuff")       # FIRST .userstuff descendant
```

On `?view_full_work=true`, each chapter's container has both a chapter-summary blockquote (`<blockquote class="userstuff">`) and the chapter body (`<div class="userstuff module" role="article">`). `select_one(".userstuff")` returns the first match in document order — the summary blockquote — which is typically 30–100 words. Chapter 1 escapes the bug because the *work* summary lives outside `div#chapter-1`, not inside it. Hence "first chapter fine, others short."

The same descendant-selector pattern exists in [`get_chapter_text`](backend/app/scrapers/fanfic/ao3.py:195) (`#chapters .userstuff`) and would have the same flaw on a single-chapter view that happens to include a chapter summary.

In addition, the scrape pipeline currently has **no minimum-length sanity check** anywhere — whatever the parser returns (including an empty string or a 15-word summary stub) gets persisted as `chapter.content` with `scrape_status = SCRAPED`. There is nothing that fails a job loud when the extracted content is suspiciously short.

## Goal

1. Confirm the AO3 bulk-selector hypothesis against a live page, then fix the selectors so chapter summaries can never substitute for chapter bodies.
2. Add a metadata-driven "smart guard" so the next bug of this shape (selector regression, redirect-page parse, partial fetch) fails loud — chapter row marked `FAILED`, no truncated content committed.
3. Provide an opt-out per fanfic for legitimate edge cases the heuristic cannot judge (e.g., works where AO3 omits `word_count` metadata).
4. Backfill the corruption: re-scrape every fanfic that currently has any chapter under 500 words.

## Scope

- **Backend only.** No iOS changes. iOS already reads `fanfic_chapters.content` straight from the DB; once the backend writes correct content, the reader picks it up on the next library refresh.
- **AO3 only for the selector fix.** FFNet's per-chapter selector (`#storytext`) does not have the descendant-summary risk. The new short-content guard, however, applies to **all** sources.
- **One PR**, shipped to `development` via `feature/ast-20-ao3-bulk-selector`.

## Out of scope

- Switching the bulk path to per-chapter as a "safer default." The bulk path is a 10–50× speedup on multi-chapter works and is worth keeping.
- A user-facing UI for the `allow_short_chapters` opt-out flag. For now the flag is set via a one-off SQL update or a tiny script; iOS surfacing comes later if it becomes a frequent need.
- Backfilling FFNet works affected by unrelated short-content issues (e.g., guest-preview interstitials). The histogram in §1 will tell us if FFNet is also affected; if so, a follow-up ticket scopes that work.

## Design

### §1. Investigation step (run before changing any selector)

Goal: confirm the HTML hypothesis on a real page, and measure blast radius.

1. **Pull the source URL** for "Correctional Officer Arc" from the local Postgres:
   ```sql
   SELECT id, source_url, source_key, word_count, total_chapters
   FROM fanfics WHERE title ILIKE 'Correctional Officer Arc%';
   ```
2. **Fetch the bulk view** through the same code path the scraper uses. Run a one-shot Python REPL inside the backend container:
   ```python
   from app.scrapers.fanfic.ao3 import AO3Scraper
   import asyncio
   s = AO3Scraper()
   html = asyncio.run(s._fetch(f"{source_url}?view_full_work=true&view_adult=true"))
   open("/tmp/ao3-cooa.html", "w").write(html)
   ```
3. **Inspect** `/tmp/ao3-cooa.html` for `div#chapter-2`. Confirm the markup is:
   - One `<blockquote class="userstuff">` inside `div.summary.module` (the chapter summary)
   - One `<div class="userstuff module" role="article">` further down (the chapter body)
   If the structure differs (e.g., AO3 redesigned wrappers, or the response is a "register to view" interstitial), the §2 selector choice changes.
4. **Run the histogram SQL** from the ticket, grouped by source so we know whether FFNet is also affected:
   ```sql
   SELECT f.source_key,
          COUNT(*)            AS short_chapter_count,
          COUNT(DISTINCT c.fanfic_id) AS affected_fanfics
   FROM fanfic_chapters c
   JOIN fanfics f ON f.id = c.fanfic_id
   WHERE c.deleted_at IS NULL
     AND array_length(string_to_array(c.content, ' '), 1) < 500
   GROUP BY f.source_key;
   ```

The investigation step is documented in the implementation plan but does not produce code artifacts other than (optionally) the saved HTML and the histogram numbers, which feed into §6 (backfill expected impact).

### §2. AO3 selector fix

In [backend/app/scrapers/fanfic/ao3.py](backend/app/scrapers/fanfic/ao3.py):

**`get_all_chapters_bulk` (line ~245):** change
```python
content = div.select_one(".userstuff")
```
to
```python
content = div.select_one("div.userstuff[role='article']")
```

`role="article"` is AO3's own semantic marker for the chapter body div and is not used on the summary blockquote. If §1 reveals AO3 has dropped the `role` attribute on some works, fall back to `:scope > div.userstuff` (direct child of the chapter container, which excludes the summary nested deeper inside `div.summary.module > blockquote`).

**`get_chapter_text` (line ~195):** change
```python
content_div = soup.select_one("#chapters .userstuff") or soup.select_one(".userstuff")
```
to
```python
content_div = (
    soup.select_one("#chapters div.userstuff[role='article']")
    or soup.select_one("div.userstuff[role='article']")
)
```

Both selectors retain the existing `h3.landmark` and `.end-notes` decompose calls and the `<p>` join logic — only the `.userstuff` lookup tightens.

### §3. Smart guard with per-fanfic opt-out

The guard logic lives in a new pure helper so it's directly unit-testable without spinning up the full ARQ task. New file `backend/app/scrapers/validation.py`:

```python
def validate_chapter_content(
    word_count: int, fanfic_word_count: int | None,
    fanfic_total_chapters: int | None, allow_short: bool,
) -> tuple[bool, str | None]:
    """Returns (accept, rejection_reason). rejection_reason is None when accepted."""
```

The task calls it after computing `len(text.split())` and branches on the result.

#### New column on `Fanfic`

```python
allow_short_chapters: Mapped[bool] = mapped_column(
    Boolean, nullable=False, server_default=sa.false()
)
```

Default `False`. When `True`, the guard is bypassed for every chapter on that fanfic.

#### New constants in [backend/app/core/constants.py](backend/app/core/constants.py)

```python
SHORT_CHAPTER_RATIO_THRESHOLD = 0.30   # fraction of expected_avg below which we reject
SHORT_CHAPTER_HARD_FLOOR = 50          # absolute word count below which we always reject
```

#### Guard logic — applied inside `fanfic_scrape_task` immediately after `chapter.word_count = len(text.split())`

```
if fanfic.allow_short_chapters:
    accept
elif chapter.word_count < SHORT_CHAPTER_HARD_FLOOR:
    reject — message: "Got {N} words, below hard floor of 50"
elif fanfic.word_count and fanfic.total_chapters:
    expected_avg = fanfic.word_count / fanfic.total_chapters
    threshold    = expected_avg * SHORT_CHAPTER_RATIO_THRESHOLD
    if chapter.word_count < threshold:
        reject — message: "Got {N} words, expected ≥{int(threshold)} (avg {int(expected_avg)})"
    else:
        accept
else:
    accept   # no metadata → can't judge, fall through (hard floor still applied above)
```

A "reject" path:
1. Sets `chapter.scrape_status = ScrapeStatus.FAILED`
2. Leaves `chapter.content = NULL` and `chapter.word_count = NULL` (clear, not the truncated value — we don't want a downstream consumer to read it)
3. Increments `job.chapters_failed`
4. Writes a `ScrapeLog` row with `level="error"`, `step=ch_label`, `error_type="ShortContent"`, message as above
5. **Does not break the loop.** The job continues to the next chapter (this is per-chapter validation, not a fatal job error). The job ends in `PARTIAL` status if `chapters_failed > 0`, which is the existing behavior.

The guard runs in both code paths (bulk-text branch and per-chapter `get_chapter_text` branch) since the validation is on the final word count, not on the fetch method.

### §4. Diagnostic logs in the bulk parser

In `get_all_chapters_bulk`, after extracting each chapter, emit:

```python
logger.info(
    "get_all_chapters_bulk parsed | chapter=%d raw_paragraphs=%d final_chars=%d final_words=%d",
    chapter_num, len(paragraphs), len(text), len(text.split()),
)
```

If `content is None` (selector returned nothing), log a warning with the `chapter-N` div's stripped text length so we can see whether the page was empty or just selector-mismatched.

These logs go through stdlib `logger`, not `ScrapeLog` rows. Forensic only — keeps DB noise down.

### §5. Backfill script

New file `backend/scripts/rescrape_short_chapters.py`. Pattern mirrors [seed_fanfic_thumbnails.py](backend/scripts/seed_fanfic_thumbnails.py).

Behavior:

1. Connect via `AsyncSessionLocal`.
2. Query distinct fanfics that have at least one chapter under 500 words and are not soft-deleted:
   ```sql
   SELECT DISTINCT c.fanfic_id
   FROM fanfic_chapters c
   JOIN fanfics f ON f.id = c.fanfic_id
   WHERE c.deleted_at IS NULL
     AND f.deleted_at IS NULL
     AND array_length(string_to_array(c.content, ' '), 1) < 500;
   ```
3. For each `fanfic_id`:
   - Update affected chapters back to scrapable state:
     ```sql
     UPDATE fanfic_chapters
        SET scrape_status = 'pending', content = NULL, word_count = NULL
      WHERE fanfic_id = :id
        AND deleted_at IS NULL
        AND array_length(string_to_array(content, ' '), 1) < 500;
     ```
   - Call `scrape_service.delta_update(db, fanfic_id)` to enqueue a DELTA scrape job. (DELTA reuses the same task and only re-fetches `PENDING`/`FAILED` chapters via the existing query at [backend/app/tasks/fanfic_scrape_task.py:226](backend/app/tasks/fanfic_scrape_task.py:226).)
4. Print summary: `Queued N fanfics, reset M chapters.`

CLI invocation (matches the existing `seed_fanfic_thumbnails.py` style — `scripts/` has no `__init__.py`):
```
docker compose -f docker-compose.local.yml exec api python scripts/rescrape_short_chapters.py
```

Run **once**, after the §2 fix and §3 guard are deployed, so that the re-scrapes both pick up the corrected selector and are validated by the new guard. Not a recurring job.

### §6. Alembic migration

New file `backend/alembic/versions/e1f2a3b4c5d6_add_fanfic_allow_short_chapters.py`:

```python
revision = 'e1f2a3b4c5d6'
down_revision = 'd0e1f2a3b4c5'

def upgrade():
    op.add_column(
        'fanfics',
        sa.Column('allow_short_chapters', sa.Boolean(), nullable=False,
                  server_default=sa.false()),
    )

def downgrade():
    op.drop_column('fanfics', 'allow_short_chapters')
```

### §7. Tests

New file `backend/tests/scrapers/test_ao3_bulk_selector.py`:

- **`test_bulk_picks_chapter_body_not_summary_blockquote`** — feed a hand-crafted HTML fixture with `div#chapter-1` containing both a summary `<blockquote class="userstuff">` (~20 words) and a body `<div class="userstuff module" role="article">` (~3000 words). Assert the parsed dict's chapter 1 text contains body markers and not summary markers, and `len(text.split()) > 1000`.
- **`test_bulk_handles_chapter_without_summary`** — fixture with body only, assert it still parses correctly.
- **`test_get_chapter_text_picks_body_not_summary`** — same fixture pattern for the per-chapter path.

New file `backend/tests/scrapers/test_validation.py` — tests the pure helper from §3 directly (no DB, no ARQ, no fixtures beyond pytest):

- **`test_rejects_below_ratio_threshold`** — `validate_chapter_content(word_count=200, fanfic_word_count=10000, fanfic_total_chapters=10, allow_short=False)` → `(False, "...")`. (expected_avg=1000, threshold=300, 200 < 300)
- **`test_accepts_above_ratio_threshold`** — same fanfic metadata, word_count=4000 → `(True, None)`.
- **`test_rejects_below_hard_floor_even_when_metadata_missing`** — `word_count=30, fanfic_word_count=None` → `(False, "...hard floor of 50")`.
- **`test_bypassed_by_allow_short_flag`** — `word_count=80, fanfic_word_count=10000, total_chapters=10, allow_short=True` → `(True, None)`.
- **`test_accepts_when_metadata_missing_and_above_floor`** — `word_count=100, fanfic_word_count=None` → `(True, None)`. (Can't judge ratio → only the floor applies.)
- **`test_rejects_below_ratio_when_chapters_only_one`** — `word_count=200, fanfic_word_count=5000, fanfic_total_chapters=1` (expected_avg=5000, threshold=1500). 200 < 1500 → `(False, "...")`.

All tests are sync, no fixtures needed. Pure-function tests.

## Branch and commit shape

Branch: `feature/ast-20-ao3-bulk-selector`, cut from `origin/development`.

Planned commit sequence:

1. `[backend] AST-20 add diagnostic logs to AO3 bulk parser` — only the `logger.info` lines from §4. Lands first so that if §2 still misbehaves on some work, the logs are already there.
2. `[backend] AST-20 fix AO3 bulk and per-chapter selectors — target chapter body, not summary blockquote` — the §2 selector tightening, with the bulk-selector unit tests from §7.
3. `[backend] AST-20 add allow_short_chapters column to fanfics` — the §6 migration plus the SQLAlchemy column.
4. `[backend] AST-20 add short-content guard with per-fanfic opt-out` — the §3 guard logic in `fanfic_scrape_task`, the constants, the guard tests from §7.
5. `[backend] AST-20 add rescrape_short_chapters backfill script` — the §5 script.

PR target: `development`.

## Acceptance

- "Correctional Officer Arc" re-scrapes (manual delta trigger) produce chapters with word counts roughly matching the AO3 page's per-chapter counts (eyeballed; the work's `word_count / total_chapters` ratio puts each chapter in the multi-thousand-word range).
- The histogram SQL after backfill returns zero rows for `source_key='ao3'` (modulo any work flagged with `allow_short_chapters=true`).
- A new scrape on a hypothetical broken-selector regression fails the affected chapters loud — `scrape_status='failed'`, `error_type='ShortContent'` in `scrape_logs`, `job.status='partial'`.
- `bulk_parsed` log lines appear in the worker stdout for every chapter on every AO3 scrape, including raw and final character counts.
