"""Filtered request metric aggregation for monitor panels."""
from __future__ import annotations

from collections import Counter
from dataclasses import asdict
from datetime import UTC, datetime
from typing import Any

from monitor.schema import RequestsBlock
from monitor.traffic import (
    RequestFilters,
    normalize_path,
    record_matches_filters,
    redact_sample,
    status_band,
)

WINDOWS_S = {
    "1h": 3600,
    "6h": 21600,
    "24h": 86400,
    "7d": 604800,
    "30d": 2592000,
    "1m_api": 60,
}
MAX_DEBUG_SAMPLES = 100

_STATUS_BUCKETS = ("2xx", "3xx", "4xx", "5xx")


def records_for_window(
    records: list[dict], window: str, now_ms: int | None = None
) -> list[dict]:
    """Return records whose timestamp falls within the requested window."""
    if window not in WINDOWS_S:
        raise ValueError(f"invalid window: {window}")
    if now_ms is None:
        now_ms = int(datetime.now(UTC).timestamp() * 1000)
    cutoff_ms = now_ms - WINDOWS_S[window] * 1000
    return [
        record for record in records if _coerce_int(record.get("ts_ms")) >= cutoff_ms
    ]


def build_requests_block(
    records: list[dict], window: str, filters: RequestFilters
) -> RequestsBlock:
    """Build a request metrics block from already time-windowed records."""
    filtered = [record for record in records if record_matches_filters(record, filters)]

    status_codes = {bucket: 0 for bucket in _STATUS_BUCKETS}
    by_endpoint: dict[tuple[str, str], list[dict]] = {}
    bucket_ms = max(60_000, WINDOWS_S[window] * 1000 // 60)
    series_rps_buckets: Counter[int] = Counter()
    series_p95_buckets: dict[int, list[int]] = {}

    for record in filtered:
        status = _optional_int(record.get("status"))
        band = status_band(status) if status is not None else None
        if band is not None:
            status_codes[band] += 1

        method = _coerce_str(record.get("method"))
        path = _coerce_str(record.get("path"))
        rt_ms = _coerce_int(record.get("rt_ms"))
        ts_ms = _coerce_int(record.get("ts_ms"))

        by_endpoint.setdefault((method, normalize_path(path)), []).append(record)
        bucket = (ts_ms // bucket_ms) * bucket_ms
        series_rps_buckets[bucket] += 1
        series_p95_buckets.setdefault(bucket, []).append(rt_ms)

    series_rps = [
        (bucket, count / (bucket_ms / 1000))
        for bucket, count in sorted(series_rps_buckets.items())
    ]
    series_p95_ms = [
        (bucket, _pct(rts, 95)) for bucket, rts in sorted(series_p95_buckets.items())
    ]

    slowest = []
    for (method, path), endpoint_records in by_endpoint.items():
        rts = [_coerce_int(record.get("rt_ms")) for record in endpoint_records]
        err_rate = _error_rate(endpoint_records)
        slowest.append(
            {
                "method": method,
                "path": path,
                "p50_ms": _pct(rts, 50),
                "p95_ms": _pct(rts, 95),
                "p99_ms": _pct(rts, 99),
                "count": len(endpoint_records),
                "error_rate_pct": round(err_rate * 100, 1),
                "_error_rate": err_rate,
            }
        )

    if filters.rank == "count":
        slowest.sort(
            key=lambda item: (
                -item["count"],
                -item["p95_ms"],
                item["method"],
                item["path"],
            )
        )
    elif filters.rank == "error_rate":
        slowest.sort(
            key=lambda item: (
                -item["_error_rate"],
                -item["count"],
                -item["p95_ms"],
                item["method"],
                item["path"],
            )
        )
    else:
        slowest.sort(
            key=lambda item: (
                -item["p95_ms"],
                -item["count"],
                item["method"],
                item["path"],
            )
        )

    return RequestsBlock(
        window=_public_window(window),
        series_rps=series_rps,
        series_p95_ms=series_p95_ms,
        status_codes=status_codes,
        slowest=[
            {k: v for k, v in item.items() if not k.startswith("_")}
            for item in slowest[:10]
        ],
    )


def build_request_debug(
    records: list[dict],
    filters: RequestFilters,
    limit: int,
    sampler_meta: dict | None = None,
) -> dict:
    """Build a debug payload describing classified and filtered request records."""
    traffic_counts: Counter[str] = Counter()
    reason_counts: Counter[str] = Counter()
    included = []
    excluded = []

    for record in records:
        traffic_counts[_coerce_str(record.get("traffic_class"))] += 1
        reason_counts[_coerce_str(record.get("classification_reason"))] += 1
        if record_matches_filters(record, filters):
            included.append(record)
        else:
            excluded.append(record)

    sample_limit = min(MAX_DEBUG_SAMPLES, max(0, _coerce_int(limit)))
    return {
        "filters": asdict(filters),
        "traffic_counts": dict(traffic_counts),
        "reason_counts": dict(reason_counts),
        "included_count": len(included),
        "excluded_count": len(excluded),
        "included_samples": [_sample_record(record) for record in included[:sample_limit]],
        "excluded_samples": [_sample_record(record) for record in excluded[:sample_limit]],
        "sampler": sampler_meta or {},
    }


def _sample_record(record: dict) -> dict[str, int | str]:
    return {
        "ts_ms": _coerce_int(record.get("ts_ms")),
        "method": _coerce_str(record.get("method")),
        "path": redact_sample(_coerce_str(record.get("path"))),
        "status": _coerce_int(record.get("status")),
        "rt_ms": _coerce_int(record.get("rt_ms")),
        "traffic_class": _coerce_str(record.get("traffic_class")),
        "classification_reason": _coerce_str(record.get("classification_reason")),
    }


def _public_window(window: str) -> str:
    if window == "1m_api":
        return "1h"
    return window


def _pct(values: list[int], p: int) -> int:
    if not values:
        return 0
    xs = sorted(values)
    k = int(len(xs) * p / 100)
    return xs[min(k, len(xs) - 1)]


def _error_rate(records: list[dict]) -> float:
    """Return fraction of records with 4xx or 5xx status. Consistent with the endpoint modal."""
    if not records:
        return 0.0
    errors = 0
    for record in records:
        status = _optional_int(record.get("status"))
        if status is not None and status_band(status) in ("4xx", "5xx"):
            errors += 1
    return errors / len(records)


def _coerce_int(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _optional_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _coerce_str(value: Any) -> str:
    if value is None:
        return ""
    return str(value)
