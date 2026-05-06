from monitor.traffic import (
    RequestFilters,
    classify_request,
    normalize_path,
    record_matches_filters,
    redact_sample,
    status_band,
)


def test_classifies_astral_api_as_app():
    c = classify_request("GET", "/api/v1/comics")
    assert c.traffic_class == "app"
    assert c.reason == "api_path"


def test_classifies_static_as_static():
    c = classify_request("GET", "/static/comics/x/001.jpg")
    assert c.traffic_class == "static"
    assert c.reason == "static_path"


def test_classifies_monitor_owned_static_as_monitor():
    c = classify_request("GET", "/static/controls.js")
    assert c.traffic_class == "monitor"
    assert c.reason == "monitor_path"


def test_classifies_monitor_control_as_monitor():
    c = classify_request("POST", "/monitor/control/exec/start")
    assert c.traffic_class == "monitor"
    assert c.reason == "monitor_path"


def test_classifies_metrics_descendants_as_monitor():
    for path in (
        "/metrics/service/fastapi",
        "/metrics/logs/stream",
        "/metrics/endpoint",
    ):
        c = classify_request("GET", path)
        assert c.traffic_class == "monitor"
        assert c.reason == "monitor_path"


def test_classifies_metrics_prefix_without_boundary_as_unknown():
    c = classify_request("GET", "/metricsfoo")
    assert c.traffic_class == "unknown"
    assert c.reason == "valid_unknown_path"


def test_classifies_monitoring_as_unknown():
    c = classify_request("GET", "/monitoring")
    assert c.traffic_class == "unknown"
    assert c.reason == "valid_unknown_path"


def test_classifies_cgi_traversal_probe_as_noise():
    c = classify_request("POST", "/cgi-bin/.%2e/.%2e/.%2e/.%2e/bin/sh")
    assert c.traffic_class == "noise"
    assert c.reason == "cgi_traversal_probe"


def test_classifies_double_encoded_traversal_probe_as_noise():
    c = classify_request("POST", "/cgi-bin/%%32%65%%32%65/%%32%65%%32%65/bin/sh")
    assert c.traffic_class == "noise"
    assert c.reason == "cgi_traversal_probe"


def test_classifies_smb_bytes_as_noise():
    c = classify_request("GET", "\\x00\\x00\\x001\\xFFSMBr\\x00\\x00NT LM")
    assert c.traffic_class == "noise"
    assert c.reason == "binary_or_malformed_request"


def test_classifies_tls_bytes_as_noise():
    c = classify_request("GET", "\\x16\\x03\\x03\\x01\\xA5\\x01\\x00")
    assert c.traffic_class == "noise"
    assert c.reason == "binary_or_malformed_request"


def test_classifies_wordpress_probe_as_noise():
    c = classify_request("GET", "/wp-admin/setup-config.php")
    assert c.traffic_class == "noise"
    assert c.reason == "known_probe_path"


def test_classifies_valid_unknown_path_as_unknown():
    c = classify_request("GET", "/robots.txt")
    assert c.traffic_class == "unknown"
    assert c.reason == "valid_unknown_path"


def test_redact_sample_caps_and_removes_query_values():
    sample = redact_sample('/api/v1/comics?token=secret-value&name=abc', max_len=36)
    assert "secret-value" not in sample
    assert "token=REDACTED" in sample
    assert len(sample) <= 36


def test_record_filter_does_not_match_invalid_status_for_concrete_filter():
    record = {
        "traffic_class": "app",
        "method": "GET",
        "path": "/api/v1/comics",
        "status": "-",
    }
    filters = RequestFilters(status="5xx")

    assert record_matches_filters(record, filters) is False


def test_record_filter_does_not_treat_missing_status_as_5xx():
    record = {"traffic_class": "app", "method": "GET", "path": "/api/v1/comics"}
    filters = RequestFilters(status="5xx")

    assert record_matches_filters(record, filters) is False


def test_record_filter_all_status_allows_missing_or_invalid_status():
    filters = RequestFilters(status="all")
    missing = {"traffic_class": "app", "method": "GET", "path": "/api/v1/comics"}
    invalid = {
        "traffic_class": "app",
        "method": "GET",
        "path": "/api/v1/comics",
        "status": "-",
    }

    assert record_matches_filters(missing, filters) is True
    assert record_matches_filters(invalid, filters) is True


def test_status_band_returns_none_for_1xx_status():
    assert status_band(101) is None


def test_record_filter_does_not_match_1xx_status_as_5xx():
    record = {
        "traffic_class": "app",
        "method": "GET",
        "path": "/api/v1/comics",
        "status": 101,
    }
    filters = RequestFilters(status="5xx")

    assert record_matches_filters(record, filters) is False


def test_redact_sample_removes_extended_sensitive_query_values():
    sample = redact_sample(
        "/api/v1/comics?"
        "session=alpha1&jwt=beta2&signature=gamma3&credential=delta4&code=epsilon5&"
        "authorization=zeta6"
    )

    for secret in ("alpha1", "beta2", "gamma3", "delta4", "epsilon5", "zeta6"):
        assert secret not in sample
    for key in ("session", "jwt", "signature", "credential", "code", "authorization"):
        assert f"{key}=REDACTED" in sample


