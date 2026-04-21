# OCI Native Monitoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install the OCI Management Agent on the A1 VM and build the Astral — Infrastructure dashboard in the OCI Console with 6 sections and ~25 widgets covering compute, block volumes, object storage, VCN, instance health, and OS filesystem.

**Architecture:** Management Agent runs as a systemd service on the A1, unlocking memory/OS metrics in the `oci_computeagent` namespace. One custom OCI Console dashboard pins widgets across all Always Free metric namespaces. No code changes to the Astral backend.

**Tech Stack:** OCI Management Agent, OCI Monitoring (Console dashboard), SSH

---

## Task 1: Confirm A1 OS and gather OCIDs

**Status: COMPLETE — all OCIDs resolved via OCI CLI.**

| Variable | Value |
|---|---|
| `A1_INSTANCE_OCID` | `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq` |
| `BOOT_VOL_OCID` | `ocid1.bootvolume.oc1.us-sanjose-1.abzwuljrj7brujoejpqkggvnaj462mlz7abziyx5dt25uitwxddcmwxlapya` |
| `DATA_VOL_OCID` | `ocid1.volume.oc1.us-sanjose-1.abzwuljrkyzyl6lpwnpofra4srw7a5774twnbgdotsznxxzfrryceb7qqo2q` |
| `VNIC_OCID` | `ocid1.vnic.oc1.us-sanjose-1.abzwuljrfhdghxmtaqrns6ucqydprsacft7nuykxryhbw2vrv4vsempyck3q` |
| `OS_NAMESPACE` | `axfta6t5vu1x` |
| Region | `us-sanjose-1` |
| Availability Domain | `dgpj:US-SANJOSE-1-AD-1` |
| Bucket | `astral-backups` ✓ confirmed |

- [x] **Step 1–5: All OCIDs gathered via OCI CLI** — no console lookup needed.

- [ ] **Step 6: Confirm A1 OS (needed for agent install package format)**

```bash
ssh ubuntu@<a1-ip> "cat /etc/os-release | grep -E '^(NAME|VERSION)'"
```

Expected (Ubuntu): use `.deb` in Task 2. If Oracle Linux: use `.rpm`.

---

## Task 2: Install OCI Management Agent on A1

**Files:**
- Create: `backend/scripts/install-mgmt-agent.sh` (reproducible install script, committed to repo)

- [ ] **Step 1: Generate agent install key in OCI Console**

Navigate to: `Observability & Management → Management Agent → Download Management Agent Software`
→ Click **Create Agent Install Key**
→ Name: `astral-a1`
→ Leave defaults (unlimited installs, no expiry)
→ Click **Create**
→ Copy the install key string. Save as `MGMT_AGENT_KEY=<value>`

- [ ] **Step 2: Download agent software**

On the same page, download the appropriate package:
- Ubuntu/Debian: `oracle.mgmt_agent.deb`
- Oracle Linux / RHEL: `oracle.mgmt_agent.rpm`

SCP it to the A1:
```bash
scp oracle.mgmt_agent.deb ubuntu@<a1-ip>:~/
```

- [ ] **Step 3: Write install script to repo**

Create `backend/scripts/install-mgmt-agent.sh`:

```bash
#!/usr/bin/env bash
# Installs the OCI Management Agent on an Ubuntu/Debian A1 instance.
# Run as root or with sudo. Requires oracle.mgmt_agent.deb in the same directory.
# Usage: sudo bash install-mgmt-agent.sh <INSTALL_KEY>
set -euo pipefail

INSTALL_KEY="${1:?Usage: $0 <install_key>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Installing OCI Management Agent..."
dpkg -i "${SCRIPT_DIR}/oracle.mgmt_agent.deb"

echo "==> Configuring with install key..."
/opt/oracle/mgmt_agent/agent_inst/bin/setup.sh <<< "${INSTALL_KEY}"

echo "==> Enabling and starting mgmt_agent service..."
systemctl enable mgmt_agent
systemctl start mgmt_agent

echo "==> Status:"
systemctl status mgmt_agent --no-pager
echo ""
echo "Done. Allow 5–10 minutes for the agent to appear in OCI Console under:"
echo "  Observability & Management → Management Agent → Agents"
```

