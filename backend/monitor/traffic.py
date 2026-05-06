"""Traffic classification and filtering helpers for monitor request metrics."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Literal
from urllib.parse import unquote
import re

TrafficClass = Literal["app", "static", "monitor", "noise", "unknown"]
StatusBand = Literal["all", "2xx", "3xx", "4xx", "5xx"]
RankMode = Literal["p95", "count", "error_rate"]


@dataclass(frozen=True)
class TrafficClassification:
    traffic_class: TrafficClass
    reason: str


@dataclass(frozen=True)
class RequestFilters:
    traffic: TrafficClass = "app"
    method: str = "all"
    status: StatusBand = "all"
    q: str = ""
    rank: RankMode = "p95"


_TOKEN_RE = re.compile(r"(?i)(token|auth|password|secret|key)=([^&\s]+)")
_HEX_ESCAPE_RE = re.compile(r"\\x[0-9a-fA-F]{2}")
_CGI_TRAVERSAL_RE = re.compile(r"(?i)^/cgi-bin/.*(%2e|%%32%65|\.\.).*/bin/sh")
_KNOWN_PROBE_PREFIXES = (
    "/wp-admin",
    "/wp-login.php",
    "/phpmyadmin",
    "/.env",
    "/vendor/phpunit",
    "/boaform",
    "/HNAP1",
)


def classify_request(method: str, path: str) -> TrafficClassification:
    """Classify one nginx request path into dashboard traffic classes."""
    raw = path or ""
    decoded_once = _safe_unquote(raw)
    decoded_twice = _safe_unquote(decoded_once)
    lowered = decoded_twice.lower()

    if _looks_binary_or_malformed(raw):
        return TrafficClassification("noise", "binary_or_malformed_request")

    if raw.startswith("/api/") or raw == "/api":
        return TrafficClassification("app", "api_path")

    if raw.startswith("/static/"):
        return TrafficClassification("static", "static_path")

    if (
        raw == "/metrics"
        or raw.startswith("/metrics?")
        or raw.startswith("/monitor")
        or raw.startswith("/control/")
        or raw.startswith("/static/controls.js")
    ):
        return TrafficClassification("monitor", "monitor_path")

    if _CGI_TRAVERSAL_RE.search(raw) or _CGI_TRAVERSAL_RE.search(decoded_twice):
        return TrafficClassification("noise", "cgi_traversal_probe")

    if any(lowered.startswith(prefix.lower()) for prefix in _KNOWN_PROBE_PREFIXES):
        return TrafficClassification("noise", "known_probe_path")

    return TrafficClassification("unknown", "valid_unknown_path")


def status_band(status: int) -> Literal["2xx", "3xx", "4xx", "5xx"]:
    if 200 <= status < 300:
        return "2xx"
    if 300 <= status < 400:
        return "3xx"
    if 400 <= status < 500:
        return "4xx"
    return "5xx"


def record_matches_filters(record: dict, filters: RequestFilters) -> bool:
    if record.get("traffic_class") != filters.traffic:
        return False
    method = filters.method.upper()
    if method != "ALL" and str(record.get("method", "")).upper() != method:
        return False
    if filters.status != "all" and status_band(int(record.get("status", 0))) != filters.status:
        return False
    q = filters.q.strip().lower()
    if q and q not in str(record.get("path", "")).lower():
        return False
    return True


def redact_sample(value: str, max_len: int = 120) -> str:
    redacted = _TOKEN_RE.sub(lambda m: f"{m.group(1)}=REDACTED", value or "")
    return redacted[:max_len]


def _safe_unquote(value: str) -> str:
    try:
        return unquote(value)
    except Exception:
        return value


def _looks_binary_or_malformed(value: str) -> bool:
    if _HEX_ESCAPE_RE.search(value):
        return True
    return any(ord(ch) < 32 and ch not in ("\t", "\n", "\r") for ch in value)
