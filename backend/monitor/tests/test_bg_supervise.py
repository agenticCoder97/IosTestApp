"""supervise() — catches exceptions, backs off, relaunches."""
import asyncio

import pytest

from monitor.bg import supervise


@pytest.mark.asyncio
async def test_supervise_restarts_after_exception(monkeypatch):
    call_count = {"n": 0}

    async def flaky():
        call_count["n"] += 1
        if call_count["n"] < 3:
            raise RuntimeError("boom")

    monkeypatch.setattr("monitor.bg._BACKOFF_INITIAL_S", 0.01)
    monkeypatch.setattr("monitor.bg._BACKOFF_MAX_S", 0.02)

    await supervise(flaky, "flaky")
    assert call_count["n"] == 3


@pytest.mark.asyncio
async def test_supervise_propagates_cancelled_error():
    async def hangs():
        await asyncio.Event().wait()

    task = asyncio.create_task(supervise(hangs, "hangs"))
    await asyncio.sleep(0.01)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task


@pytest.mark.asyncio
async def test_supervise_returns_on_clean_exit(monkeypatch):
    async def clean():
        return

    monkeypatch.setattr("monitor.bg._BACKOFF_INITIAL_S", 0.01)
    await supervise(clean, "clean")
