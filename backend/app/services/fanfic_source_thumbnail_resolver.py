import html
import io
import logging
import re
from pathlib import Path
from typing import Any

import httpx
from PIL import Image

logger = logging.getLogger(__name__)

SOURCE_THUMBNAIL_DIR = "fanfic-source-thumbnails"
WIKIPEDIA_API_URL = "https://en.wikipedia.org/w/api.php"
REQUEST_HEADERS = {
    "User-Agent": "Astral/1.0 fanfic source thumbnail resolver (https://github.com/agenticCoder97/IosTestApp)",
}

_ALIASES = {
    "harry potter - j. k. rowling": "Harry Potter",
    "harry potter": "Harry Potter",
    "naruto": "Naruto",
    "star wars - all media types": "Star Wars",
    "star wars prequel trilogy": "Star Wars",
    "star wars: the clone wars": "Star Wars",
    "star wars: the clone wars (2008)": "Star Wars",
    "star wars": "Star Wars",
    "marvel cinematic universe": "Marvel Cinematic Universe",
    "the avengers (marvel movies)": "Marvel Cinematic Universe",
    "marvel (comics)": "Marvel Comics",
    "x-men - all media types": "X-Men",
    "batman - all media types": "Batman",
    "batman": "Batman",
    "supernatural (tv 2005)": "Supernatural (American TV series)",
    "sherlock (tv)": "Sherlock (TV series)",
    "teen wolf (tv)": "Teen Wolf (2011 TV series)",
    "boku no hero academia": "My Hero Academia",
    "my hero academia": "My Hero Academia",
    "genshin impact": "Genshin Impact",
    "bungou stray dogs": "Bungo Stray Dogs",
    "bungo stray dogs": "Bungo Stray Dogs",
    "haikyuu!!": "Haikyu!!",
    "haikyu!!": "Haikyu!!",
    "highschool dxd": "High School DxD",
    "high school dxd": "High School DxD",
    "rwby": "RWBY",
}

_AMBIGUOUS_RE = re.compile(
    r"\b(?:rpf|real person fiction|original work|no fandom|multi-fandom|multifandom|crossover)\b",
    re.IGNORECASE,
)
_MEDIA_PAREN_RE = re.compile(
    r"\s*\((?:[^)]*(?:anime|manga|movie|movies|tv|television|comics?|cartoons?|"
    r"video games?|books?|novels?|web series|podcasts?)[^)]*)\)\s*$",
    re.IGNORECASE,
)
_ALL_MEDIA_SUFFIX_RE = re.compile(r"\s+-\s+all media types\s*$", re.IGNORECASE)


def ao3_source_candidates(fandom: str | None) -> list[str]:
    """Return a single high-confidence AO3 source-work candidate, or none."""
    if not fandom:
        return []

    candidates: list[str] = []
    for raw_tag in fandom.split(","):
        cleaned = _clean_ao3_fandom_tag(raw_tag)
        if cleaned and cleaned not in candidates:
            candidates.append(cleaned)

    if len(candidates) != 1:
        return []
    return candidates


def is_generic_fanfic_thumbnail(path: str | None) -> bool:
    if not path:
        return True
    return path.startswith("fanfic-covers/") or path.startswith("fanfic-thumbnails/")


async def resolve_fanfic_source_thumbnail(fanfic: Any, media_root: str | Path) -> str | None:
    resolver = SourceThumbnailResolver(media_root=media_root)
    return await resolver.resolve(
        fandom=getattr(fanfic, "fandom", None),
        source_key=_source_key_value(getattr(fanfic, "source_key", None)),
    )


