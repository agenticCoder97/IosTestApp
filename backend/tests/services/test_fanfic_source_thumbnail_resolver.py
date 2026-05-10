import io

import httpx
import pytest
from PIL import Image

from app.services.fanfic_source_thumbnail_resolver import (
    SourceThumbnailResolver,
    ao3_source_candidates,
    is_generic_fanfic_thumbnail,
)


def _image_bytes() -> bytes:
    buf = io.BytesIO()
    Image.new("RGB", (320, 480), (120, 40, 80)).save(buf, format="PNG")
    return buf.getvalue()


def test_ao3_source_candidates_clean_common_fandom_suffixes():
    candidates = ao3_source_candidates("Harry Potter - J. K. Rowling")
    assert candidates == ["Harry Potter"]


def test_ao3_source_candidates_prefer_english_pipe_aliases():
    candidates = ao3_source_candidates("原神 | Genshin Impact (Video Game)")
    assert candidates == ["Genshin Impact"]


def test_ao3_source_candidates_collapse_related_star_wars_tags():
    candidates = ao3_source_candidates(
        "Star Wars - All Media Types, Star Wars Prequel Trilogy, "
        "Star Wars: The Clone Wars (2008) - All Media Types"
    )
    assert candidates == ["Star Wars"]


def test_ao3_source_candidates_collapse_highschool_dxd_aliases():
    candidates = ao3_source_candidates(
        "Highschool DxD (Anime), ハイスクール DxD - 石踏 一榮 | High School DxD - Ishibumi Ichiei"
    )
    assert candidates == ["High School DxD"]


def test_ao3_source_candidates_skip_rpf_and_original_work():
    assert ao3_source_candidates("Football RPF") == []
    assert ao3_source_candidates("Original Work") == []


def test_ao3_source_candidates_treat_crossovers_as_ambiguous():
    candidates = ao3_source_candidates("Harry Potter - J. K. Rowling, Naruto")
    assert candidates == []


def test_is_generic_fanfic_thumbnail_identifies_old_random_pools():
    assert is_generic_fanfic_thumbnail(None)
    assert is_generic_fanfic_thumbnail("fanfic-covers/cover_1.jpg")
    assert is_generic_fanfic_thumbnail("fanfic-thumbnails/12.jpg")
    assert not is_generic_fanfic_thumbnail("fanfic-source-thumbnails/harry-potter.jpg")


@pytest.mark.asyncio
async def test_resolver_uses_wikipedia_alias_and_caches_local_jpeg(tmp_path):
    async def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "en.wikipedia.org":
            assert request.url.params["titles"] == "Harry Potter"
            return httpx.Response(
                200,
                json={
                    "query": {
                        "pages": {
                            "123": {
                                "title": "Harry Potter",
                                "thumbnail": {
                                    "source": "https://upload.wikimedia.org/hp-thumb.png"
                                },
                                "original": {
                                    "source": "https://upload.wikimedia.org/hp.png"
                                },
                            }
                        }
                    }
                },
            )
        if request.url.host == "upload.wikimedia.org":
            assert request.url.path == "/hp-thumb.png"
            return httpx.Response(200, content=_image_bytes())
        return httpx.Response(404)

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        resolver = SourceThumbnailResolver(client=client, media_root=tmp_path)
        path = await resolver.resolve(fandom="Harry Potter - J. K. Rowling", source_key="ao3")

    assert path == "fanfic-source-thumbnails/harry-potter.jpg"
    cached = tmp_path / path
    assert cached.exists()
    with Image.open(cached) as img:
        assert img.format == "JPEG"


@pytest.mark.asyncio
async def test_resolver_returns_none_when_no_confident_ao3_source(tmp_path):
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda _: httpx.Response(500))) as client:
        resolver = SourceThumbnailResolver(client=client, media_root=tmp_path)
        path = await resolver.resolve(fandom="Harry Potter - J. K. Rowling, Naruto", source_key="ao3")

    assert path is None
