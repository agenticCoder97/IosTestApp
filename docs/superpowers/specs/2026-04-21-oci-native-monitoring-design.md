# OCI Native Monitoring — Design

**Date**: 2026-04-21
**Status**: Approved, ready for implementation plan

## Summary

Set up visibility-only monitoring for all Astral OCI resources using native OCI Console tooling. Install the OCI Management Agent on the A1 VM to unlock memory and OS-level metrics, then build one custom dashboard in the OCI Console covering compute, storage, networking, and instance health. No alerting, no third-party SaaS, $0 incremental cost.

## Goals / Non-goals

**In scope**
- OCI Management Agent installed and reporting on the A1 VM.
- One custom OCI Console dashboard with 6 sections, ~25 widgets, covering all Always Free resources.
- Runbook documenting exact console steps + SSH commands, reproducible on a fresh VM.

**Out of scope**
- OCI Alarms or Notifications (alerts are a separate concern).
- OCI Logging / log ingestion (app logs handled by docker-compose + the custom monitor dashboard).
- Terraform / IaC for the dashboard (console-only setup).
- Any paid metric namespaces or services.

## Constraints

- **$0/month** — all metric namespaces and the Management Agent are Always Free.
- **No new SaaS** — OCI Console only.
- **Visibility only** — no alerting wired to this dashboard.

---

## 1. Architecture

### Two-part setup

**Part 1 — OCI Management Agent (on A1 VM)**

The OCI Management Agent is a lightweight Java-based daemon that runs as a systemd service on the VM. It is required to surface the following metric namespaces that are otherwise unavailable:
- `oci_computeagent` — memory utilization, load average, disk bytes, process count, filesystem usage %

Without the agent, OCI Monitoring can only see CPU, network, and block volume metrics from the hypervisor. The agent install is a single `wget` + `bash` command scoped to the tenancy via a one-time install key generated in the OCI Console.

**Resource cost of agent:**
- RAM: ~100 MB idle
- CPU: <1% steady state
- Disk: ~50 MB install
- Well within the A1 24 GB / 4 OCPU Always Free envelope.

**Part 2 — OCI Console Custom Dashboard**

Created under `Observability & Management → Monitoring → Dashboards`. One dashboard named **Astral — Infrastructure**. Widgets use the OCI Console's built-in chart editor; no code required.

---

## 2. Dashboard Sections

### Section 1 — Compute (A1)

| Widget | Metric | Namespace | Stat |
|---|---|---|---|
| CPU Utilization | `CpuUtilization` | `oci_computeagent` | Max, P95 |
| Memory Utilization | `MemoryUtilization` | `oci_computeagent` | Max, P95 |
| Load Average 1m | `LoadAverage[1m]` | `oci_computeagent` | Mean |
| Load Average 5m | `LoadAverage[5m]` | `oci_computeagent` | Mean |
| Disk Read Bytes | `DiskBytesRead` | `oci_computeagent` | Sum |
| Disk Write Bytes | `DiskBytesWritten` | `oci_computeagent` | Sum |
| Network Bytes In | `NetworksBytesIn` | `oci_computeagent` | Sum |
| Network Bytes Out | `NetworksBytesOut` | `oci_computeagent` | Sum |
| Running Processes | `ProcessesCount` | `oci_computeagent` | Mean |

### Section 2 — Block Volumes

Two rows: one for the boot volume, one for the data volume (`/mnt/astral-media` block vol).

| Widget | Metric | Namespace | Stat |
|---|---|---|---|
| Read IOPS | `VolumeReadOps` | `oci_blockstore` | Sum |
| Write IOPS | `VolumeWriteOps` | `oci_blockstore` | Sum |
| Read Throughput | `VolumeReadThroughput` | `oci_blockstore` | Mean |
| Write Throughput | `VolumeWriteThroughput` | `oci_blockstore` | Mean |
| Throttled IOPS | `VolumeThrottledIOs` | `oci_blockstore` | Sum |

Filter by each volume OCID to split the two rows. Throttled IOPS > 0 means the volume is hitting Always Free limits.

### Section 3 — Object Storage (`astral-backups`)

| Widget | Metric | Namespace | Stat |
|---|---|---|---|
| Stored Bytes | `StoredBytes` | `oci_objectstorage` | Max |
| GET Requests | `GetRequests` | `oci_objectstorage` | Sum |
| PUT Requests | `PutRequests` | `oci_objectstorage` | Sum |
| Total Requests | `AllRequests` | `oci_objectstorage` | Sum |
| First Byte Latency | `FirstByteLatency` | `oci_objectstorage` | P95 |

