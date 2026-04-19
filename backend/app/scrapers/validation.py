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
