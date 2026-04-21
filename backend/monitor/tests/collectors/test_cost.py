"""cost.collect() — OCI budget + always-free, all mocked."""
from unittest.mock import MagicMock

import pytest
from fakeredis import FakeAsyncRedis

from monitor.collectors import cost as cost_mod


@pytest.mark.asyncio
async def test_collect_assembles_from_budget_api(monkeypatch):
    fake_budget = MagicMock()
    fake_budget.data.actual_spend = 0.0
    fake_budget.data.forecasted_spend = 0.0
    fake_budget.data.amount = 1.0
    fake_budget.data.currency = "USD"

    async def _fb():
        return fake_budget

    async def _faf():
        return {
            "a1_ocpu":       {"used": 4,  "cap": 4,  "unit": "ocpu"},
            "a1_ram_gb":     {"used": 24, "cap": 24, "unit": "GB"},
            "block_vol_gb":  {"used": 152,"cap": 200,"unit": "GB"},
            "egress_tb":     {"used": 0.18,"cap": 10,"unit": "TB"},
            "object_std_gb": {"used": 3.4,"cap": 20,"unit": "GB"},
        }

    monkeypatch.setattr(cost_mod, "_fetch_budget", _fb)
    monkeypatch.setattr(cost_mod, "_fetch_always_free", _faf)
    monkeypatch.setattr(cost_mod, "get_cache_redis", lambda: FakeAsyncRedis(decode_responses=True))

    block = await cost_mod.collect()
    assert block.month_to_date == 0.0
    assert block.budget == 1.0
    assert block.always_free.a1_ocpu.used == 4


@pytest.mark.asyncio
async def test_collect_raises_on_oci_failure(monkeypatch):
    async def _raise():
        raise RuntimeError("IMDS unreachable")

    monkeypatch.setattr(cost_mod, "_fetch_budget", _raise)
    monkeypatch.setattr(cost_mod, "get_cache_redis", lambda: FakeAsyncRedis(decode_responses=True))
    with pytest.raises(RuntimeError):
        await cost_mod.collect()