- [ ] **Step 4: Run the install script on the A1**

```bash
scp backend/scripts/install-mgmt-agent.sh ubuntu@<a1-ip>:~/
ssh ubuntu@<a1-ip> "sudo bash ~/install-mgmt-agent.sh '<MGMT_AGENT_KEY>'"
```

Expected final lines:
```
Active: active (running) since ...
Done. Allow 5–10 minutes for the agent to appear in OCI Console...
```

- [ ] **Step 5: Verify agent appears in OCI Console**

Navigate to: `Observability & Management → Management Agent → Agents`
Wait up to 10 minutes. The A1 instance should appear with status **Active**.

- [ ] **Step 6: Verify metrics are flowing**

Navigate to: `Observability & Management → Monitoring → Metrics Explorer`
- Compartment: your root/Astral compartment
- Namespace: `oci_computeagent`
- Metric: `MemoryUtilization`
- Click **Update Chart**

Expected: non-zero data points within 10 minutes of agent activation. If no data after 15 minutes, check `sudo systemctl status mgmt_agent` on the VM.

- [ ] **Step 7: Commit install script**

```bash
git add backend/scripts/install-mgmt-agent.sh
git commit -m "[backend] AST-new add OCI Management Agent install script"
```

---

## Task 3: Create OCI Console Dashboard

**Files:**
- No repo changes — all steps are in the OCI Console.

Navigate to: `Observability & Management → Monitoring → Dashboards`
→ Click **Create Dashboard**
→ Name: `Astral — Infrastructure`
→ Description: `Visibility dashboard for all Astral OCI Always Free resources`
→ Click **Create**

You are now in the dashboard editor. Add widgets section by section below.

---

### Section 1 — Compute (A1)

For each widget: click **Add Widget → Metric Chart**, set the fields, click **Save Widget**.

- [ ] **Widget 1.1 — CPU Utilization**
  - Compartment: Astral
  - Namespace: `oci_computeagent`
  - Metric: `CpuUtilization`
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistics: Max, P95
  - Interval: 1m
  - Title: `CPU Utilization`

- [ ] **Widget 1.2 — Memory Utilization**
  - Namespace: `oci_computeagent`
  - Metric: `MemoryUtilization`
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistics: Max, P95
  - Interval: 1m
  - Title: `Memory Utilization`

- [ ] **Widget 1.3 — Load Average**
  - Namespace: `oci_computeagent`
  - Metric: `CpuLoadAverage` (1-minute)
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistic: Mean
  - Interval: 1m
  - Title: `Load Average`

- [ ] **Widget 1.4 — Disk Read/Write Bytes**
  - Namespace: `oci_computeagent`
  - Metrics: `DiskBytesRead`, `DiskBytesWritten` (two lines, same chart)
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistic: Sum
  - Interval: 1m
  - Title: `Disk Throughput`

- [ ] **Widget 1.5 — Network Bytes In/Out**
  - Namespace: `oci_computeagent`
  - Metrics: `NetworksBytesIn`, `NetworksBytesOut` (two lines)
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistic: Sum
  - Interval: 1m
  - Title: `Network Throughput`

- [ ] **Widget 1.6 — Running Processes**
  - Namespace: `oci_computeagent`
  - Metric: `ProcessesCount`
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistic: Mean
  - Interval: 5m
  - Title: `Running Processes`

---

### Section 2 — Block Volumes

Add two rows: one for boot volume, one for data volume. Repeat each widget pair twice, filtering by the respective OCID.

- [ ] **Widget 2.1 — Boot Volume IOPS**
  - Namespace: `oci_blockstore`
  - Metrics: `VolumeReadOps`, `VolumeWriteOps` (two lines)
  - Dimension: `resourceId` = `ocid1.bootvolume.oc1.us-sanjose-1.abzwuljrj7brujoejpqkggvnaj462mlz7abziyx5dt25uitwxddcmwxlapya`
  - Statistic: Sum
  - Interval: 1m
  - Title: `Boot Volume IOPS`

