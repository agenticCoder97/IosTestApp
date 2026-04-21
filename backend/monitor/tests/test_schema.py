"""Golden parse test — the UI contract lives or dies on this."""
import pytest
from pydantic import ValidationError

from monitor.schema import MetricsResponse

GOLDEN = {
    "schema_version": "1.0.0",
    "generated_at": "2026-04-21T14:23:05Z",
    "build": "a7f3c9d",
    "tenancy_ocid": "ocid1.tenancy.oc1..aaaaaaaa3kf7sjr2",
    "region": "us-sanjose-1",
    "instance_ocid": "ocid1.instance.oc1.us-sanjose-1.an2g6l",
    "cost": {
        "currency": "USD", "month_to_date": 0.00, "forecast": 0.00,
        "budget": 1.00, "last_alert": None,
        "always_free": {
            "a1_ocpu":       {"used": 4,   "cap": 4,   "unit": "ocpu"},
            "a1_ram_gb":     {"used": 24,  "cap": 24,  "unit": "GB"},
            "block_vol_gb":  {"used": 152, "cap": 200, "unit": "GB"},
            "egress_tb":     {"used": 0.18,"cap": 10,  "unit": "TB"},
            "object_std_gb": {"used": 3.4, "cap": 20,  "unit": "GB"},
        },
    },
    "services": [{
        "name": "postgres", "image": "postgres:16-alpine",
        "container_id": "a7c3e9f0b2d1", "status": "up", "health": "healthy",
        "uptime_s": 864312, "cpu_pct": 2.4, "mem_mb": 412, "restarts": 0,
        "extra": {"pg_connections": 6, "pg_max_connections": 100},
        "spark_cpu": [0.8, 1.2, 1.1, 2.4, 3.0, 1.5, 0.9, 1.0] * 4,
    }],
    "requests": {
        "window": "6h",
        "series_rps": [[1713614400000, 1.2]],
        "series_p95_ms": [[1713614400000, 120]],
        "status_codes": {"2xx": 18421, "3xx": 320, "4xx": 87, "5xx": 3},
        "slowest": [{"method": "GET", "path": "/c/{s}/ch",
                     "p50_ms": 38, "p95_ms": 412, "p99_ms": 980, "count": 1284}],
    },
    "arq": {
        "queue_depth": 2, "in_flight": 1, "workers": 3,
        "completed_24h": 184, "failed_24h": 2,
        "active": [{"job_id": "a71f3c9d2b4e", "fn": "scrape_chapter",
                    "source": "ao3", "target": "ao3:1/ch3",
                    "started": "2026-04-21T14:21:55Z", "elapsed_s": 73}],
        "recent_completed": [{"job_id": "b71f3c9d2b4e", "fn": "scrape_chapter",
                              "source": "ao3", "target": "ao3:1/ch1",
                              "duration_s": 42, "finished": "2026-04-21T14:20:00Z"}],
        "recent_failed": [],
    },
    "storage": {
        "postgres_bytes": 2_147_483_648, "media_bytes": 142_000_000_000,
        "block_vol": {"total_bytes": 161_061_273_600, "used_bytes": 144_000_000_000,
                      "free_bytes": 17_061_273_600, "mount": "/mnt/astral-media"},
        "object_storage": {"bucket": "astral-backups",
                           "used_bytes": 3_650_000_000, "tier": "standard"},
        "trend_7d": {"postgres": [1,2,3], "media": [1,2,3],
                     "block_free": [1,2,3], "object_used": [1,2,3]},
    },
    "backups": {
        "last_pg_dump": "2026-04-20T03:00:12Z", "last_size_bytes": 2_050_000_000,
        "status": "ok", "next_run_in_s": 45_588, "bucket": "astral-backups",
        "retention_days": 56,
        "recent_runs": [{"started": "2026-04-20T03:00:00Z", "duration_s": 42,
                         "size_bytes": 2_050_000_000, "status": "ok"}],
    },
    "cert": {
        "domain": "astral-reader.duckdns.org", "issuer": "Let's Encrypt R11",
        "not_before": "2026-03-12T10:14:03Z", "not_after": "2026-06-10T10:14:02Z",
        "days_left": 51, "last_renew": {"at": "2026-04-15T12:00:07Z", "status": "ok"},
    },
    "logs": [{"ts": "2026-04-21T14:23:00.412Z", "svc": "nginx",
              "lvl": "info", "msg": "GET /x 200"}],
}


def test_golden_parse_succeeds():
    resp = MetricsResponse.model_validate(GOLDEN)
    assert resp.schema_version == "1.0.0"
    assert resp.cost.budget == 1.00
    assert resp.cost.always_free.a1_ocpu.used == 4
    assert resp.services[0].name == "postgres"
    assert resp.arq.queue_depth == 2
    assert resp.cert.days_left == 51
    assert resp.logs[0].svc == "nginx"


def test_missing_required_key_raises():
    bad = {**GOLDEN}
    del bad["cost"]
    with pytest.raises(ValidationError):
        MetricsResponse.model_validate(bad)


def test_degraded_meta_sidecar_accepted():
    with_meta = {**GOLDEN, "cost_meta": {
        "degraded": True, "reason": "oci api timeout",
        "last_good": "2026-04-21T14:18:00Z",
    }}
    resp = MetricsResponse.model_validate(with_meta)
    assert resp.cost_meta is not None
    assert resp.cost_meta.degraded is True