def test_redact_sample_removes_authorization_bearer_header_value():
    sample = redact_sample("Authorization: Bearer header-secret")

    assert "header-secret" not in sample
    assert sample == "Authorization: Bearer REDACTED"


# ── normalize_path ──────────────────────────────────────────────────────────

def test_normalize_comics_pages_collapses_ids():
    assert normalize_path("/api/v1/comics/abc123/chapters/7/pages") == "/api/v1/comics/{id}/chapters/{id}/pages"

def test_normalize_comics_detail_collapses_id():
    assert normalize_path("/api/v1/comics/abc123") == "/api/v1/comics/{id}"

def test_normalize_comics_patch_collapses_id():
    assert normalize_path("/api/v1/comics/abc123") == "/api/v1/comics/{id}"

def test_normalize_comics_archive_collapses_id():
    assert normalize_path("/api/v1/comics/abc123/archive") == "/api/v1/comics/{id}/archive"

def test_normalize_comics_unarchive_collapses_id():
    assert normalize_path("/api/v1/comics/abc123/unarchive") == "/api/v1/comics/{id}/unarchive"

def test_normalize_comics_delete_permanent_collapses_id():
    assert normalize_path("/api/v1/comics/abc123/permanent") == "/api/v1/comics/{id}/permanent"

def test_normalize_comics_list_is_unchanged():
    assert normalize_path("/api/v1/comics") == "/api/v1/comics"

def test_normalize_fanfic_chapter_collapses_ids():
    assert normalize_path("/api/v1/fanfic/xyz789/chapters/3") == "/api/v1/fanfic/{id}/chapters/{id}"

def test_normalize_fanfic_random_is_unchanged():
    assert normalize_path("/api/v1/fanfic/random") == "/api/v1/fanfic/random"

def test_normalize_fanfic_detail_collapses_id():
    assert normalize_path("/api/v1/fanfic/xyz789") == "/api/v1/fanfic/{id}"

def test_normalize_fanfic_permanent_collapses_id():
    assert normalize_path("/api/v1/fanfic/xyz789/permanent") == "/api/v1/fanfic/{id}/permanent"

def test_normalize_fanfic_list_is_unchanged():
    assert normalize_path("/api/v1/fanfic") == "/api/v1/fanfic"

def test_normalize_fanfic_thumbnails_random_unchanged():
    assert normalize_path("/api/v1/fanfic-thumbnails/random") == "/api/v1/fanfic-thumbnails/random"

def test_normalize_scrape_retry_collapses_id():
    assert normalize_path("/api/v1/scrape/job99/retry") == "/api/v1/scrape/{id}/retry"

def test_normalize_scrape_update_collapses_id():
    assert normalize_path("/api/v1/scrape/story42/update") == "/api/v1/scrape/{id}/update"

def test_normalize_scrape_logs_collapses_id():
    assert normalize_path("/api/v1/scrape/job99/logs") == "/api/v1/scrape/{id}/logs"

def test_normalize_scrape_comic_literal_unchanged():
    assert normalize_path("/api/v1/scrape/comic") == "/api/v1/scrape/comic"

def test_normalize_scrape_fanfic_literal_unchanged():
    assert normalize_path("/api/v1/scrape/fanfic") == "/api/v1/scrape/fanfic"

def test_normalize_scrape_id_collapses():
    assert normalize_path("/api/v1/scrape/job99") == "/api/v1/scrape/{id}"

def test_normalize_scrape_list_unchanged():
    assert normalize_path("/api/v1/scrape") == "/api/v1/scrape"

def test_normalize_progress_comic_collapses_id():
    assert normalize_path("/api/v1/progress/comic/story123") == "/api/v1/progress/comic/{id}"

def test_normalize_progress_fanfic_collapses_id():
    assert normalize_path("/api/v1/progress/fanfic/story456") == "/api/v1/progress/fanfic/{id}"

def test_normalize_progress_generic_type_id_collapses():
    assert normalize_path("/api/v1/progress/comic/story123") == "/api/v1/progress/comic/{id}"
    assert normalize_path("/api/v1/progress/fanfic/story456") == "/api/v1/progress/fanfic/{id}"

def test_normalize_authors_detail_collapses_id():
    assert normalize_path("/api/v1/authors/author99") == "/api/v1/authors/{id}"

def test_normalize_authors_list_unchanged():
    assert normalize_path("/api/v1/authors") == "/api/v1/authors"

def test_normalize_health_unchanged():
    assert normalize_path("/api/v1/health") == "/api/v1/health"

def test_normalize_stats_unchanged():
    assert normalize_path("/api/v1/stats") == "/api/v1/stats"

def test_normalize_unknown_path_passthrough():
    assert normalize_path("/some/random/path") == "/some/random/path"

def test_normalize_strips_query_string_before_matching():
    assert normalize_path("/api/v1/comics?page=2") == "/api/v1/comics"
    assert normalize_path("/api/v1/comics/abc123?include=chapters") == "/api/v1/comics/{id}"
    assert normalize_path("/api/v1/fanfic?q=naruto&page=3") == "/api/v1/fanfic"

def test_normalize_unknown_path_strips_query_string():
    assert normalize_path("/some/path?foo=bar") == "/some/path"
