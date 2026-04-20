"""
MangaDex title matcher (AST-30).

Scores a candidate match between a toongod/hentai20 series and a MangaDex
search result. Pure scoring service — no DB writes.

Score formula (sums to 1.0):
    0.55 × title similarity (rapidfuzz token_set_ratio / 100)
    0.15 × original-language match (1.0 if matches expected for source)
    0.15 × tag Jaccard overlap
    0.15 × chapter-count delta within ±20%

Threshold: settings.mangadex_title_match_threshold (default 0.85).
"""
import logging
import re
import unicodedata
from dataclasses import asdict, dataclass
from typing import Optional

from rapidfuzz import fuzz

from app.core.config import settings
from app.scrapers.comic.mangadex import MangadexScraper

logger = logging.getLogger(__name__)

_EXPECTED_LANG = {
    "toongod": "ko",
    "hentai20": "ja",
}

_NORMALIZE_DROP = re.compile(r"\b(vol(?:ume)?\.?|ch(?:apter)?\.?|ep(?:isode)?\.?|\d+)\b", re.I)
_NON_ALNUM = re.compile(r"[^a-z0-9 ]+")
_MULTI_WS = re.compile(r"\s+")


@dataclass
class MangaDexMatch:
    manga_id: str
    mangadex_url: str
    title: str
    confidence: float
    thumbnail_url: Optional[str]
    chapter_count: int
    source_chapter_count: int

    def to_dict(self) -> dict:
        return asdict(self)


def _normalize(s: str) -> str:
    if not s:
        return ""
    s = unicodedata.normalize("NFKD", s)
    s = "".join(c for c in s if not unicodedata.combining(c))
    s = s.lower()
    s = _NORMALIZE_DROP.sub(" ", s)
    s = _NON_ALNUM.sub(" ", s)
    s = _MULTI_WS.sub(" ", s).strip()
    return s


def _score(
    candidate: dict,
    *,
    source_title: str,
    expected_lang: Optional[str],
    source_tags: set[str],
    source_chapter_count: int,
) -> float:
    title_sim = (
        fuzz.token_set_ratio(_normalize(source_title), _normalize(candidate["title"])) / 100.0
    )
    lang_match = 1.0 if (
        expected_lang and candidate.get("original_language") == expected_lang
    ) else 0.0
    md_tags = {t.lower() for t in candidate.get("tags", []) if t}
    src_tags_lc = {t.lower() for t in source_tags if t}
    if not md_tags and not src_tags_lc:
        tag_jaccard = 0.0
    else:
        union = md_tags | src_tags_lc
        tag_jaccard = (len(md_tags & src_tags_lc) / len(union)) if union else 0.0
    md_chapter_count = candidate.get("last_chapter", 0) or 0
    if source_chapter_count > 0 and md_chapter_count > 0:
        delta_pct = abs(md_chapter_count - source_chapter_count) / source_chapter_count
        chapter_match = 1.0 if delta_pct <= 0.20 else 0.0
    else:
        chapter_match = 0.0
    return (
        0.55 * title_sim
        + 0.15 * lang_match
        + 0.15 * tag_jaccard
        + 0.15 * chapter_match
    )


async def find_mangadex_match(
    *,
    source: str,
    source_url: str,
    source_title: str,
) -> Optional[MangaDexMatch]:
    """Return a MangaDexMatch if best score >= threshold, else None."""
    if settings.mangadex_disabled:
        logger.info("find_mangadex_match skipped — kill switch on")
        return None
    if not settings.mangadex_auto_switch_source:
        logger.info("find_mangadex_match skipped — auto-switch disabled")
        return None
    if source not in _EXPECTED_LANG:
        logger.debug("find_mangadex_match skipped — source %s not eligible", source)
        return None

    # Fetch source-side metadata (tags + chapter count) using the existing scraper
    # registry. Imported here to avoid circular import at module load.
    from app.tasks.comic_scrape_task import SCRAPER_REGISTRY

    source_scraper_cls = SCRAPER_REGISTRY.get(source)
    if source_scraper_cls is None:
        logger.warning("find_mangadex_match: no scraper registered for %s", source)
        return None
    # Source-meta fetch may fail (Cloudflare 403 on the API thread, since the
    # fastapi container lacks chromium for the headless fallback). Degrade
    # gracefully to title+lang scoring instead of bailing entirely.
    src_tags: set[str] = set()
    src_chapter_count: int = 0
    has_source_meta = False
    try:
        src_meta = await source_scraper_cls().get_story_metadata(source_url)
        src_tags = {t.get("name", "") for t in (src_meta.tags or [])}
        src_chapter_count = src_meta.total_chapters or 0
        has_source_meta = True
    except Exception as e:
        logger.warning(
            "find_mangadex_match source meta unavailable; falling back to title+lang | err=%s",
            e,
        )

    md = MangadexScraper()
    try:
        candidates = await md.search(
            title=_normalize(source_title) or source_title,
            content_ratings=["safe", "suggestive", "erotica"],
            limit=10,
        )
    except Exception as e:
        logger.warning("find_mangadex_match mangadex search failed | err=%s", e)
        return None

    best: Optional[tuple[float, dict]] = None
    for c in candidates:
        s = _score(
            c,
            source_title=source_title,
            expected_lang=_EXPECTED_LANG[source],
            source_tags=src_tags,
            source_chapter_count=src_chapter_count,
        )
        if best is None or s > best[0]:
            best = (s, c)

    # Threshold: when source meta is missing, only title (0.55) + lang (0.15)
    # signals contribute (max 0.70). Rescale the configured threshold so the
    # same "≥X% of available evidence agrees" semantics apply.
    if has_source_meta:
        threshold = settings.mangadex_title_match_threshold
    else:
        threshold = settings.mangadex_title_match_threshold * 0.70

    if best is None or best[0] < threshold:
        logger.info(
            "find_mangadex_match no qualifying match | source=%s best=%.3f threshold=%.3f has_meta=%s",
            source, best[0] if best else 0.0, threshold, has_source_meta,
        )
        return None

    score, cand = best
    # Display confidence rescaled to 0-1 in the title-only fallback so the user
    # sees a comparable percentage in the dialog.
    display_confidence = score / 0.70 if not has_source_meta else score
    display_confidence = min(1.0, display_confidence)
    logger.info(
        "find_mangadex_match hit | source=%s candidate=%s raw=%.3f display=%.3f has_meta=%s",
        source, cand["id"], score, display_confidence, has_source_meta,
    )
    return MangaDexMatch(
        manga_id=cand["id"],
        mangadex_url=f"https://mangadex.org/title/{cand['id']}",
        title=cand["title"],
        confidence=round(display_confidence, 3),
        thumbnail_url=cand.get("thumbnail_url"),
        chapter_count=cand.get("last_chapter", 0) or 0,
        source_chapter_count=src_chapter_count,
    )
