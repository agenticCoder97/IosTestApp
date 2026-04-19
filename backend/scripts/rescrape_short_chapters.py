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
from sqlalchemy import text

# Allow `python scripts/...` from the backend root.
sys.path.insert(0, ".")

from app.db.database import AsyncSessionLocal
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
