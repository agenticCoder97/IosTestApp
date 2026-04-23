"""FastAPI router wiring every /control/* endpoint.

Auth: every route checks X-Monitor-Auth against MONITOR_CONTROL_TOKEN.
Missing/mismatched → 401. Token absent from env → every mutating
request is rejected (dashboard shows an actionable error).
"""
from __future__ import annotations

import asyncio
import logging
import os
from json import dumps as _json_dump
from typing import Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Request, WebSocket
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel

from monitor.control import arq_ops, backup, docker_ops, exec as exec_mod, flags, sql_console
from monitor.control.audit import record as audit_record, tail as audit_tail

logger = logging.getLogger("monitor.control.routes")

router = APIRouter(prefix="/control", tags=["control"])


async def require_auth(
    request: Request,
    x_monitor_auth: Optional[str] = Header(default=None, alias="X-Monitor-Auth"),
) -> str:
    expected = os.getenv("MONITOR_CONTROL_TOKEN")
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="MONITOR_CONTROL_TOKEN is unset — control endpoints disabled",
        )
    if not x_monitor_auth or x_monitor_auth != expected:
        raise HTTPException(status_code=401, detail="invalid control token")
    return request.client.host if request.client else "unknown"


# ── config bootstrap ──────────────────────────────────────────────────
# Serves the control token to the browser so the dashboard can seed
# localStorage without prompting. Gated only by nginx Basic Auth on
# /monitor/ — fine for this single-user deployment since holding the
# Basic Auth password already grants full control-plane access.

@router.get("/config")
async def get_config() -> JSONResponse:
    token = os.getenv("MONITOR_CONTROL_TOKEN")
    return JSONResponse({"token": token or None})


# ── flags (AST-70) ────────────────────────────────────────────────────

class FlagPut(BaseModel):
    key: str
    value: bool


@router.get("/flags")
async def get_flags(_ip: str = Depends(require_auth)) -> JSONResponse:
    states = await flags.read_all()
    return JSONResponse({"flags": [s.__dict__ for s in states]})


@router.post("/flags")
async def put_flag(body: FlagPut, ip: str = Depends(require_auth)) -> JSONResponse:
    try:
        state = await flags.set_flag(body.key, body.value, changed_by=f"ui@{ip}")
    except ValueError as e:
        audit_record("flags.set", ok=False, detail=str(e), source_ip=ip)
        raise HTTPException(status_code=400, detail=str(e))
    audit_record("flags.set", ok=True, detail={"key": body.key, "value": body.value}, source_ip=ip)
    return JSONResponse(state.__dict__)


# ── service restart (AST-71) ──────────────────────────────────────────

@router.post("/restart/{service}")
async def restart(service: str, ip: str = Depends(require_auth)) -> JSONResponse:
    try:
        result = await docker_ops.restart_service(service)
    except ValueError as e:
        audit_record("service.restart", ok=False, detail=str(e), source_ip=ip)
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        audit_record("service.restart", ok=False, detail=f"{service}: {e}", source_ip=ip)
        raise HTTPException(status_code=500, detail=str(e))
    audit_record("service.restart", ok=True, detail=result, source_ip=ip)
    return JSONResponse(result)


# ── arq retry (AST-72) ────────────────────────────────────────────────

@router.post("/retry-job/{job_id}")
async def retry_job(job_id: str, ip: str = Depends(require_auth)) -> JSONResponse:
    try:
        result = await arq_ops.retry_failed_job(job_id)
    except LookupError as e:
        audit_record("arq.retry", ok=False, detail=str(e), source_ip=ip)
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        audit_record("arq.retry", ok=False, detail=f"{job_id}: {e}", source_ip=ip)
        raise HTTPException(status_code=500, detail=str(e))
    audit_record("arq.retry", ok=True, detail=result, source_ip=ip)
    return JSONResponse(result)


# ── backup (AST-74) ───────────────────────────────────────────────────

@router.post("/backup")
async def start_backup(ip: str = Depends(require_auth)) -> JSONResponse:
    try:
        job = await backup.start_backup()
    except RuntimeError as e:
        raise HTTPException(status_code=409, detail=str(e))
    audit_record("backup.start", ok=True, detail={"job_id": job.job_id}, source_ip=ip)
    return JSONResponse({
        "job_id": job.job_id,
        "status": job.status,
        "started": job.started_iso,
    })


