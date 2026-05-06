"""Pydantic v2 models for the /metrics response contract.

1:1 with the JSON schema comment block at the top of the handoff's
Dashboard.html. Any change here must be mirrored in the UI's render
functions — treat this as the UI contract.
"""
from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class CapUsage(BaseModel):
    used: float
    cap: float
    unit: str


class DegradedMeta(BaseModel):
    degraded: bool
    reason: str
    last_good: Optional[datetime] = None


class AlwaysFree(BaseModel):
    a1_ocpu:       CapUsage
    a1_ram_gb:     CapUsage
    block_vol_gb:  CapUsage
    egress_tb:     CapUsage
    object_std_gb: Optional[CapUsage] = None


class CostBlock(BaseModel):
    currency: str
    month_to_date: float
    forecast: float
    budget: float
    last_alert: Optional[datetime] = None
    always_free: AlwaysFree


class ServiceBlock(BaseModel):
    model_config = ConfigDict(extra="allow")

    name: str
    image: str
    container_id: str
    status: Literal["up", "restarting", "stopped", "unhealthy", "starting"]
    health: Optional[Literal["healthy", "starting", "unhealthy"]] = None
    uptime_s: int
    cpu_pct: float
    mem_mb: float
    restarts: int = 0
    extra: dict = Field(default_factory=dict)
    spark_cpu: list[float]


class SlowEndpoint(BaseModel):
    method: str
    path: str
    p50_ms: int
    p95_ms: int
    p99_ms: int
    count: int


class StatusCodes(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    two_xx:   int = Field(alias="2xx")
    three_xx: int = Field(alias="3xx")
    four_xx:  int = Field(alias="4xx")
    five_xx:  int = Field(alias="5xx")


class RequestsBlock(BaseModel):
    window: Literal["1h", "6h", "24h", "7d", "30d"]
    series_rps:    list[tuple[int, float]]
    series_p95_ms: list[tuple[int, float]]
    status_codes:  StatusCodes
    slowest:       list[SlowEndpoint]


class ArqActiveJob(BaseModel):
    job_id: str
    fn: str
    source: str
    target: str
    started: datetime
    elapsed_s: int


class ArqCompletedJob(BaseModel):
    job_id: str
    fn: str
    source: str
    target: str
    duration_s: int
    finished: datetime


class ArqFailedJob(BaseModel):
    job_id: str
    fn: str
    source: str
    target: str
    error: str = ""
    finished: datetime


class ArqBlock(BaseModel):
    queue_depth: int
    in_flight: int
    workers: int
    completed_24h: int
    failed_24h: int
    active: list[ArqActiveJob]
    recent_completed: list[ArqCompletedJob]
    recent_failed: list[ArqFailedJob]


class BlockVolStorage(BaseModel):
    total_bytes: int
    used_bytes: int
    free_bytes: int
    mount: str


class ObjectStorage(BaseModel):
    bucket: str
    used_bytes: int
    tier: str


class StorageTrend(BaseModel):
    postgres:    list[int]
    media:       list[int]
    block_free:  list[int]
    object_used: list[int]


class StorageBlock(BaseModel):
    postgres_bytes: Optional[int] = None
    media_bytes:    Optional[int] = None
    block_vol:      Optional[BlockVolStorage] = None
    object_storage: Optional[ObjectStorage] = None
    trend_7d:       StorageTrend


class BackupRun(BaseModel):
    started: datetime
    duration_s: int
    size_bytes: int
    status: str


class BackupsBlock(BaseModel):
    last_pg_dump: Optional[datetime] = None
    last_size_bytes: Optional[int] = None
    status: Literal["ok", "stale", "failed"]
    next_run_in_s: int
    bucket: str
    retention_days: int
    recent_runs: list[BackupRun]


class CertRenew(BaseModel):
    at: Optional[datetime] = None
    status: Literal["ok", "skipped", "failed"]


class CertBlock(BaseModel):
    domain: str
    issuer: Optional[str] = None
    not_before: Optional[datetime] = None
    not_after: Optional[datetime] = None
    days_left: Optional[int] = None
    last_renew: CertRenew


class LogLine(BaseModel):
    ts: datetime
    svc: str
    lvl: Literal["debug", "info", "warn", "error"]
    msg: str


class DeployEvent(BaseModel):
    ts: datetime
    images_pulled: list[str]
    healthy: bool
    duration_s: int
    commit_sha: Optional[str] = None
    actor: Optional[str] = None


class DeploysBlock(BaseModel):
    recent: list[DeployEvent]


class EndpointBucket(BaseModel):
    """Per-bucket latency for one endpoint, used by /metrics/endpoint."""
    ts_ms: int
    p50_ms: int
    p95_ms: int
    p99_ms: int
    count: int
    status_2xx: int = 0
    status_3xx: int = 0
    status_4xx: int = 0
    status_5xx: int = 0


class EndpointDetail(BaseModel):
    method: str
    path: str
    window: Literal["1h", "6h", "24h", "7d", "30d"]
    total_requests: int
    error_rate_pct: float
    peak_p99_ms: int
    buckets: list[EndpointBucket]


class RequestDebugResponse(BaseModel):
    filters: dict[str, str]
    traffic_counts: dict[str, int]
    reason_counts: dict[str, int]
    included_count: int
    excluded_count: int
    included_samples: list[dict]
    excluded_samples: list[dict]
    sampler: dict


class MetricsResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")

    schema_version: str
    generated_at:   datetime
    build:          str
    tenancy_ocid:   str
    region:         str
    instance_ocid:  str

    cost:     CostBlock
    services: list[ServiceBlock]
    requests: RequestsBlock
    arq:      ArqBlock
    storage:  StorageBlock
    backups:  BackupsBlock
    cert:     CertBlock
    logs:     list[LogLine]
    deploys:  DeploysBlock

    cost_meta:     Optional[DegradedMeta] = None
    services_meta: Optional[DegradedMeta] = None
    requests_meta: Optional[DegradedMeta] = None
    arq_meta:      Optional[DegradedMeta] = None
    storage_meta:  Optional[DegradedMeta] = None
    backups_meta:  Optional[DegradedMeta] = None
    cert_meta:     Optional[DegradedMeta] = None
    logs_meta:     Optional[DegradedMeta] = None
    deploys_meta:  Optional[DegradedMeta] = None
