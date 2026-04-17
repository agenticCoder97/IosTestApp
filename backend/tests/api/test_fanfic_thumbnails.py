import re
import pytest


VALID_PATH_RE = re.compile(r"fanfic-thumbnails/([1-9]|[1-4][0-9]|50)\.jpg")


@pytest.mark.asyncio
async def test_random_thumbnail_no_count_returns_single_path(client):
    """GET /fanfic-thumbnails/random with no count returns { path: ... }."""
    resp = await client.get("/fanfic-thumbnails/random")
    assert resp.status_code == 200
    data = resp.json()
    assert "path" in data
    assert "paths" not in data
    assert VALID_PATH_RE.fullmatch(data["path"]), f"Invalid path: {data['path']}"


@pytest.mark.asyncio
async def test_random_thumbnail_count_1_returns_single_path(client):
    """GET /fanfic-thumbnails/random?count=1 returns { path: ... } (not batch)."""
    resp = await client.get("/fanfic-thumbnails/random?count=1")
    assert resp.status_code == 200
    data = resp.json()
    assert "path" in data
    assert "paths" not in data
    assert VALID_PATH_RE.fullmatch(data["path"]), f"Invalid path: {data['path']}"


@pytest.mark.asyncio
async def test_random_thumbnail_batch_count_5_returns_paths_array(client):
    """GET /fanfic-thumbnails/random?count=5 returns { paths: [...] } of length 5."""
    resp = await client.get("/fanfic-thumbnails/random?count=5")
    assert resp.status_code == 200
    data = resp.json()
    assert "paths" in data
    assert "path" not in data
    assert len(data["paths"]) == 5
    for path in data["paths"]:
        assert VALID_PATH_RE.fullmatch(path), f"Invalid path in batch: {path}"


@pytest.mark.asyncio
async def test_random_thumbnail_count_above_cap_rejected(client):
    """GET /fanfic-thumbnails/random?count=60 returns 422 (server enforces le=50)."""
    resp = await client.get("/fanfic-thumbnails/random?count=60")
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_random_thumbnail_count_zero_rejected(client):
    """GET /fanfic-thumbnails/random?count=0 returns 422 (ge=1)."""
    resp = await client.get("/fanfic-thumbnails/random?count=0")
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_random_thumbnail_batch_count_50_returns_50_paths(client):
    """GET /fanfic-thumbnails/random?count=50 returns exactly 50 paths."""
    resp = await client.get("/fanfic-thumbnails/random?count=50")
    assert resp.status_code == 200
    data = resp.json()
    assert "paths" in data
    assert len(data["paths"]) == 50


@pytest.mark.asyncio
async def test_random_thumbnail_varies(client):
    """20 consecutive calls should yield at least 3 distinct paths (probabilistic)."""
    paths = set()
    for _ in range(20):
        resp = await client.get("/fanfic-thumbnails/random")
        assert resp.status_code == 200
        paths.add(resp.json()["path"])
    assert len(paths) >= 3, f"Expected >= 3 distinct paths, got {len(paths)}: {paths}"
