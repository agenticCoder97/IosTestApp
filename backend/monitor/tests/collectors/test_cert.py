"""cert.collect() — parse the LE cert file."""
from pathlib import Path

import pytest

from monitor.collectors import cert as cert_mod


@pytest.mark.asyncio
async def test_collect_parses_valid_cert(monkeypatch):
    fixture = Path(__file__).parent / "_fixtures" / "fullchain.pem"
    monkeypatch.setattr(cert_mod, "CERT_PATH", fixture)
    monkeypatch.setattr(cert_mod, "LE_LOG_PATH", fixture.parent / "nonexistent.log")

    block = await cert_mod.collect()
    assert block.domain == "astral-reader.duckdns.org"
    assert block.days_left is not None and 0 < block.days_left <= 30
    assert block.not_after is not None


@pytest.mark.asyncio
async def test_collect_returns_placeholder_when_file_missing(monkeypatch, tmp_path):
    monkeypatch.setattr(cert_mod, "CERT_PATH", tmp_path / "missing.pem")
    monkeypatch.setattr(cert_mod, "LE_LOG_PATH", tmp_path / "missing.log")

    block = await cert_mod.collect()
    assert block.domain == "astral-reader.duckdns.org"
    assert block.days_left is None
    assert block.last_renew.status == "failed"
