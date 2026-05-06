from monitor.traffic import classify_request, redact_sample


def test_classifies_astral_api_as_app():
    c = classify_request("GET", "/api/v1/comics")
    assert c.traffic_class == "app"
    assert c.reason == "api_path"


def test_classifies_static_as_static():
    c = classify_request("GET", "/static/comics/x/001.jpg")
    assert c.traffic_class == "static"
    assert c.reason == "static_path"


def test_classifies_monitor_control_as_monitor():
    c = classify_request("POST", "/monitor/control/exec/start")
    assert c.traffic_class == "monitor"
    assert c.reason == "monitor_path"


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
