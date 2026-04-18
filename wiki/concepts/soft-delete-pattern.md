# Soft Delete Pattern

> How content deletion works: soft delete on the API, hard delete on a nightly cron.

## How It Works

1. **DELETE request** (e.g., `DELETE /comics/{id}`) sets `deleted_at = now()` on the row
2. Row is excluded from normal queries (WHERE deleted_at IS NULL)
3. **cleanup_task** runs nightly at 03:00 UTC
4. Hard-deletes rows where `deleted_at < now() - SOFT_DELETE_DAYS` (default: 5 days)
5. Cascade: deleting a Comic also removes its ComicChapters, Pages, join table rows

## Tables with Soft Delete

| Table | Column |
|-------|--------|
| comics | deleted_at |
| fanfics | deleted_at |

## Configuration

| Env Variable | Default | Description |
|-------------|---------|-------------|
| SOFT_DELETE_DAYS | 5 | Days before hard-delete |

## Cleanup Task

**File:** `backend/app/tasks/cleanup_task.py`
**Schedule:** Nightly at 03:00 UTC (ARQ cron)
**Logic:** `DELETE FROM table WHERE deleted_at < now() - interval {SOFT_DELETE_DAYS} days`

## Why Soft Delete

- **Undo window:** User can accidentally delete a story. 5-day window before permanent loss.
- **No re-scrape needed:** If caught in time, the story can be restored.
- **Clean queries:** Active data always filtered by `deleted_at IS NULL`.
