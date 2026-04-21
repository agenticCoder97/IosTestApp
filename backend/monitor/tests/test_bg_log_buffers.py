"""Regression tests for LOG_DEQUE size and _follow_one tail backfill."""
from unittest.mock import MagicMock

import pytest

from monitor import bg


def test_log_deque_maxlen_is_2000():
    """LOG_DEQUE must buffer at least 2000 lines so per-service filters in
    the UI still find non-nginx entries after nginx's per-request bursts."""
    assert bg.LOG_DEQUE.maxlen == 2000


@pytest.mark.asyncio
async def test_follow_one_requests_200_line_backfill(monkeypatch):
    """_follow_one must pass tail=200 to container.logs() so newly-attached
    followers pick up recent history on monitor restart."""
    captured = {}

    def fake_logs(**kwargs):
        captured.update(kwargs)
        return iter([])  # empty stream — loop exits on StopIteration

    container = MagicMock()
    container.logs = fake_logs

    await bg._follow_one(client=MagicMock(), container=container, svc="fastapi")

    assert captured.get("tail") == 200
    assert captured.get("stream") is True
    assert captured.get("follow") is True
    assert captured.get("timestamps") is True
