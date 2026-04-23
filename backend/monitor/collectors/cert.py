"""cert collector — parse /etc/letsencrypt/.../fullchain.pem."""
from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path

from cryptography import x509
from cryptography.x509.oid import NameOID

from monitor.schema import CertBlock, CertRenew

logger = logging.getLogger("monitor.cert")

CERT_PATH = Path("/etc/letsencrypt/live/astral-reader.duckdns.org/fullchain.pem")
LE_LOG_PATH = Path("/etc/letsencrypt/logs/letsencrypt.log")


async def collect() -> CertBlock:
    if not CERT_PATH.exists():
        return _placeholder("cert file missing")

    try:
        pem = CERT_PATH.read_bytes()
        cert = x509.load_pem_x509_certificate(pem)
    except Exception as e:
        logger.warning("cert parse failed: %s", e)
        return _placeholder(f"parse error: {e}")

    not_before = cert.not_valid_before_utc
    not_after = cert.not_valid_after_utc
    days_left = max(0, int((not_after - datetime.now(timezone.utc)).total_seconds() / 86400))

    issuer_cn = next(
        (a.value for a in cert.issuer if a.oid == NameOID.COMMON_NAME),
        "unknown issuer",
    )
    subject_cn = next(
        (a.value for a in cert.subject if a.oid == NameOID.COMMON_NAME),
        "astral-reader.duckdns.org",
    )

    last_renew_at, last_renew_status = _read_last_renew()

    return CertBlock(
        domain=subject_cn,
        issuer=issuer_cn,
        not_before=not_before,
        not_after=not_after,
        days_left=days_left,
        last_renew=CertRenew(at=last_renew_at, status=last_renew_status),
    )


def _placeholder(reason: str) -> CertBlock:
    logger.info("cert placeholder: %s", reason)
    return CertBlock(
        domain="astral-reader.duckdns.org",
        issuer=None,
        not_before=None, not_after=None, days_left=None,
        last_renew=CertRenew(at=None, status="failed"),
    )


def _read_last_renew() -> tuple[datetime | None, str]:
    try:
        stat = CERT_PATH.stat()
        at = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)
    except Exception:
        return None, "failed"

    status = "ok"
    if LE_LOG_PATH.exists():
        try:
            tail = LE_LOG_PATH.read_text(errors="replace").splitlines()[-200:]
            if any("failed" in line.lower() for line in tail):
                status = "failed"
            elif any("skipped" in line.lower() for line in tail):
                status = "skipped"
        except Exception as e:
            logger.debug("letsencrypt.log read failed, reporting renewal status=ok: %s", e)
    return at, status