Filter by bucket name `astral-backups` and namespace (your tenancy's object storage namespace).

### Section 4 — VCN / VNIC

| Widget | Metric | Namespace | Stat |
|---|---|---|---|
| Packets In | `VnicFromNetworkPackets` | `oci_vcn` | Sum |
| Packets Out | `VnicToNetworkPackets` | `oci_vcn` | Sum |
| Bytes In | `VnicFromNetworkBytes` | `oci_vcn` | Sum |
| Egress Bytes (cap tracker) | `VnicToNetworkBytes` | `oci_vcn` | Sum |
| Packets Dropped | `VnicFromNetworkPacketsDropped` | `oci_vcn` | Sum |

Egress Bytes tracks against the 10 TB Always Free monthly cap. Set the time range to the current month when checking.

### Section 5 — Instance Health

| Widget | Metric | Namespace | Stat |
|---|---|---|---|
| Instance Reachability | `instance_status` | `oci_compute_infrastructure_health` | Last |
| Maintenance Reboot Required | `maintenance_status` | `oci_compute_infrastructure_health` | Last |

These surface silent VM crashes and scheduled maintenance windows that would otherwise only appear in the OCI Console's events feed.

### Section 6 — OS Filesystem

| Widget | Metric | Namespace | Stat |
|---|---|---|---|
| Filesystem Usage % (`/`) | `FilesystemUtilization` | `oci_computeagent` | Max |
| Filesystem Usage % (`/mnt/astral-media`) | `FilesystemUtilization` | `oci_computeagent` | Max |
| Swap Utilization | `MemorySwapUtilization` | `oci_computeagent` | Max |

Filter each filesystem widget by the `mountPoint` dimension to separate `/` from `/mnt/astral-media`.

### Budget (link, not widget)

OCI does not expose budget spend as a Monitoring metric. Add a text widget or bookmark to:
`OCI Console → Billing & Cost Management → Budgets → Astral Budget`

---

## 3. Runbook Steps

### Part A — Install OCI Management Agent on A1

1. **Generate install key** in OCI Console:
   `Observability & Management → Management Agent → Download Management Agent Software`
   → Create Agent Install Key → name it `astral-a1` → download `oracle.mgmt_agent.rpm` or `.deb`

2. **SSH into A1:**
   ```bash
   ssh ubuntu@<a1-ip>
   ```

3. **Install the agent** (Ubuntu/Debian):
   ```bash
   sudo dpkg -i oracle.mgmt_agent.deb
   # or for Oracle Linux:
   sudo rpm -ivh oracle.mgmt_agent.rpm
   ```

4. **Configure with install key:**
   ```bash
   sudo /opt/oracle/mgmt_agent/agent_inst/bin/setup.sh
   # Paste the install key when prompted
   ```

5. **Verify agent is running:**
   ```bash
   sudo systemctl status mgmt_agent
   # Expected: active (running)
   ```

6. **Verify in OCI Console** (allow 5 minutes):
   `Observability & Management → Management Agent → Agents`
   → The A1 instance should appear with status `Active`.

7. **Verify metrics are flowing:**
   `Observability & Management → Monitoring → Metrics Explorer`
   → Namespace: `oci_computeagent` → Metric: `MemoryUtilization`
   → Should return data points within 10 minutes of agent activation.

### Part B — Create the Dashboard

1. Navigate to `Observability & Management → Monitoring → Dashboards`
2. Click **Create Dashboard** → name it `Astral — Infrastructure`
3. For each widget in sections 1–6:
   - Click **Add Widget** → **Metric Chart**
   - Set Compartment → select the root/Astral compartment
   - Set Namespace → (see table for each widget)
   - Set Metric → (see table)
   - Set Dimension filters (e.g. instance OCID, volume OCID, bucket name, mountPoint)
   - Set Statistic and interval (1m for most; 5m for filesystem/swap)
   - Set time range to **Last 24 hours** as the default
   - Save widget
4. Arrange widgets into sections using the dashboard layout editor.
5. For the Budget section: add a **Text Widget** with a direct link to the Budgets page.
6. Save dashboard.

### Verification

After completing both parts:
- Open the dashboard → all widgets should show data (not "No data available").
- Section 1 memory widget shows non-zero values → agent is working.
- Section 2 throttled IOPS shows 0 → block volume is not hitting limits (expected at idle).
- Section 3 stored bytes shows the size of existing `pg_dump` backups.
- Section 4 egress bytes over the current month is well under 10 TB.
- Section 5 instance health shows `OK`.

---

## Cost Envelope

| Component | Cost |
|---|---|
| OCI Management Agent | Free |
| Custom Dashboard | Free |
| `oci_computeagent` namespace | Free |
| `oci_blockstore` namespace | Free |
| `oci_objectstorage` namespace | Free |
| `oci_vcn` namespace | Free |
| `oci_compute_infrastructure_health` namespace | Free |

**Net OCI spend: $0/month.**

---

## Open Questions

- Exact OCID of the data block volume (needed when filtering Section 2 widgets). Retrieve via `OCI Console → Block Storage → Block Volumes` or `oci bv volume list`.
- Object Storage namespace string for the tenancy (needed for Section 3 filters). Retrieve via `oci os ns get`.
- Whether the A1 runs Oracle Linux or Ubuntu — determines `.rpm` vs `.deb` install path. Confirm via `ssh … cat /etc/os-release`.
