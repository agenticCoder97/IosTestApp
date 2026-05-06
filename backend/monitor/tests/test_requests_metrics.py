import pytest

from monitor.requests_metrics import (
    build_request_debug,
    build_requests_block,
    records_for_window,
)
from monitor.traffic import RequestFilters

EXPECTED_MAX_DEBUG_SAMPLES = 100


def _records():
    return [
        {
            "ts_ms": 1000,
            "method": "GET",
            "path": "/api/v1/comics",
            "status": 200,
            "rt_ms": 10,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": 2000,
            "method": "POST",
            "path": "/api/v1/scrape",
            "status": 500,
            "rt_ms": 500,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": 3000,
            "method": "GET",
            "path": "/static/comics/x/001.jpg",
            "status": 200,
            "rt_ms": 4,
            "traffic_class": "static",
            "classification_reason": "static_path",
        },
        {
            "ts_ms": 4000,
            "method": "POST",
            "path": "/cgi-bin/.%2e/bin/sh",
            "status": 404,
            "rt_ms": 30,
            "traffic_class": "noise",
            "classification_reason": "cgi_traversal_probe",
        },
        {
            "ts_ms": 5000,
            "method": "GET",
            "path": "/monitor/",
            "status": 200,
            "rt_ms": 8,
            "traffic_class": "monitor",
            "classification_reason": "monitor_path",
        },
    ]


def test_default_app_filter_excludes_static_monitor_and_noise():
    block = build_requests_block(_records(), "6h", RequestFilters())
    assert block.status_codes.two_xx == 1
    assert block.status_codes.five_xx == 1
    assert block.status_codes.four_xx == 0
    assert block.slowest[0].path == "/api/v1/scrape"
    assert all("cgi-bin" not in endpoint.path for endpoint in block.slowest)


def test_noise_filter_returns_noise_only():
    block = build_requests_block(_records(), "6h", RequestFilters(traffic="noise"))
    assert block.status_codes.four_xx == 1
    assert block.slowest[0].path == "/cgi-bin/.%2e/bin/sh"


def test_status_and_method_filters_apply_to_same_record_set():
    block = build_requests_block(
        _records(), "6h", RequestFilters(method="POST", status="5xx")
    )
    assert block.status_codes.five_xx == 1
    assert block.status_codes.two_xx == 0
    assert block.slowest[0].method == "POST"
    assert block.slowest[0].path == "/api/v1/scrape"


