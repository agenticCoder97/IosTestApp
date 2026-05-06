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


_TOKEN_RE = re.compile(
    r"(?i)"
    r"(token|auth|password|secret|key|session|jwt|signature|credential|code|authorization)"
    r"=([^&\s]+)"
)
_AUTH_HEADER_RE = re.compile(r"(?i)(authorization\s*:\s*bearer\s+)([^\s&]+)")
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

    if (
        _matches_path_boundary(raw, "/metrics")
        or _matches_path_boundary(raw, "/monitor")
        or raw.startswith("/control/")
        or _matches_path_boundary(raw, "/static/controls.js")
    ):
        return TrafficClassification("monitor", "monitor_path")

    if raw.startswith("/static/"):
        return TrafficClassification("static", "static_path")

    if _CGI_TRAVERSAL_RE.search(raw) or _CGI_TRAVERSAL_RE.search(decoded_twice):
        return TrafficClassification("noise", "cgi_traversal_probe")

    if any(lowered.startswith(prefix.lower()) for prefix in _KNOWN_PROBE_PREFIXES):
        return TrafficClassification("noise", "known_probe_path")

    return TrafficClassification("unknown", "valid_unknown_path")


def status_band(status: int) -> Literal["2xx", "3xx", "4xx", "5xx"] | None:
    if 200 <= status < 300:
        return "2xx"
    if 300 <= status < 400:
        return "3xx"
    if 400 <= status < 500:
        return "4xx"
    if 500 <= status < 600:
        return "5xx"
    return None


def record_matches_filters(record: dict, filters: RequestFilters) -> bool:
    if record.get("traffic_class") != filters.traffic:
        return False
    method = filters.method.upper()
    if method != "ALL" and str(record.get("method", "")).upper() != method:
        return False
    if filters.status != "all":
        status = _parse_http_status(record.get("status"))
        if status is None or status_band(status) != filters.status:
            return False
    q = filters.q.strip().lower()
    if q and q not in str(record.get("path", "")).lower():
        return False
    return True


def redact_sample(value: str, max_len: int = 120) -> str:
    redacted = _TOKEN_RE.sub(lambda m: f"{m.group(1)}=REDACTED", value or "")
    redacted = _AUTH_HEADER_RE.sub(lambda m: f"{m.group(1)}REDACTED", redacted)
    return redacted[:max_len]


def _safe_unquote(value: str) -> str:
    try:
        return unquote(value)
    except Exception:
        return value


def _matches_path_boundary(path: str, prefix: str) -> bool:
    return path == prefix or path.startswith(f"{prefix}/") or path.startswith(f"{prefix}?")


def _parse_http_status(value: object) -> int | None:
    try:
        status = int(value)
    except (TypeError, ValueError):
        return None
    if 200 <= status <= 599:
        return status
    return None


def _looks_binary_or_malformed(value: str) -> bool:
    if _HEX_ESCAPE_RE.search(value):
        return True
    return any(ord(ch) < 32 and ch not in ("\t", "\n", "\r") for ch in value)
