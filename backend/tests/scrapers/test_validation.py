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
