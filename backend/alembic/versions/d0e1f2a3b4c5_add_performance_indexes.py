"""add performance indexes for frequently filtered/sorted columns

Revision ID: d0e1f2a3b4c5
Revises: c9d4e5f6a7b8
Create Date: 2026-04-08 12:00:00.000000
"""
from typing import Sequence, Union
from alembic import op


revision: str = 'd0e1f2a3b4c5'
down_revision: Union[str, None] = 'c9d4e5f6a7b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Comics — soft-delete filter + sort columns
    op.create_index('ix_comics_deleted_at', 'comics', ['deleted_at'])
    op.create_index('ix_comics_created_at', 'comics', ['created_at'])
    op.create_index('ix_comics_updated_at', 'comics', ['updated_at'])

    # Fanfics — soft-delete + filter + sort columns
    op.create_index('ix_fanfics_deleted_at', 'fanfics', ['deleted_at'])
    op.create_index('ix_fanfics_created_at', 'fanfics', ['created_at'])
    op.create_index('ix_fanfics_rating', 'fanfics', ['rating'])
    op.create_index('ix_fanfics_completion_status', 'fanfics', ['completion_status'])
    op.create_index('ix_fanfics_updated_at_source', 'fanfics', ['updated_at_source'])

    # Fanfic chapters — FK join key
    op.create_index('ix_fanfic_chapters_fanfic_id', 'fanfic_chapters', ['fanfic_id'])
    op.create_index('ix_fanfic_chapters_deleted_at', 'fanfic_chapters', ['deleted_at'])

    # Comic chapters — FK join key
    op.create_index('ix_comic_chapters_comic_id', 'comic_chapters', ['comic_id'])
    op.create_index('ix_comic_chapters_deleted_at', 'comic_chapters', ['deleted_at'])

    # Pages — FK join key
    op.create_index('ix_pages_chapter_id', 'pages', ['chapter_id'])

    # Scrape jobs — story lookup + status filter
    op.create_index('ix_scrape_jobs_story_id', 'scrape_jobs', ['story_id'])
    op.create_index('ix_scrape_jobs_status', 'scrape_jobs', ['status'])
    op.create_index('ix_scrape_jobs_deleted_at', 'scrape_jobs', ['deleted_at'])
    op.create_index('ix_scrape_jobs_created_at', 'scrape_jobs', ['created_at'])

    # Reading progress — content_type filter + story lookup
    op.create_index('ix_reading_progress_content_type', 'reading_progress', ['content_type'])
    op.create_index('ix_reading_progress_story_id', 'reading_progress', ['story_id'])


def downgrade() -> None:
    op.drop_index('ix_reading_progress_story_id')
    op.drop_index('ix_reading_progress_content_type')
    op.drop_index('ix_scrape_jobs_created_at')
    op.drop_index('ix_scrape_jobs_deleted_at')
    op.drop_index('ix_scrape_jobs_status')
    op.drop_index('ix_scrape_jobs_story_id')
    op.drop_index('ix_pages_chapter_id')
    op.drop_index('ix_comic_chapters_deleted_at')
    op.drop_index('ix_comic_chapters_comic_id')
    op.drop_index('ix_fanfic_chapters_deleted_at')
    op.drop_index('ix_fanfic_chapters_fanfic_id')
    op.drop_index('ix_fanfics_updated_at_source')
    op.drop_index('ix_fanfics_completion_status')
    op.drop_index('ix_fanfics_rating')
    op.drop_index('ix_fanfics_created_at')
    op.drop_index('ix_fanfics_deleted_at')
    op.drop_index('ix_comics_updated_at')
    op.drop_index('ix_comics_created_at')
    op.drop_index('ix_comics_deleted_at')