def test_rank_count_orders_by_request_count():
    records = _records() + [
        {
            "ts_ms": 6000,
            "method": "GET",
            "path": "/api/v1/comics",
            "status": 200,
            "rt_ms": 11,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": 7000,
            "method": "GET",
            "path": "/api/v1/comics",
            "status": 200,
            "rt_ms": 12,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
    ]
    block = build_requests_block(records, "6h", RequestFilters(rank="count"))
    assert block.slowest[0].path == "/api/v1/comics"
    assert block.slowest[0].count == 3


def test_rank_error_rate_ignores_invalid_statuses():
    records = [
        {
            "ts_ms": 1000,
            "method": "GET",
            "path": "/api/invalid",
            "status": 999,
            "rt_ms": 900,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": 2000,
            "method": "GET",
            "path": "/api/real-error",
            "status": 500,
            "rt_ms": 1,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
    ]

    block = build_requests_block(records, "6h", RequestFilters(rank="error_rate"))

    assert block.slowest[0].path == "/api/real-error"


@pytest.mark.parametrize("rank", ["p95", "count", "error_rate"])
def test_rank_ties_order_by_method_and_path(rank):
    records = [
        {
            "ts_ms": 1000,
            "method": "POST",
            "path": "/api/z",
            "status": 200,
            "rt_ms": 10,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
        {
            "ts_ms": 2000,
            "method": "GET",
            "path": "/api/a",
            "status": 200,
            "rt_ms": 10,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
    ]

    block = build_requests_block(records, "6h", RequestFilters(rank=rank))

    assert [(endpoint.method, endpoint.path) for endpoint in block.slowest[:2]] == [
        ("GET", "/api/a"),
        ("POST", "/api/z"),
    ]


def test_debug_summary_counts_match_classified_records():
    debug = build_request_debug(
        _records(), RequestFilters(), limit=2, sampler_meta={"elapsed_ms": 7}
    )
    assert debug["filters"]["traffic"] == "app"
    assert debug["traffic_counts"]["app"] == 2
    assert debug["traffic_counts"]["noise"] == 1
    assert debug["reason_counts"]["cgi_traversal_probe"] == 1
    assert debug["included_count"] == 2
    assert debug["excluded_count"] == 3
    assert len(debug["included_samples"]) == 2
    assert debug["sampler"]["elapsed_ms"] == 7


def test_debug_samples_redact_paths_and_coerce_missing_values():
    records = [
        {
            "path": "/api/v1/comics?token=secret-value",
            "traffic_class": "app",
            "classification_reason": "api_path",
        }
    ]
    debug = build_request_debug(records, RequestFilters(), limit=1)
    sample = debug["included_samples"][0]

    assert "secret-value" not in sample["path"]
    assert "token=REDACTED" in sample["path"]
    assert sample["ts_ms"] == 0
    assert sample["method"] == ""
    assert sample["status"] == 0
    assert sample["rt_ms"] == 0


def test_debug_sample_limit_is_capped():
    records = [
        {
            "ts_ms": ts_ms,
            "method": "GET",
            "path": f"/api/{ts_ms}",
            "status": 200,
            "rt_ms": 1,
            "traffic_class": "app",
            "classification_reason": "api_path",
        }
        for ts_ms in range(EXPECTED_MAX_DEBUG_SAMPLES + 50)
    ]

    debug = build_request_debug(records, RequestFilters(), limit=999)

    assert len(debug["included_samples"]) == EXPECTED_MAX_DEBUG_SAMPLES


@pytest.mark.parametrize("limit", [-1, "not-a-number"])
def test_debug_sample_limit_normalizes_invalid_values(limit):
    debug = build_request_debug(_records(), RequestFilters(), limit=limit)

    assert debug["included_samples"] == []
    assert debug["excluded_samples"] == []


def test_records_for_window_applies_inclusive_cutoff():
    records = [
        {"ts_ms": 0, "path": "/api/old"},
        {"ts_ms": 3_600_000, "path": "/api/new"},
    ]
    out = records_for_window(records, "1h", now_ms=3_600_000)
    assert [r["path"] for r in out] == ["/api/old", "/api/new"]


def test_records_for_window_rejects_invalid_window():
    with pytest.raises(ValueError, match="invalid window"):
        records_for_window([], "bad-window", now_ms=0)


def test_1m_api_public_window_validates_as_1h():
    block = build_requests_block(_records(), "1m_api", RequestFilters())
    assert block.window == "1h"


def test_1xx_status_does_not_crash_or_increment_5xx():
    records = [
        {
            "ts_ms": 1000,
            "method": "GET",
            "path": "/api/switch",
            "status": 101,
            "rt_ms": 1,
            "traffic_class": "app",
            "classification_reason": "api_path",
        },
    ]
    block = build_requests_block(records, "6h", RequestFilters())
    assert block.status_codes.five_xx == 0
    assert block.slowest[0].path == "/api/switch"


def test_slowest_includes_error_rate_pct_counts_4xx_and_5xx():
    records = [
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics",
         "status": 200, "rt_ms": 10, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "GET", "path": "/api/v1/comics",
         "status": 500, "rt_ms": 20, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 3000, "method": "GET", "path": "/api/v1/comics",
         "status": 404, "rt_ms": 5, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 4000, "method": "GET", "path": "/api/v1/comics",
         "status": 200, "rt_ms": 40, "traffic_class": "app", "classification_reason": "api_path"},
    ]
    block = build_requests_block(records, "6h", RequestFilters())
    ep = block.slowest[0]
    assert ep.path == "/api/v1/comics"
    # 1 x 5xx + 1 x 4xx = 2 of 4 -> 50.0%
    assert ep.error_rate_pct == 50.0


def test_slowest_normalizes_path_before_grouping():
    records = [
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics/abc/chapters/1/pages",
         "status": 200, "rt_ms": 400, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "GET", "path": "/api/v1/comics/xyz/chapters/3/pages",
         "status": 200, "rt_ms": 420, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 3000, "method": "GET", "path": "/api/v1/comics/xyz/chapters/3/pages",
         "status": 200, "rt_ms": 380, "traffic_class": "app", "classification_reason": "api_path"},
    ]
    block = build_requests_block(records, "6h", RequestFilters())
    row = next(endpoint for endpoint in block.slowest if endpoint.path == "/api/v1/comics/{id}/chapters/{id}/pages")
    assert row.count == 3


def test_slowest_normalizes_query_strings_before_grouping():
    records = [
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics?page=1",
         "status": 200, "rt_ms": 80, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "GET", "path": "/api/v1/comics?page=2",
         "status": 200, "rt_ms": 90, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 3000, "method": "GET", "path": "/api/v1/comics",
         "status": 200, "rt_ms": 85, "traffic_class": "app", "classification_reason": "api_path"},
    ]
    block = build_requests_block(records, "6h", RequestFilters())
    row = next(endpoint for endpoint in block.slowest if endpoint.path == "/api/v1/comics")
    assert row.count == 3


def test_app_requests_include_main_endpoint_catalog_rows_with_zero_metrics():
    block = build_requests_block([], "6h", RequestFilters())
    rows = {(endpoint.method, endpoint.path): endpoint for endpoint in block.slowest}

    assert rows[("GET", "/api/v1/comics")].count == 0
    assert rows[("GET", "/api/v1/fanfic")].p95_ms == 0
    assert rows[("POST", "/api/v1/scrape/comic")].error_rate_pct == 0.0
    assert rows[("PUT", "/api/v1/progress/comic/{id}")].status_codes.two_xx == 0


def test_app_catalog_rows_merge_observed_metrics_and_status_counts():
    records = [
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics/abc",
         "status": 200, "rt_ms": 50, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "GET", "path": "/api/v1/comics/def",
         "status": 404, "rt_ms": 150, "traffic_class": "app", "classification_reason": "api_path"},
    ]

    block = build_requests_block(records, "6h", RequestFilters())
    row = next(endpoint for endpoint in block.slowest if endpoint.path == "/api/v1/comics/{id}")

    assert row.count == 2
    assert row.p50_ms == 150
    assert row.p95_ms == 150
    assert row.error_rate_pct == 50.0
    assert row.status_codes.two_xx == 1
    assert row.status_codes.four_xx == 1


def test_noise_requests_remain_observed_only_without_catalog_rows():
    block = build_requests_block(_records(), "6h", RequestFilters(traffic="noise"))

    assert [(endpoint.method, endpoint.path) for endpoint in block.slowest] == [
        ("POST", "/cgi-bin/.%2e/bin/sh")
    ]


def test_p99_rank_orders_by_p99_latency():
    records = [
        {"ts_ms": 1000, "method": "GET", "path": "/api/v1/comics",
         "status": 200, "rt_ms": 10, "traffic_class": "app", "classification_reason": "api_path"},
        {"ts_ms": 2000, "method": "GET", "path": "/api/v1/fanfic",
         "status": 200, "rt_ms": 500, "traffic_class": "app", "classification_reason": "api_path"},
    ]

    block = build_requests_block(records, "6h", RequestFilters(rank="p99"))

    assert block.slowest[0].path == "/api/v1/fanfic"
