# AST-19 Permanent Delete — Backend Plan (PR 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan.

**Goal:** Backend endpoints + services + ARQ job that hard-delete a comic/fanfic and its dependencies immediately, bypassing the 5-day soft-delete window.

**Architecture:** Two new subroutes (`/permanent`) calling new `permanent_delete_*` service functions. Each function deletes dependent rows in FK-safe order, commits, invalidates Redis cache, then enqueues a best-effort media-wipe ARQ job. Idempotent: unknown ids return 204 (the iOS retry queue depends on this).

**Tech Stack:** FastAPI, SQLAlchemy async, ARQ, Redis, pytest. Run locally via `docker-compose.local.yml`.

**Spec:** [docs/superpowers/specs/2026-04-17-ast-19-permanent-delete-design.md](../specs/2026-04-17-ast-19-permanent-delete-design.md)

**Branch:** `feature/ast-19-permanent-delete-backend` (off `origin/development`, already checked out)

**Scope note:** This PR ships backend-only. The iOS client continues to use the existing soft-delete endpoint until PR 2 lands. Deploying this PR is safe — no breaking change.

---

### Task 1: Inspect FK constraints and existing delete paths

**Files:**
- Read: `backend/app/models/comic.py`, `backend/app/models/fanfic.py`, `backend/app/models/scrape.py`, `backend/app/models/progress.py`

- [ ] **Step 1: Document the FK graph**

Read each model file, note every `ForeignKey`, `relationship`, and `ondelete` directive that involves `Comic`, `ComicChapter`, `Page`, `Fanfic`, `FanficChapter`, `ScrapeJob`, `ReadingProgress`.

Produce (as plain notes in your head or a scratch pad — no file needed) the FK order required for hard-delete. Expected, per the spec:
- Comic: `Page` → `ComicChapter` → `ScrapeJob (content='comic')` → `ReadingProgress (comic_id)` → `Comic`.
- Fanfic: `FanficChapter` → `ScrapeJob (content='fanfic')` → `ReadingProgress (fanfic_id?)` → `Fanfic`.

Confirm whether any FK already has `ondelete="CASCADE"` — if so, you can skip the manual child delete. The spec's explicit delete order is a safe default.

- [ ] **Step 2: Confirm media paths**

Grep `backend/app/services/comic_service.py` for directory patterns: `astral-media`, `/mnt/`, `comics/{comic_id}`. Note the exact path format used by the thumbnail/page save code.

Grep `fanfic_service.py` similarly. If fanfic has no page-storage (only thumbnails), the fanfic media-wipe job is just a thumbnail delete.

- [ ] **Step 3: No commit**

This task is read-only. Just understand the graph before writing code.

---

### Task 2: Implement `permanent_delete_comic` service + ARQ media-wipe task

**Files:**
- Modify: `backend/app/services/comic_service.py`
- Create: `backend/app/tasks/comic_media_wipe_task.py`
- Modify: `backend/app/worker/worker.py` (or wherever the ARQ task list is registered — find it via `grep -rn "auto_update_task\|cleanup_task" backend/app/worker`)

- [ ] **Step 1: Write the failing test**

Create `backend/tests/services/test_comic_service_permanent_delete.py`:

```python
import pytest
import uuid
from app.services.comic_service import permanent_delete_comic


@pytest.mark.asyncio
async def test_permanent_delete_comic_removes_rows_and_returns_true(db_session, seeded_comic):
    # seeded_comic fixture should create a Comic with 1 chapter and 2 pages
    comic_id = seeded_comic.id

    result = await permanent_delete_comic(db_session, comic_id)
    assert result is True

    # Verify all rows gone
    from app.models.comic import Comic, ComicChapter, Page
    from sqlalchemy import select
    assert (await db_session.execute(select(Comic).where(Comic.id == comic_id))).scalar_one_or_none() is None
    assert (await db_session.execute(select(ComicChapter).where(ComicChapter.comic_id == comic_id))).scalars().all() == []
    # Pages are FK'd to chapters; if chapters gone, pages should be too


@pytest.mark.asyncio
async def test_permanent_delete_comic_unknown_id_returns_true(db_session):
    random_id = uuid.uuid4()
    result = await permanent_delete_comic(db_session, random_id)
    assert result is True  # Idempotent
```

Check `backend/tests/conftest.py` for existing fixtures (`db_session`, `seeded_comic` may need to be added — match the pattern of other service tests under `backend/tests/services/`). If no equivalent fixture exists, add a minimal one inline in the test file.

