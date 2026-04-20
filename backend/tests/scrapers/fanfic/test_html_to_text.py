"""Unit tests for html_to_paragraphs — AST-41.

Pins that FFNet chapter text (EPUB XHTML from FicHub, fragment HTML from
FanFicFare) gets reduced to the same plain-text-paragraphs shape the iOS
reader expects (same format as AO3 scraper output).
"""
from app.scrapers.fanfic._html_to_text import html_to_paragraphs


def test_full_fichub_xhtml_document():
    raw = """<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en">
  <head/>
  <body><h2>Chapter One</h2><p/><div><p>First paragraph.</p><p>Second paragraph.</p></div></body>
</html>"""
    assert html_to_paragraphs(raw) == "First paragraph.\n\nSecond paragraph."


def test_fff_fragment_drops_h2():
    raw = "<h2>Chapter Title</h2><div><p>A</p><p>B</p></div>"
    assert html_to_paragraphs(raw) == "A\n\nB"


def test_self_closing_and_empty_blocks_filtered():
    raw = "<body><p/><div><p>Real content.</p></div><div> </div><div/></body>"
    assert html_to_paragraphs(raw) == "Real content."


def test_html_entities_decoded():
    raw = "<p>foo &amp; bar &#8212; baz</p>"
    assert html_to_paragraphs(raw) == "foo & bar — baz"


def test_inline_tags_stripped_to_text():
    raw = "<p><strong>bold</strong> and <em>ital</em></p>"
    assert html_to_paragraphs(raw) == "bold and ital"


def test_empty_input_returns_empty_string():
    assert html_to_paragraphs("") == ""
    assert html_to_paragraphs(None) == ""  # type: ignore[arg-type]


def test_body_without_paragraphs_falls_back():
    raw = "<body>Just a line<br/>Another line</body>"
    out = html_to_paragraphs(raw)
    # Fallback should still return the body text (non-empty).
    assert "Just a line" in out
    assert "Another line" in out


def test_scene_break_paragraph_preserved_as_text():
    raw = "<p><strong> - Keira - 15/08/1994 -</strong></p>"
    assert html_to_paragraphs(raw) == "- Keira - 15/08/1994 -"


def test_multiple_paragraphs_joined_with_double_newline():
    raw = "<body><p>One.</p><p>Two.</p><p>Three.</p></body>"
    assert html_to_paragraphs(raw) == "One.\n\nTwo.\n\nThree."