- [ ] **Widget 2.2 — Boot Volume Throughput**
  - Namespace: `oci_blockstore`
  - Metrics: `VolumeReadThroughput`, `VolumeWriteThroughput` (two lines)
  - Dimension: `resourceId` = `ocid1.bootvolume.oc1.us-sanjose-1.abzwuljrj7brujoejpqkggvnaj462mlz7abziyx5dt25uitwxddcmwxlapya`
  - Statistic: Mean
  - Interval: 1m
  - Title: `Boot Volume Throughput`

- [ ] **Widget 2.3 — Boot Volume Throttled IOPS**
  - Namespace: `oci_blockstore`
  - Metric: `VolumeThrottledIOs`
  - Dimension: `resourceId` = `ocid1.bootvolume.oc1.us-sanjose-1.abzwuljrj7brujoejpqkggvnaj462mlz7abziyx5dt25uitwxddcmwxlapya`
  - Statistic: Sum
  - Interval: 1m
  - Title: `Boot Volume Throttled IOPS` (should be 0 at idle)

- [ ] **Widget 2.4 — Data Volume IOPS**
  - Same as 2.1 but `resourceId` = `ocid1.volume.oc1.us-sanjose-1.abzwuljrkyzyl6lpwnpofra4srw7a5774twnbgdotsznxxzfrryceb7qqo2q`
  - Title: `Data Volume IOPS (/mnt/astral-media)`

- [ ] **Widget 2.5 — Data Volume Throughput**
  - Same as 2.2 but `resourceId` = `ocid1.volume.oc1.us-sanjose-1.abzwuljrkyzyl6lpwnpofra4srw7a5774twnbgdotsznxxzfrryceb7qqo2q`
  - Title: `Data Volume Throughput`

- [ ] **Widget 2.6 — Data Volume Throttled IOPS**
  - Same as 2.3 but `resourceId` = `ocid1.volume.oc1.us-sanjose-1.abzwuljrkyzyl6lpwnpofra4srw7a5774twnbgdotsznxxzfrryceb7qqo2q`
  - Title: `Data Volume Throttled IOPS`

---

### Section 3 — Object Storage

- [ ] **Widget 3.1 — Stored Bytes**
  - Namespace: `oci_objectstorage`
  - Metric: `StoredBytes`
  - Dimensions: `namespace` = `axfta6t5vu1x`, `bucketName` = `astral-backups`
  - Statistic: Max
  - Interval: 5m
  - Title: `Backup Bucket Size`

- [ ] **Widget 3.2 — Request Counts**
  - Namespace: `oci_objectstorage`
  - Metrics: `GetRequests`, `PutRequests`, `AllRequests` (three lines)
  - Dimensions: `namespace` = `axfta6t5vu1x`, `bucketName` = `astral-backups`
  - Statistic: Sum
  - Interval: 5m
  - Title: `Object Storage Requests`

- [ ] **Widget 3.3 — First Byte Latency**
  - Namespace: `oci_objectstorage`
  - Metric: `FirstByteLatency`
  - Dimensions: `namespace` = `axfta6t5vu1x`, `bucketName` = `astral-backups`
  - Statistic: P95
  - Interval: 5m
  - Title: `Object Storage Latency (P95)`

---

### Section 4 — VCN / VNIC

- [ ] **Widget 4.1 — Packets In/Out**
  - Namespace: `oci_vcn`
  - Metrics: `VnicFromNetworkPackets`, `VnicToNetworkPackets` (two lines)
  - Dimension: `resourceId` = `ocid1.vnic.oc1.us-sanjose-1.abzwuljrfhdghxmtaqrns6ucqydprsacft7nuykxryhbw2vrv4vsempyck3q`
  - Statistic: Sum
  - Interval: 1m
  - Title: `VNIC Packets`

- [ ] **Widget 4.2 — Bytes In/Out (egress cap tracker)**
  - Namespace: `oci_vcn`
  - Metrics: `VnicFromNetworkBytes`, `VnicToNetworkBytes` (two lines)
  - Dimension: `resourceId` = `ocid1.vnic.oc1.us-sanjose-1.abzwuljrfhdghxmtaqrns6ucqydprsacft7nuykxryhbw2vrv4vsempyck3q`
  - Statistic: Sum
  - Interval: 1m
  - Title: `VNIC Bytes (set range to current month to track 10 TB cap)`

