"""
Unit tests for AO3Scraper selector behavior — bulk and per-chapter.

These pin the regression in AST-20: select_one('.userstuff') used to
return the chapter SUMMARY blockquote instead of the chapter BODY div.

All HTTP is monkeypatched out — no network.
"""
import pytest
from app.scrapers.fanfic.ao3 import AO3Scraper


# Bulk-view HTML with a known bug-trigger:
# - chapter-1: only a body div (no summary) — happy path
# - chapter-2: body div PRECEDED by summary blockquote and notes blockquote
# - chapter-3: body div PRECEDED only by notes blockquote
BULK_FIXTURE = """
<html><body>
<div id="chapter-1" class="chapter">
  <div class="userstuff module" role="article">
    <h3 class="landmark">Chapter Text</h3>
    <p>BODY1_MARKER chapter one body content goes here.</p>
    <p>Second paragraph of chapter one body.</p>
  </div>
</div>
<div id="chapter-2" class="chapter">
  <div class="summary module">
    <h3 class="heading">Summary:</h3>
    <blockquote class="userstuff">
      <p>SUMMARY2_MARKER chapter two summary text only.</p>
    </blockquote>
  </div>
  <div class="notes module">
    <h3 class="heading">Notes:</h3>
    <blockquote class="userstuff">
      <p>NOTES2_MARKER author notes for chapter two.</p>
    </blockquote>
  </div>
  <div class="userstuff module" role="article">
    <h3 class="landmark">Chapter Text</h3>
    <p>BODY2_MARKER chapter two body content begins here. Many more words follow in a real chapter.</p>
    <p>Another paragraph in the body of chapter two.</p>
  </div>
</div>
<div id="chapter-3" class="chapter">
  <div class="notes module">
    <h3 class="heading">Notes:</h3>
    <blockquote class="userstuff">
      <p>NOTES3_MARKER author notes for chapter three.</p>
    </blockquote>
  </div>
  <div class="userstuff module" role="article">
    <p>BODY3_MARKER chapter three body content.</p>
  </div>
</div>
</body></html>
"""


# Single-chapter (per-chapter) view HTML — same trap, different wrapper.
PER_CHAPTER_FIXTURE = """
<html><body>
<div id="chapters">
  <div class="summary module">
    <blockquote class="userstuff">
      <p>SUMMARY_MARKER work summary.</p>
    </blockquote>
  </div>
  <div class="userstuff module" role="article">
    <h3 class="landmark">Chapter Text</h3>
    <p>BODY_MARKER per-chapter body text content.</p>
  </div>
</div>
</body></html>
"""


def _patch_fetch(monkeypatch, html: str) -> None:
    async def fake_fetch(self, url):
        return html
    monkeypatch.setattr(AO3Scraper, "_fetch", fake_fetch)


@pytest.mark.asyncio
async def test_bulk_picks_chapter_body_not_summary(monkeypatch):
    _patch_fetch(monkeypatch, BULK_FIXTURE)
    result = await AO3Scraper().get_all_chapters_bulk(
        "https://archiveofourown.org/works/12345"
    )
    # All three chapters parsed
    assert set(result.keys()) == {1.0, 2.0, 3.0}
    # Chapter 1 (no summary) — happy path
    assert "BODY1_MARKER" in result[1.0]
    # Chapter 2 — the bug case. Body must win over summary AND notes.
    assert "BODY2_MARKER" in result[2.0]
    assert "SUMMARY2_MARKER" not in result[2.0]
    assert "NOTES2_MARKER" not in result[2.0]
    # Chapter 3 — body must win over notes.
    assert "BODY3_MARKER" in result[3.0]
    assert "NOTES3_MARKER" not in result[3.0]


@pytest.mark.asyncio
async def test_get_chapter_text_picks_body_not_summary(monkeypatch):
    _patch_fetch(monkeypatch, PER_CHAPTER_FIXTURE)
    text = await AO3Scraper().get_chapter_text(
        "https://archiveofourown.org/works/12345/chapters/1"
    )
    assert "BODY_MARKER" in text
    assert "SUMMARY_MARKER" not in text


@pytest.mark.asyncio
async def test_bulk_handles_chapter_without_summary(monkeypatch):
    """Regression guard: chapter-1-only fixture should still parse."""
    minimal = """
    <html><body>
    <div id="chapter-1" class="chapter">
      <div class="userstuff module" role="article">
        <p>Just the body. Nothing else.</p>
      </div>
    </div>
    </body></html>
    """
    _patch_fetch(monkeypatch, minimal)
    result = await AO3Scraper().get_all_chapters_bulk(
        "https://archiveofourown.org/works/12345"
    )
    assert result == {1.0: "Just the body. Nothing else."}
