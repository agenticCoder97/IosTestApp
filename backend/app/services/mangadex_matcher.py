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

# Trailing slug noise on aggregator URLs that doesn't belong in a title query.
_SLUG_NOISE = re.compile(r"\b(manhwa|manga|webtoon|raw|uncensored|official|english)\b", re.I)


def _title_from_url(url: str) -> str:
    """Best-effort title extraction from a /webtoon/<slug>/ or /manga/<slug>/ URL.
    Used as a fallback when iOS didn't capture document.title."""
    from urllib.parse import urlparse
    path = urlparse(url).path.rstrip("/")
    if not path:
        return ""
    slug = path.rsplit("/", 1)[-1]
    title = slug.replace("-", " ").replace("_", " ")
    title = _SLUG_NOISE.sub(" ", title)
    return _MULTI_WS.sub(" ", title).strip()


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
    # Title sim against MAX of (main title + altTitles). Manhwa often live on
    # MangaDex under their original-language title (e.g. "Na Honjaman Level-Up")
    # with English in altTitles ("Solo Leveling") — without checking altTitles
    # we'd pick a worse duplicate that happens to use English in its main title.
    src_norm = _normalize(source_title)
    candidates_to_check = [candidate.get("title", "")] + list(candidate.get("alt_titles", []))
    title_sim = max(
        (fuzz.token_set_ratio(src_norm, _normalize(t)) / 100.0)
        for t in candidates_to_check if t
    ) if candidates_to_check else 0.0
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
    from app.core.runtime_flags import flag_enabled
    if await flag_enabled("MANGADEX_DISABLED", default=settings.mangadex_disabled):
        logger.info("find_mangadex_match skipped — kill switch on")
        return None
    if not await flag_enabled(
        "MANGADEX_AUTO_SWITCH_SOURCE", default=settings.mangadex_auto_switch_source,
    ):
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

    # Build the search query. Prefer the URL slug (toongod/hentai20 use clean
    # slug-as-title patterns: /webtoon/solo-leveling/ → "solo leveling").
    # Use the iOS page title only as a last-resort fallback — aggregator pages
    # ship SEO-noisy <title> like "Solo Leveling Manhwa in English Online Free
    # Chapters | ToonGod" which doesn't match anything on MangaDex.
    raw_title = (source_title or "").strip()
    slug_title = _title_from_url(source_url)
    if slug_title:
        search_title = _normalize(slug_title) or slug_title
    elif raw_title and not raw_title.startswith(("http://", "https://")):
        search_title = _normalize(raw_title) or raw_title
    else:
        search_title = _normalize(source_url)
    logger.info(
        "find_mangadex_match search | source=%s search_title=%r slug=%r raw=%r",
        source, search_title, slug_title, raw_title,
    )

    md = MangadexScraper()
    try:
        candidates = await md.search(
            title=search_title,
            content_ratings=["safe", "suggestive", "erotica"],
            limit=10,
        )
    except Exception as e:
        logger.warning("find_mangadex_match mangadex search failed | err=%s", e)
        return None

    best: Optional[tuple[float, dict]] = None
    # Score using search_title (cleaned/derived) so a junk source_title doesn't
    # tank similarity against the candidate's clean title.
    for c in candidates:
        s = _score(
            c,
            source_title=search_title,
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

    # Final gate: verify the candidate ACTUALLY has English chapters today.
    # MangaDex's availableTranslatedLanguage[] search filter uses stale metadata
    # (set when fan translations existed but later DMCA'd). Without this check,
    # we'd propose swaps that scrape 0 chapters — strictly worse than toongod.
    try:
        feed_check = await md._http.get_json(
            f"https://api.mangadex.org/manga/{cand['id']}/feed",
            params={"translatedLanguage[]": ["en"], "limit": 1},
        )
        en_chapter_count = int(feed_check.get("total", 0) or 0)
    except Exception as e:
        logger.warning("find_mangadex_match en-chapter verify failed | err=%s", e)
        en_chapter_count = 0

    if en_chapter_count == 0:
        logger.info(
            "find_mangadex_match rejected — no EN chapters | source=%s candidate=%s",
            source, cand["id"],
        )
        return None

    # Display confidence rescaled to 0-1 in the title-only fallback so the user
    # sees a comparable percentage in the dialog.
    display_confidence = score / 0.70 if not has_source_meta else score
    display_confidence = min(1.0, display_confidence)
    logger.info(
        "find_mangadex_match hit | source=%s candidate=%s raw=%.3f display=%.3f en_chapters=%d has_meta=%s",
        source, cand["id"], score, display_confidence, en_chapter_count, has_source_meta,
    )
    return MangaDexMatch(
        manga_id=cand["id"],
        mangadex_url=f"https://mangadex.org/title/{cand['id']}",
        title=cand["title"],
        confidence=round(display_confidence, 3),
        thumbnail_url=cand.get("thumbnail_url"),
        chapter_count=en_chapter_count,
        source_chapter_count=src_chapter_count,
    )
