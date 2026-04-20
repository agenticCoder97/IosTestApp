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
