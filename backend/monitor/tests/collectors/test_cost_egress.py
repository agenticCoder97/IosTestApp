"""cost._fetch_egress: OCI Usage API mocked, returns TB used this month."""
from datetime import datetime, timezone
from unittest.mock import MagicMock

import pytest

from monitor.collectors import cost as cost_mod


@pytest.mark.asyncio
async def test_fetch_egress_sums_networking_items(monkeypatch):
    def _item(service, gb):
        i = MagicMock()
        i.service = service
        i.computed_quantity = gb
        i.sku_part_number = ""
        return i

    fake_resp = MagicMock()
    fake_resp.data.items = [
        _item("Networking",    1500.0),
        _item("Compute",       9000.0),
        _item("Networking",    250.0),
        _item("Object Storage", 50.0),
    ]

    async def _mock_call():
        return fake_resp

    monkeypatch.setattr(cost_mod, "_call_usage_api", _mock_call)
    monkeypatch.setenv("OCI_TENANCY_OCID", "ocid1.tenancy.oc1..fake")

    tb = await cost_mod._fetch_egress()
    assert tb == pytest.approx((1500 + 250) / 1024, rel=1e-3)  # ~1.709 TB


@pytest.mark.asyncio
async def test_fetch_egress_returns_none_on_error(monkeypatch):
    async def _boom():
        raise RuntimeError("IMDS unreachable")
    monkeypatch.setattr(cost_mod, "_call_usage_api", _boom)
    monkeypatch.setenv("OCI_TENANCY_OCID", "ocid1.tenancy.oc1..fake")

    tb = await cost_mod._fetch_egress()
    assert tb is None


@pytest.mark.asyncio
async def test_fetch_egress_no_tenancy_env(monkeypatch):
    monkeypatch.delenv("OCI_TENANCY_OCID", raising=False)
    tb = await cost_mod._fetch_egress()
    assert tb is None
