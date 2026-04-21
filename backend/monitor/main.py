"""Astral OCI monitor — FastAPI app entrypoint."""
from __future__ import annotations

import logging
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("monitor")

_STATIC_DIR = Path(__file__).parent / "static"

app = FastAPI(title="astral-monitor", docs_url=None, redoc_url=None)
app.mount("/static", StaticFiles(directory=_STATIC_DIR), name="static")


@app.get("/healthz")
async def healthz() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/")
async def index() -> FileResponse:
    return FileResponse(_STATIC_DIR / "index.html", media_type="text/html")
