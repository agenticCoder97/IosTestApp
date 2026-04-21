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
    budget = await _fetch_budget()
    af = await _fetch_always_free()

    return CostBlock(
        currency=getattr(budget.data, "currency", "USD"),
        month_to_date=float(getattr(budget.data, "actual_spend", 0.0) or 0.0),
        forecast=float(getattr(budget.data, "forecasted_spend", 0.0) or 0.0),
        budget=float(getattr(budget.data, "amount", 1.0) or 1.0),
        last_alert=None,
        always_free=AlwaysFree(
            a1_ocpu=CapUsage(**af["a1_ocpu"]),
            a1_ram_gb=CapUsage(**af["a1_ram_gb"]),
            block_vol_gb=CapUsage(**af["block_vol_gb"]),
            egress_tb=CapUsage(**af["egress_tb"]),
            object_std_gb=CapUsage(**af["object_std_gb"]) if "object_std_gb" in af else None,
        ),
    )


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


async def _fetch_always_free() -> dict:
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
            except Exception:
                pass
    except Exception:
        pass

    return {
        "a1_ocpu":       {"used": 4,  "cap": 4,  "unit": "ocpu"},
        "a1_ram_gb":     {"used": 24, "cap": 24, "unit": "GB"},
        "block_vol_gb":  {"used": used_block_gb, "cap": 200, "unit": "GB"},
        "egress_tb":     {"used": 0.18, "cap": 10, "unit": "TB"},
        "object_std_gb": {"used": used_obj_gb, "cap": 20, "unit": "GB"},
    }