@router.get("/backup/{job_id}")
async def backup_status(job_id: str, _ip: str = Depends(require_auth)) -> JSONResponse:
    job = backup.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="unknown backup job")
    return JSONResponse({
        "job_id": job.job_id,
        "status": job.status,
        "started": job.started_iso,
        "duration_s": job.duration_s,
        "size_bytes": job.size_bytes,
        "error": job.error,
    })


@router.get("/backup/download/latest")
async def backup_download_latest(_ip: str = Depends(require_auth)) -> FileResponse:
    path = backup.latest_backup_path()
    if path is None:
        raise HTTPException(status_code=404, detail="no backups available")
    return FileResponse(path, media_type="application/octet-stream", filename=path.name)


# ── SQL console (AST-75) ──────────────────────────────────────────────

class QueryBody(BaseModel):
    sql: str


@router.post("/query")
async def run_query(body: QueryBody, ip: str = Depends(require_auth)) -> JSONResponse:
    try:
        result = await asyncio.wait_for(
            sql_console.run_query(body.sql), timeout=sql_console.TIMEOUT_S + 2.0,
        )
    except sql_console.SQLValidationError as e:
        audit_record("sql.query", ok=False, detail=str(e), source_ip=ip)
        raise HTTPException(status_code=400, detail=str(e))
    except asyncio.TimeoutError:
        audit_record("sql.query", ok=False, detail="timeout", source_ip=ip)
        raise HTTPException(status_code=504, detail="query exceeded timeout")
    audit_record(
        "sql.query", ok=True,
        detail={"row_count": result["row_count"], "duration_ms": result["duration_ms"]},
        source_ip=ip,
    )
    return JSONResponse(result)


# ── exec terminal sessions (AST-92) ──────────────────────────────────

class ExecStartBody(BaseModel):
    service: str
    cols: int = 80
    rows: int = 24


@router.post("/exec/start")
async def exec_start(body: ExecStartBody, ip: str = Depends(require_auth)) -> JSONResponse:
    try:
        sess = await exec_mod.start_session(
            body.service, cols=body.cols, rows=body.rows,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except exec_mod.SessionExists as e:
        raise HTTPException(status_code=409, detail=str(e))
    except Exception as e:
        logger.exception("exec_start unexpected error for service=%s", body.service)
        raise HTTPException(status_code=500, detail=str(e))
    return JSONResponse({"session_id": sess.session_id})


# ── audit log tail (read-only, shown in UI) ───────────────────────────

@router.get("/audit")
async def audit(limit: int = 30, _ip: str = Depends(require_auth)) -> JSONResponse:
    return JSONResponse({"entries": audit_tail(limit=min(max(limit, 1), 200))})


# ── exec WebSocket (AST-92) ───────────────────────────────────────────

@router.websocket("/exec/{session_id}")
async def exec_ws(websocket: WebSocket, session_id: str) -> None:
    expected = os.getenv("MONITOR_CONTROL_TOKEN")
    offered = [p.strip() for p in
               websocket.headers.get("sec-websocket-protocol", "").split(",")
               if p.strip()]
    tok = exec_mod.token_from_subprotocols(offered)
    if not expected or tok != expected:
        await websocket.close(code=1008)
        return
    if not exec_mod.origin_allowed(websocket.headers.get("origin")):
        await websocket.close(code=1008)
        return
    sess = exec_mod._REGISTRY.get(session_id)
    if sess is None or sess._closed:
        await websocket.close(code=1008)
        return
    await websocket.accept(subprotocol="monitor-token")

    async def _recv() -> dict:
        return await websocket.receive()

    watchdog_task = asyncio.create_task(exec_mod.idle_watchdog(sess))
    stdout_task = asyncio.create_task(
        exec_mod.pump_stdout(sess, websocket.send_bytes),
    )
    stdin_task = asyncio.create_task(
        exec_mod.pump_stdin(sess, _recv, websocket.send_text),
    )
    done, pending = await asyncio.wait(
        {stdout_task, stdin_task}, return_when=asyncio.FIRST_COMPLETED,
    )
    for t in pending:
        t.cancel()
    watchdog_task.cancel()
    try:
        await watchdog_task
    except asyncio.CancelledError:
        pass
    reason = sess.reason or "exec-exited"
    try:
        await websocket.send_text(
            _json_dump({"type": "closed", "reason": reason})
        )
    except Exception:
        pass
    try:
        await websocket.close(code=1000)
    except Exception:
        pass
    if not sess._closed:
        await exec_mod.close_session(sess, reason=reason)