- [ ] **Step 2: Run the test, confirm it fails**

```bash
cd backend && docker compose -f docker-compose.local.yml exec backend pytest tests/services/test_comic_service_permanent_delete.py -v
```

Expected: `AttributeError: module 'app.services.comic_service' has no attribute 'permanent_delete_comic'` or similar.

- [ ] **Step 3: Implement `permanent_delete_comic`**

In `backend/app/services/comic_service.py`, add after `soft_delete_comic` (around line 291):

```python
async def permanent_delete_comic(db: AsyncSession, comic_id: uuid.UUID) -> bool:
    """Hard-delete a comic and all its dependent rows. Idempotent."""
    logger.info("permanent_delete_comic called | comic_id=%s", comic_id)

    # Delete in FK order: pages → chapters → scrape jobs → reading progress → comic
    await db.execute(
        delete(Page).where(
            Page.chapter_id.in_(select(ComicChapter.id).where(ComicChapter.comic_id == comic_id))
        )
    )
    await db.execute(delete(ComicChapter).where(ComicChapter.comic_id == comic_id))
    await db.execute(
        delete(ScrapeJob).where(
            and_(ScrapeJob.story_id == comic_id, ScrapeJob.content_type == "comic")
        )
    )
    # ReadingProgress: column name and presence vary — verify and include if applicable
    # await db.execute(delete(ReadingProgress).where(ReadingProgress.comic_id == comic_id))
    await db.execute(delete(Comic).where(Comic.id == comic_id))
    await db.commit()

    await redis_cache.invalidate_comics(str(comic_id))

    # Best-effort media wipe
    try:
        import arq
        from app.core.config import settings
        arq_redis = await arq.create_pool(settings.arq_redis_settings)
        await arq_redis.enqueue_job("comic_media_wipe_task", str(comic_id))
        await arq_redis.aclose()
    except Exception as e:
        logger.warning("permanent_delete_comic ARQ enqueue failed | comic_id=%s error=%s", comic_id, e)

    return True
```

Add the required imports at the top of the file (match existing style):

```python
from sqlalchemy import delete, select, and_
from app.models.comic import Comic, ComicChapter, Page
from app.models.scrape import ScrapeJob
```

