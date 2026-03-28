import re
from bs4 import BeautifulSoup
from app.scrapers.base import BaseScraper, StoryMetadata, ChapterInfo, PageInfo
from app.core.constants import SourceKey


def _work_id(url: str) -> str:
    m = re.search(r"/works/(\d+)", url)
    if not m:
        raise ValueError(f"Cannot extract AO3 work ID from URL: {url}")
    return m.group(1)


def _adult(url: str) -> str:
    """Append view_adult=true so mature works don't show the age gate."""
    sep = "&" if "?" in url else "?"
    return f"{url}{sep}view_adult=true"


class AO3Scraper(BaseScraper):
    source_key = SourceKey.AO3
    content_type = "fanfic"
    requires_browser = False
    request_delay_seconds = 2.0  # AO3 rate-limit policy
    max_retries = 3

    async def get_story_metadata(self, url: str) -> StoryMetadata:
        work_id = _work_id(url)
        html = await self._fetch(_adult(f"https://archiveofourown.org/works/{work_id}"))
        soup = BeautifulSoup(html, "lxml")

        title_tag = soup.select_one("h2.title.heading")
        title = title_tag.get_text(strip=True) if title_tag else "Unknown Title"

        author_tags = soup.select("h3.byline.heading a[rel='author']")
        authors = [a.get_text(strip=True) for a in author_tags]

        summary_tag = soup.select_one(".summary blockquote")
        description = summary_tag.get_text(separator="\n", strip=True) if summary_tag else None

        # Rating
        rating_tag = soup.select_one("dd.rating.tags a")
        rating = rating_tag.get_text(strip=True) if rating_tag else None

        # Fandom
        fandom_tags = soup.select("dd.fandom.tags a")
        fandom = ", ".join(a.get_text(strip=True) for a in fandom_tags) or None

        # Relationships / Pairings
        rel_tags = soup.select("dd.relationship.tags a")
        pairing = ", ".join(a.get_text(strip=True) for a in rel_tags) or None

        # Characters
        char_tags = soup.select("dd.character.tags a")
        characters = ", ".join(a.get_text(strip=True) for a in char_tags) or None

        # Warnings
        warn_tags = soup.select("dd.warning.tags a")
        warnings = ", ".join(a.get_text(strip=True) for a in warn_tags) or None

        # Freeform tags
        free_tags = soup.select("dd.freeform.tags a")
        tag_list = [{"name": a.get_text(strip=True), "tag_type": "freeform"} for a in free_tags]

        # Word count
        words_dd = soup.select_one("dd.words")
        word_count = None
        if words_dd:
            try:
                word_count = int(words_dd.get_text(strip=True).replace(",", ""))
            except ValueError:
                pass

        # Dates
        pub_dd = soup.select_one("dd.published")
        published_at = pub_dd.get_text(strip=True) if pub_dd else None

        status_dd = soup.select_one("dd.status")
        updated_at_source = status_dd.get_text(strip=True) if status_dd else None

        # "3/10" or "3/?" or just "3"
        chapters_dd = soup.select_one("dd.chapters")
        total_chapters = None
        completion_status = "ongoing"
        if chapters_dd:
            parts = chapters_dd.get_text(strip=True).split("/")
            try:
                total = parts[-1]
                if total == "?":
                    total_chapters = None
                    completion_status = "ongoing"
                else:
                    total_chapters = int(total)
                    posted = int(parts[0]) if len(parts) > 1 else total_chapters
                    completion_status = "complete" if posted >= total_chapters else "ongoing"
            except ValueError:
                pass

        return StoryMetadata(
            title=title,
            source_url=url,
            source_key=self.source_key,
            source_id=work_id,
            description=description,
            authors=authors,
            tags=tag_list,
            total_chapters=total_chapters,
            fandom=fandom,
            rating=rating,
            warnings=warnings,
            characters=characters,
            pairing=pairing,
            word_count=word_count,
            completion_status=completion_status,
            published_at=published_at,
            updated_at_source=updated_at_source,
        )

    async def get_chapter_list(self, story_url: str) -> list[ChapterInfo]:
        work_id = _work_id(story_url)
        html = await self._fetch(f"https://archiveofourown.org/works/{work_id}/navigate")
        soup = BeautifulSoup(html, "lxml")

        chapters = []
        for idx, li in enumerate(soup.select("ol.chapter.index.group li"), start=1):
            a = li.select_one("a")
            if not a:
                continue
            href = a.get("href", "")
            chapter_url = f"https://archiveofourown.org{href}" if href.startswith("/") else href
            # Link text is "N. Chapter Title" — strip the leading number
            raw_title = a.get_text(strip=True)
            title = re.sub(r"^\d+\.\s*", "", raw_title)
            chapters.append(ChapterInfo(
                chapter_number=float(idx),
                source_url=chapter_url,
                title=title or f"Chapter {idx}",
            ))

        # Single-chapter works have no navigate page — fall back
        if not chapters:
            chapters.append(ChapterInfo(
                chapter_number=1.0,
                source_url=_adult(f"https://archiveofourown.org/works/{work_id}"),
                title="Chapter 1",
            ))

        return chapters

    async def get_chapter_pages(self, chapter_url: str) -> list[PageInfo]:
        raise NotImplementedError("ao3 is a fanfic source — no pages")

    async def get_chapter_text(self, chapter_url: str) -> str:
        html = await self._fetch(_adult(chapter_url))
        soup = BeautifulSoup(html, "lxml")

        content_div = soup.select_one("#chapters .userstuff") or soup.select_one(".userstuff")
        if not content_div:
            return ""

        # Remove the landmark "Chapter Text" heading AO3 injects
        for heading in content_div.select("h3.landmark"):
            heading.decompose()

        # Remove author end notes
        for notes in content_div.select(".end-notes"):
            notes.decompose()

        paragraphs = [p.get_text(separator="\n", strip=True) for p in content_div.find_all("p")]
        return "\n\n".join(p for p in paragraphs if p)
