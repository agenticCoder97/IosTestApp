"""cost collector — OCI Budget API + Always-Free usage inference."""
from __future__ import annotations

import asyncio
import json
import logging
import os
from typing import Optional

from monitor.cache import get_cache_redis
from monitor.schema import AlwaysFree, CapUsage, CostBlock

logger = logging.getLogger("monitor.cost")

_BUDGET_OCID = os.getenv("OCI_BUDGET_OCID")


async def collect() -> CostBlock:
    # Budget + egress API calls run concurrently so cost collector
    # wall-time is max(budget, egress) rather than budget + egress.
    # return_exceptions=True so a partial failure (budget succeeds + egress
    # fails, or vice versa) still returns the real data we did get, rather
    # than raising into safe() and losing the other half to fallback.
    budget_res, egress_res = await asyncio.gather(
        _fetch_budget(),
        _fetch_egress(),
        return_exceptions=True,
    )
    if isinstance(budget_res, BaseException):
        logger.warning("cost._fetch_budget failed: %s", budget_res)
        budget_res = None
    egress_tb_used = None if isinstance(egress_res, BaseException) else egress_res

    af = await _fetch_always_free(egress_tb_used=egress_tb_used)

    # Budget block defaults when the API call failed; currency/mtd/forecast
    # fall back to zeros so the CostBlock remains renderable.
    budget_data = getattr(budget_res, "data", None)
    return CostBlock(
        currency=getattr(budget_data, "currency", "USD") if budget_data else "USD",
        month_to_date=float(getattr(budget_data, "actual_spend", 0.0) or 0.0) if budget_data else 0.0,
        forecast=float(getattr(budget_data, "forecasted_spend", 0.0) or 0.0) if budget_data else 0.0,
        budget=float(getattr(budget_data, "amount", 1.0) or 1.0) if budget_data else 1.0,
        last_alert=None,
        always_free=AlwaysFree(
            a1_ocpu=CapUsage(**af["a1_ocpu"]),
            a1_ram_gb=CapUsage(**af["a1_ram_gb"]),
            block_vol_gb=CapUsage(**af["block_vol_gb"]),
            egress_tb=CapUsage(**af["egress_tb"]),
            object_std_gb=CapUsage(**af["object_std_gb"]) if "object_std_gb" in af else None,
        ),
    )


async def _call_usage_api():
    """OCI Usage API round-trip via instance-principal signer. Sync call
    wrapped in to_thread because the SDK is blocking."""
    def _sync():
        import oci
        from datetime import datetime, timezone

        tenancy = os.getenv("OCI_TENANCY_OCID")
        if not tenancy:
            raise RuntimeError("OCI_TENANCY_OCID env var not set")

        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        client = oci.usage_api.UsageapiClient(config={}, signer=signer)

        now = datetime.now(timezone.utc)
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        details = oci.usage_api.models.RequestSummarizedUsagesDetails(
            tenant_id=tenancy,
            time_usage_started=month_start,
            time_usage_ended=now,
            granularity="MONTHLY",
            query_type="USAGE",
            group_by=["service"],
        )
        return client.request_summarized_usages(details)

    return await asyncio.to_thread(_sync)


async def _fetch_egress() -> Optional[float]:
    """TB used on outbound networking this calendar month. None on failure."""
    if not os.getenv("OCI_TENANCY_OCID"):
        return None
    try:
        resp = await _call_usage_api()
        gb_total = 0.0
        for item in getattr(resp.data, "items", []) or []:
            svc = (getattr(item, "service", "") or "").lower()
            # All OCI outbound-transfer line items live under the "Networking"
            # service family. Simpler + more robust than whitelisting SKUs.
            if "networking" in svc:
                qty = float(getattr(item, "computed_quantity", 0.0) or 0.0)
                gb_total += qty
        return gb_total / 1024.0  # GB → TB
    except Exception as e:
        logger.debug("_fetch_egress failed: %s", e)
        return None


async def _fetch_budget():
    """OCI Budget API via instance-principal signer."""
    if not _BUDGET_OCID:
        raise RuntimeError("OCI_BUDGET_OCID env var not set")

    def _sync():
        import oci
        signer = oci.auth.signers.InstancePrincipalsSecurityTokenSigner()
        client = oci.budget.BudgetClient(config={}, signer=signer)
        return client.get_budget(_BUDGET_OCID)

    return await asyncio.to_thread(_sync)


async def _fetch_always_free(egress_tb_used: Optional[float] = None) -> dict:
    """Assemble 5-dimension usage-vs-cap snapshot.

    block_vol_gb + object_std_gb read from storage last-good; others are
    static-config for the Always Free envelope.
    """
    r = get_cache_redis()
    used_block_gb = 150
    used_obj_gb = 0
    try:
        last = await r.get("mon:last_good:storage")
        if last:
            try:
                sd = json.loads(last)
                if sd.get("block_vol"):
                    used_block_gb = int(sd["block_vol"]["used_bytes"] / 1024**3)
                if sd.get("object_storage"):
                    used_obj_gb = round(sd["object_storage"]["used_bytes"] / 1024**3, 1)
            except Exception as e:
                logger.debug("mon:last_good:storage JSON parse failed, using defaults: %s", e)
    except Exception as e:
        logger.debug("mon:last_good:storage Redis GET failed, using defaults: %s", e)

    egress = round(egress_tb_used, 3) if egress_tb_used is not None else 0.0
    return {
        "a1_ocpu":       {"used": 4,  "cap": 4,  "unit": "ocpu"},
        "a1_ram_gb":     {"used": 24, "cap": 24, "unit": "GB"},
        "block_vol_gb":  {"used": used_block_gb, "cap": 200, "unit": "GB"},
        "egress_tb":     {"used": egress, "cap": 10, "unit": "TB"},
        "object_std_gb": {"used": used_obj_gb, "cap": 20, "unit": "GB"},
    }
