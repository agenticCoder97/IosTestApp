"""Chapter HTML/XHTML → plain-text-paragraph normalization.

FFNet scraping has two backends (FanFicFare primary, FicHub fallback) that
each emit a different HTML shape:

- FanFicFare: fragment like `<h2>Title</h2><div><p>...</p></div>`.
- FicHub: full XHTML document per EPUB item — XML prolog, DOCTYPE,
  namespaced `<html>` root, `<head/>`, `<body>`.

The iOS reader (FanficReaderView) only knows how to render plain text
with paragraphs separated by "\\n\\n" (same shape the AO3 scraper
already produces). This module normalizes both FFNet shapes to that
format so all fanfic sources render identically.

Inline formatting (bold, italic) is discarded — matches the AO3 scraper's
existing behaviour. Duplicate chapter-title headings (`<h1>`–`<h4>` at the
top of the body) are dropped: FicHub injects `<h2>{chapter_title}</h2>`
and FFF sometimes does the same, but the chapter title is already stored
in `fanfic_chapters.title`.
"""
from __future__ import annotations

from bs4 import BeautifulSoup


def html_to_paragraphs(raw: str) -> str:
    """Extract plain-text paragraphs from chapter HTML or XHTML.

    Returns paragraphs joined by `"\\n\\n"`, matching the AO3 scraper's
    output format. Accepts both full XHTML documents (FicHub EPUB items)
    and bare fragments (FanFicFare adapter output). Empty or falsy input
    returns `""`.
    """
    if not raw:
        return ""

    soup = BeautifulSoup(raw, "lxml")
    root = soup.body if soup.body else soup

    # Drop structural/metadata elements and duplicate chapter-title
    # headings (FicHub EPUBs inject <h2>{chapter_title}</h2>).
    for tag in root.find_all(["head", "script", "style", "h1", "h2", "h3", "h4"]):
        tag.decompose()

    paragraphs = [
        p.get_text(" ", strip=True)
        for p in root.find_all("p")
        if p.get_text(strip=True)
    ]
    if paragraphs:
        return "\n\n".join(paragraphs)

    # Rare: chapter body uses raw text + <br> with no <p> wrapping.
    # Preserve blank-line separators so the reader still gets paragraph
    # breaks where possible.
    return root.get_text("\n\n", strip=True)
