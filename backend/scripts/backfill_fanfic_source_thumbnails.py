"""Backfill AO3 fanfics with source-work thumbnails.

This replaces only missing or generic fanfic thumbnails. It leaves already
resolved source thumbnails and any manually assigned images untouched.
"""

import argparse
import asyncio

from sqlalchemy import or_, select

from app.core.config import settings
from app.db.database import AsyncSessionLocal
from app.models.fanfic import Fanfic
from app.services.fanfic_source_thumbnail_resolver import (
    ao3_source_candidates,
    is_generic_fanfic_thumbnail,
    resolve_fanfic_source_thumbnail,
)
from app.utils.image_utils import ensure_fanfic_covers, random_fanfic_cover


async def backfill(limit: int | None, dry_run: bool, delay_seconds: float) -> None:
    async with AsyncSessionLocal() as db:
        stmt = (
            select(Fanfic)
            .where(
                Fanfic.deleted_at.is_(None),
                Fanfic.source_key == "ao3",
                or_(
                    Fanfic.thumbnail_path.is_(None),
                    Fanfic.thumbnail_path.like("fanfic-covers/%"),
                    Fanfic.thumbnail_path.like("fanfic-thumbnails/%"),
                ),
            )
            .order_by(Fanfic.updated_at.desc())
        )
        if limit:
            stmt = stmt.limit(limit)

        fanfics = list((await db.execute(stmt)).scalars().all())
        checked = resolved = fallback = 0
        source_cache: dict[tuple[str, ...], str | None] = {}

        for fanfic in fanfics:
            if not is_generic_fanfic_thumbnail(fanfic.thumbnail_path):
                continue
            checked += 1
            source_key = tuple(ao3_source_candidates(fanfic.fandom))
            source_path = source_cache.get(source_key)
            if source_key and source_key not in source_cache:
                source_path = await resolve_fanfic_source_thumbnail(fanfic, settings.block_volume_path)
                source_cache[source_key] = source_path
                if delay_seconds > 0:
                    await asyncio.sleep(delay_seconds)
            if source_path:
                resolved += 1
                print(f"resolved: {fanfic.title!r} -> {source_path}")
                if not dry_run:
                    fanfic.thumbnail_path = source_path
            elif not fanfic.thumbnail_path:
                fallback += 1
                print(f"fallback: {fanfic.title!r} -> random generic")
                if not dry_run:
                    ensure_fanfic_covers(settings.block_volume_path)
                    fanfic.thumbnail_path = random_fanfic_cover()

        if dry_run:
            await db.rollback()
        else:
            await db.commit()

        print(f"checked={checked} resolved={resolved} fallback={fallback} dry_run={dry_run}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--delay-seconds", type=float, default=1.0)
    args = parser.parse_args()
    asyncio.run(backfill(limit=args.limit, dry_run=args.dry_run, delay_seconds=args.delay_seconds))


if __name__ == "__main__":
    main()