- [ ] **Widget 4.3 — Dropped Packets**
  - Namespace: `oci_vcn`
  - Metric: `VnicFromNetworkPacketsDropped`
  - Dimension: `resourceId` = `ocid1.vnic.oc1.us-sanjose-1.abzwuljrfhdghxmtaqrns6ucqydprsacft7nuykxryhbw2vrv4vsempyck3q`
  - Statistic: Sum
  - Interval: 1m
  - Title: `Dropped Packets (should be 0)`

---

### Section 5 — Instance Health

- [ ] **Widget 5.1 — Instance Reachability**
  - Namespace: `oci_compute_infrastructure_health`
  - Metric: `instance_status`
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistic: Mean
  - Interval: 5m
  - Title: `Instance Reachability`

- [ ] **Widget 5.2 — Maintenance Status**
  - Namespace: `oci_compute_infrastructure_health`
  - Metric: `maintenance_status`
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistic: Mean
  - Interval: 5m
  - Title: `Scheduled Maintenance`

---

### Section 6 — OS Filesystem

- [ ] **Widget 6.1 — Root Filesystem Usage**
  - Namespace: `oci_computeagent`
  - Metric: `FilesystemUtilization`
  - Dimensions: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`, `mountPoint` = `/`
  - Statistic: Max
  - Interval: 5m
  - Title: `Filesystem Usage — /`

- [ ] **Widget 6.2 — Media Filesystem Usage**
  - Namespace: `oci_computeagent`
  - Metric: `FilesystemUtilization`
  - Dimensions: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`, `mountPoint` = `/mnt/astral-media`
  - Statistic: Max
  - Interval: 5m
  - Title: `Filesystem Usage — /mnt/astral-media`

- [ ] **Widget 6.3 — Swap Utilization**
  - Namespace: `oci_computeagent`
  - Metric: `MemorySwapUtilization`
  - Dimension: `resourceId` = `ocid1.instance.oc1.us-sanjose-1.anzwuljr47solkicfjexpqt7oe76wwrsxv4iljnwdfejinr5u2iqhoxqqlwq`
  - Statistic: Max
  - Interval: 5m
  - Title: `Swap Utilization`

---

### Budget Link

- [ ] **Add Text Widget**
  - Content: `Budget: OCI Console → Billing & Cost Management → Budgets → Astral Budget`
  - Title: `Budget (Always Free — $0 target)`

---

## Task 4: Verify dashboard

- [ ] **Step 1: Open the saved dashboard**

Navigate to: `Observability & Management → Monitoring → Dashboards → Astral — Infrastructure`

- [ ] **Step 2: Confirm all sections have data**

All widgets should show data (not "No data available"). If any widget shows no data:
- Check the dimension filter (OCID or bucket name may be wrong)
- Check the time range (last 1 hour should show data if agent is running)
- For `oci_computeagent` widgets: confirm agent status is Active (Task 2 Step 5)

- [ ] **Step 3: Spot-check key values**

| Check | Expected |
|---|---|
| Memory Utilization | Non-zero (5 docker containers = memory in use) |
| Section 2 Throttled IOPS | 0 at idle |
| Section 3 Stored Bytes | > 0 (existing pg_dump backups present) |
| Section 4 Dropped Packets | 0 |
| Section 5 Instance Reachability | 1 (healthy) |
| Section 6 `/mnt/astral-media` usage | Non-zero |

- [ ] **Step 4: Set dashboard as default time range**

In the dashboard header, set time range to **Last 6 hours** and save the layout. This is a reasonable default for checking recent activity.

---

## Task 5: Commit plan and close

- [ ] **Step 1: Commit the plan doc**

```bash
git add docs/superpowers/specs/2026-04-21-oci-native-monitoring-design.md
git add docs/superpowers/plans/2026-04-21-oci-native-monitoring.md
git add backend/scripts/install-mgmt-agent.sh
git commit -m "chore: add OCI native monitoring spec, plan, and agent install script"
```