class SourceThumbnailResolver:
    def __init__(
        self,
        *,
        media_root: str | Path,
        client: httpx.AsyncClient | None = None,
        timeout: float = 8.0,
    ) -> None:
        self.media_root = Path(media_root)
        self.client = client
        self.timeout = timeout

    async def resolve(self, *, fandom: str | None, source_key: str | None) -> str | None:
        if source_key != "ao3":
            return None

        for candidate in ao3_source_candidates(fandom):
            title = _alias(candidate)
            rel_path = f"{SOURCE_THUMBNAIL_DIR}/{_slugify(title)}.jpg"
            if (self.media_root / rel_path).exists():
                return rel_path

            image_url = await self._wikipedia_image_url(title)
            if not image_url:
                continue

            if await self._cache_image(image_url, rel_path):
                logger.info("fanfic source thumbnail cached | title=%s path=%s", title, rel_path)
                return rel_path

        return None

    async def _wikipedia_image_url(self, title: str) -> str | None:
        params = {
            "action": "query",
            "format": "json",
            "formatversion": "2",
            "redirects": "1",
            "prop": "pageimages",
            "piprop": "thumbnail|original",
            "pithumbsize": "800",
            "titles": title,
        }
        try:
            response = await self._get(WIKIPEDIA_API_URL, params=params)
            response.raise_for_status()
            data = response.json()
        except Exception as exc:
            logger.warning("wikipedia image lookup failed | title=%s error=%s", title, exc)
            return None

        pages = data.get("query", {}).get("pages", [])
        if isinstance(pages, dict):
            pages = pages.values()
        for page in pages:
            if page.get("missing"):
                continue
            original = page.get("original") or {}
            thumbnail = page.get("thumbnail") or {}
            image_url = thumbnail.get("source") or original.get("source")
            if image_url:
                return image_url
        return None

    async def _cache_image(self, image_url: str, rel_path: str) -> bool:
        dest = self.media_root / rel_path
        try:
            response = await self._get(image_url)
            response.raise_for_status()
            dest.parent.mkdir(parents=True, exist_ok=True)
            with Image.open(io.BytesIO(response.content)) as img:
                img.thumbnail((800, 1000), Image.LANCZOS)
                converted = _convert_to_rgb(img)
                converted.save(dest, "JPEG", quality=86, optimize=True)
            return True
        except Exception as exc:
            logger.warning("fanfic source thumbnail cache failed | url=%s path=%s error=%s", image_url, rel_path, exc)
            return False

    async def _get(self, url: str, **kwargs: Any) -> httpx.Response:
        if self.client is not None:
            return await self.client.get(url, headers=REQUEST_HEADERS, **kwargs)
        async with httpx.AsyncClient(timeout=self.timeout, headers=REQUEST_HEADERS, follow_redirects=True) as client:
            return await client.get(url, **kwargs)


def _clean_ao3_fandom_tag(raw_tag: str) -> str | None:
    tag = html.unescape(raw_tag).strip()
    if not tag or _AMBIGUOUS_RE.search(tag):
        return None

    aliased = _alias(tag)
    if aliased != tag:
        return aliased

    tag = _prefer_pipe_alias(tag)
    tag = _ALL_MEDIA_SUFFIX_RE.sub("", tag).strip()
    if " - " in tag:
        tag = tag.split(" - ", 1)[0].strip()
    tag = _MEDIA_PAREN_RE.sub("", tag).strip()
    tag = re.sub(r"\s+", " ", tag)
    return _alias(tag) if tag else None


def _alias(title: str) -> str:
    return _ALIASES.get(title.strip().lower(), title.strip())


def _prefer_pipe_alias(tag: str) -> str:
    if "|" not in tag:
        return tag
    parts = [part.strip() for part in tag.split("|") if part.strip()]
    for part in reversed(parts):
        if re.search(r"[A-Za-z]", part):
            return part
    return parts[-1] if parts else tag


def _slugify(title: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
    return slug or "source"


def _convert_to_rgb(img: Image.Image) -> Image.Image:
    if img.mode in ("RGBA", "LA") or (img.mode == "P" and "transparency" in img.info):
        canvas = Image.new("RGB", img.size, "white")
        canvas.paste(img.convert("RGBA"), mask=img.convert("RGBA").getchannel("A"))
        return canvas
    return img.convert("RGB")


def _source_key_value(source_key: Any) -> str | None:
    if source_key is None:
        return None
    return getattr(source_key, "value", source_key)