(The specific `ReadingProgress` column name depends on Task 1 Step 1's findings — include the delete only if the comic has a direct FK to it. If reading progress cascades via chapter/comic on delete, skip this line.)

- [ ] **Step 4: Create the ARQ job**

Create `backend/app/tasks/comic_media_wipe_task.py`:

```python
import logging
import shutil
from pathlib import Path
from app.core.config import settings

logger = logging.getLogger(__name__)


async def comic_media_wipe_task(ctx, comic_id: str):
    """Best-effort: delete /mnt/astral-media/comics/{comic_id}/. Never raises."""
    media_root = Path(settings.astral_media_root if hasattr(settings, "astral_media_root") else "/mnt/astral-media")
    target = media_root / "comics" / comic_id
    try:
        shutil.rmtree(target, ignore_errors=True)
        logger.info("comic_media_wipe_task done | comic_id=%s target=%s", comic_id, target)
    except Exception as e:
        logger.warning("comic_media_wipe_task failed | comic_id=%s error=%s", comic_id, e)
```

Verify the settings path key by grep: `grep -rn "astral_media\|media_root" backend/app/core/config.py`. If the key has a different name, substitute.

- [ ] **Step 5: Register the ARQ task**

Find the ARQ worker config (likely `backend/app/worker/worker.py` or similar — use `grep -rn "functions.*=.*\[" backend/app/worker/`). Add `comic_media_wipe_task` to the `functions` list, imported at top of the file:

```python
from app.tasks.comic_media_wipe_task import comic_media_wipe_task
# ...
functions = [
    cleanup_task,
    auto_update_task,
    comic_scrape_task,
    fanfic_scrape_task,
    comic_archive_task,
    comic_unarchive_task,
    comic_media_wipe_task,  # NEW
]
```

- [ ] **Step 6: Run the test, confirm it passes**

```bash
cd backend && docker compose -f docker-compose.local.yml exec backend pytest tests/services/test_comic_service_permanent_delete.py -v
```

Expected: `PASSED` on both test cases.

- [ ] **Step 7: Commit**

```bash
git add backend/app/services/comic_service.py \
        backend/app/tasks/comic_media_wipe_task.py \
        backend/app/worker/worker.py \
        backend/tests/services/test_comic_service_permanent_delete.py
git commit -m "[backend] AST-19 permanent_delete_comic service + media wipe task

Hard-delete comic + chapters + pages + scrape jobs in FK-safe order,
commit, invalidate Redis cache, enqueue best-effort media wipe ARQ
job. Idempotent: unknown comic_id returns True so the iOS retry queue
can drain safely.

New ARQ task comic_media_wipe_task: rmtree /mnt/astral-media/comics/{id}
with ignore_errors=True. Registered in worker functions list."
```

---

### Task 3: Implement `permanent_delete_fanfic` service + ARQ job

Mirror of Task 2 for fanfic. Same structure, different models.

**Files:**
- Modify: `backend/app/services/fanfic_service.py`
- Create: `backend/app/tasks/fanfic_media_wipe_task.py` (only if fanfic has a media directory; otherwise skip this file and do the thumbnail delete inline in the service)
- Modify: `backend/app/worker/worker.py` (register the new task if created)

- [ ] **Step 1: Write the failing test**

Create `backend/tests/services/test_fanfic_service_permanent_delete.py` mirroring the comic test. Adjust models: `Fanfic`, `FanficChapter`, no `Page` (fanfic content is stored inline, not as separate page rows — confirm via Task 1's notes).

- [ ] **Step 2: Run test, confirm failure**

```bash
cd backend && docker compose -f docker-compose.local.yml exec backend pytest tests/services/test_fanfic_service_permanent_delete.py -v
```

Expected: `AttributeError` on `permanent_delete_fanfic`.

- [ ] **Step 3: Implement `permanent_delete_fanfic`**

In `backend/app/services/fanfic_service.py`, after `soft_delete_fanfic` (around line 180):

```python
async def permanent_delete_fanfic(db: AsyncSession, fanfic_id: uuid.UUID) -> bool:
    """Hard-delete a fanfic and dependent rows. Idempotent."""
    logger.info("permanent_delete_fanfic called | fanfic_id=%s", fanfic_id)

    await db.execute(delete(FanficChapter).where(FanficChapter.fanfic_id == fanfic_id))
    await db.execute(
        delete(ScrapeJob).where(
            and_(ScrapeJob.story_id == fanfic_id, ScrapeJob.content_type == "fanfic")
        )
    )
    # ReadingProgress: verify column name and include if applicable
    await db.execute(delete(Fanfic).where(Fanfic.id == fanfic_id))
    await db.commit()

    await redis_cache.invalidate_fanfic(str(fanfic_id))  # Verify method name

    # Best-effort media wipe (thumbnail only for fanfic — no page directory)
    try:
        import arq
        from app.core.config import settings
        arq_redis = await arq.create_pool(settings.arq_redis_settings)
        await arq_redis.enqueue_job("fanfic_media_wipe_task", str(fanfic_id))
        await arq_redis.aclose()
    except Exception as e:
        logger.warning("permanent_delete_fanfic ARQ enqueue failed | fanfic_id=%s error=%s", fanfic_id, e)

    return True
```

Add imports mirroring the comic version.

- [ ] **Step 4: Create the ARQ job** (only if fanfic has a media dir; otherwise inline the thumbnail delete in the service and skip this step)

Create `backend/app/tasks/fanfic_media_wipe_task.py`:

```python
import logging
from pathlib import Path
from app.core.config import settings

logger = logging.getLogger(__name__)


async def fanfic_media_wipe_task(ctx, fanfic_id: str):
    """Best-effort: delete fanfic thumbnail(s). Never raises."""
    media_root = Path(settings.astral_media_root if hasattr(settings, "astral_media_root") else "/mnt/astral-media")
    # Match existing fanfic thumbnail path convention (verify from fanfic_service save code)
    thumbnail = media_root / "fanfics" / f"{fanfic_id}.jpg"
    try:
        thumbnail.unlink(missing_ok=True)
        logger.info("fanfic_media_wipe_task done | fanfic_id=%s", fanfic_id)
    except Exception as e:
        logger.warning("fanfic_media_wipe_task failed | fanfic_id=%s error=%s", fanfic_id, e)
```

- [ ] **Step 5: Register the ARQ task**

Add `fanfic_media_wipe_task` to the `functions` list in `backend/app/worker/worker.py`.

- [ ] **Step 6: Run test, confirm pass**

```bash
cd backend && docker compose -f docker-compose.local.yml exec backend pytest tests/services/test_fanfic_service_permanent_delete.py -v
```

Expected: `PASSED`.

- [ ] **Step 7: Commit**

```bash
git add backend/app/services/fanfic_service.py \
        backend/app/tasks/fanfic_media_wipe_task.py \
        backend/app/worker/worker.py \
        backend/tests/services/test_fanfic_service_permanent_delete.py
git commit -m "[backend] AST-19 permanent_delete_fanfic service + media wipe task

Mirror of comic permanent-delete. Hard-delete fanfic + chapters +
scrape jobs, invalidate Redis cache, enqueue best-effort thumbnail
wipe. Idempotent."
```

---

### Task 4: Add `/permanent` routes

**Files:**
- Modify: `backend/app/api/v1/routes/comics.py`
- Modify: `backend/app/api/v1/routes/fanfic.py`

- [ ] **Step 1: Write route tests**

Create `backend/tests/routes/test_comic_permanent_route.py`:

```python
import pytest
import uuid


@pytest.mark.asyncio
async def test_permanent_delete_comic_route_returns_204(async_client, seeded_comic):
    response = await async_client.delete(f"/api/v1/comics/{seeded_comic.id}/permanent")
    assert response.status_code == 204


@pytest.mark.asyncio
async def test_permanent_delete_comic_route_unknown_id_returns_204(async_client):
    random_id = uuid.uuid4()
    response = await async_client.delete(f"/api/v1/comics/{random_id}/permanent")
    assert response.status_code == 204  # Idempotent
```

Check `backend/tests/routes/` for existing route-test conventions (fixture names may differ — look at `test_comics_route.py` if one exists). Create `backend/tests/routes/test_fanfic_permanent_route.py` mirroring the comic one.

- [ ] **Step 2: Run tests, confirm 404 / fail**

```bash
cd backend && docker compose -f docker-compose.local.yml exec backend pytest tests/routes/test_comic_permanent_route.py tests/routes/test_fanfic_permanent_route.py -v
```

Expected: route returns 405 Method Not Allowed or 404 (the route doesn't exist yet).

- [ ] **Step 3: Add comic route**

In `backend/app/api/v1/routes/comics.py`, after the existing `delete_comic` at line 68-72, add:

```python
@router.delete("/{comic_id}/permanent", status_code=204)
async def permanent_delete_comic_route(comic_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    await comic_service.permanent_delete_comic(db, comic_id)
    # Idempotent: always 204, even for unknown ids
```

- [ ] **Step 4: Add fanfic route**

In `backend/app/api/v1/routes/fanfic.py`, after the existing `delete_fanfic` at line 49-53:

```python
@router.delete("/{fanfic_id}/permanent", status_code=204)
async def permanent_delete_fanfic_route(fanfic_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    await fanfic_service.permanent_delete_fanfic(db, fanfic_id)
```

- [ ] **Step 5: Run tests, confirm pass**

```bash
cd backend && docker compose -f docker-compose.local.yml exec backend pytest tests/routes/test_comic_permanent_route.py tests/routes/test_fanfic_permanent_route.py -v
```

Expected: both test files pass (4 cases).

- [ ] **Step 6: Full backend test sweep**

```bash
cd backend && docker compose -f docker-compose.local.yml exec backend pytest -x
```

Expected: all existing tests still pass.

- [ ] **Step 7: Commit**

```bash
git add backend/app/api/v1/routes/comics.py \
        backend/app/api/v1/routes/fanfic.py \
        backend/tests/routes/test_comic_permanent_route.py \
        backend/tests/routes/test_fanfic_permanent_route.py
git commit -m "[backend] AST-19 DELETE /permanent routes for comic and fanfic

Both routes call the new permanent_delete_* service and return 204,
regardless of whether the target row existed (idempotent). iOS retry
queue depends on 204-for-unknown-id behavior."
```

---

### Task 5: Integration test — hit a live dev backend

- [ ] **Step 1: Start the local stack**

```bash
cd backend && docker compose -f docker-compose.local.yml up -d
```

Wait ~10s for backend + worker + db to be ready. Verify with `curl http://localhost:8000/api/v1/health`.

- [ ] **Step 2: Seed a throwaway comic via the API**

```bash
# If there's an existing script or curl pattern for creating a comic via scrape,
# use it. Otherwise, query an existing comic id from the DB:
docker compose -f docker-compose.local.yml exec backend python -c "
from app.db.database import AsyncSessionLocal
from app.models.comic import Comic
from sqlalchemy import select
import asyncio

async def main():
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(Comic).limit(1))
        comic = result.scalar_one_or_none()
        print(comic.id if comic else 'NO COMIC')
asyncio.run(main())
"
```

Note the returned UUID.

- [ ] **Step 3: Hit the permanent-delete endpoint**

```bash
curl -v -X DELETE "http://localhost:8000/api/v1/comics/{UUID}/permanent"
```

Expected: `HTTP/1.1 204 No Content`.

- [ ] **Step 4: Verify DB state**

```bash
docker compose -f docker-compose.local.yml exec postgres psql -U astral -d astral -c "SELECT COUNT(*) FROM comics WHERE id = '{UUID}';"
```

Expected: `count = 0`.

Same for chapters:

```bash
docker compose -f docker-compose.local.yml exec postgres psql -U astral -d astral -c "SELECT COUNT(*) FROM comic_chapters WHERE comic_id = '{UUID}';"
```

Expected: `count = 0`.

- [ ] **Step 5: Verify idempotency**

Run the `curl` again with the same UUID.

Expected: `HTTP/1.1 204 No Content` (not 404).

- [ ] **Step 6: Verify media wipe fired (best-effort)**

Check worker logs:

```bash
docker compose -f docker-compose.local.yml logs arq_worker | grep "comic_media_wipe"
```

Expected: a log line per invocation. If media root had files, verify they're gone: `docker compose -f docker-compose.local.yml exec backend ls /mnt/astral-media/comics/{UUID} 2>&1` — expected "No such file or directory."

- [ ] **Step 7: If any check fails**

Stop. Describe symptom and return to the failing task.

---

### Task 6: Push branch and open PR

- [ ] **Step 1: Push**

```bash
git push -u origin feature/ast-19-permanent-delete-backend
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --base development --title "[backend] AST-19 permanent delete endpoints (comic + fanfic)" --body "$(cat <<'EOF'
## Summary

First of two PRs for AST-19. Backend-only.

- New `DELETE /api/v1/comics/{id}/permanent` and `DELETE /api/v1/fanfic/{id}/permanent` routes.
- New `permanent_delete_comic` / `permanent_delete_fanfic` services: hard-delete the row + dependent children in FK-safe order, invalidate Redis cache, enqueue best-effort media-wipe ARQ job.
- New `comic_media_wipe_task` / `fanfic_media_wipe_task` ARQ jobs.
- Existing soft-delete endpoints and `cleanup_task` cron unchanged.
- Idempotent: unknown ids return 204 (iOS retry queue depends on this).

Part of [AST-19](https://linear.app/nnetraganti/issue/AST-19/library-add-permanent-delete-long-press-on-library-item-and-action-in). iOS wiring lands in a follow-up PR after this ships.

Spec: `docs/superpowers/specs/2026-04-17-ast-19-permanent-delete-design.md`

## Test plan

- [x] Unit tests for both services (happy path + unknown-id idempotent path)
- [x] Route tests for both endpoints
- [x] Full `pytest -x` sweep passes
- [x] Integration: `curl -X DELETE` against live dev backend returns 204, DB rows are gone, worker logs show media wipe task fired, second call to same id also returns 204

## Deploy note

This PR can ship independently. No iOS client needs updating — the existing soft-delete endpoints continue to work. PR 2 (iOS) will only merge once this is deployed.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

- [ ] **Step 3: Report PR URL**

---

## Self-review

**Spec coverage:**
- New routes → Task 4 ✓
- Service hard-delete in FK order → Tasks 2, 3 ✓
- Redis cache invalidation → Tasks 2, 3 ✓
- ARQ media wipe → Tasks 2, 3 ✓
- Idempotent 204 for unknown ids → Tasks 2, 4 ✓
- Keep soft-delete path working → Tasks 2, 3, 4 (no change to existing endpoints) ✓

**Placeholder scan:** none that aren't explicit "verify during implementation" instructions (FK cascade behavior, settings key names, fixture names). Each verification has a concrete grep/check to run.

**Known sharp edges:**
- Worker file location may not be `backend/app/worker/worker.py` — Task 2 Step 5 includes the grep to find it.
- `ReadingProgress` column name depends on the model — Task 1 Step 1's FK graph feeds Task 2's implementation.
- `arq_redis_settings` key on `settings` — verify via `grep arq_redis backend/app/core/config.py`. If different, substitute.
