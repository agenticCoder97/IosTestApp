#!/usr/bin/env bash
# Installs the OCI Management Agent on the A1 instance (Ubuntu/Debian).
# Unlocks oci_computeagent metrics: memory, load avg, disk bytes, filesystem %, process count.
#
# Prerequisites:
#   1. Download oracle.mgmt_agent.deb from OCI Console:
#      Observability & Management → Management Agent → Download Management Agent Software
#   2. Generate an install key on the same page (name it "astral-a1")
#
# Usage:
#   scp oracle.mgmt_agent.deb ubuntu@<a1-ip>:~/
#   scp backend/scripts/install-mgmt-agent.sh ubuntu@<a1-ip>:~/
#   ssh ubuntu@<a1-ip> "sudo bash ~/install-mgmt-agent.sh '<INSTALL_KEY>'"
set -euo pipefail

INSTALL_KEY="${1:?Usage: $0 <install_key>}"
DEB_PATH="${2:-$(dirname "$0")/oracle.mgmt_agent.deb}"

if [[ ! -f "$DEB_PATH" ]]; then
  echo "ERROR: oracle.mgmt_agent.deb not found at: $DEB_PATH"
  echo "Download it from OCI Console → Observability & Management → Management Agent"
  exit 1
fi

echo "==> Installing OCI Management Agent from $DEB_PATH ..."
dpkg -i "$DEB_PATH"

echo "==> Configuring with install key ..."
printf '%s\n' "$INSTALL_KEY" | /opt/oracle/mgmt_agent/agent_inst/bin/setup.sh

echo "==> Enabling and starting mgmt_agent service ..."
systemctl enable mgmt_agent
systemctl start mgmt_agent

echo ""
systemctl status mgmt_agent --no-pager
echo ""
echo "Done. Allow 5–10 minutes for the agent to appear in OCI Console:"
echo "  Observability & Management → Management Agent → Agents"
echo ""
echo "Verify metrics are flowing:"
echo "  OCI Console → Monitoring → Metrics Explorer"
echo "  Namespace: oci_computeagent  Metric: MemoryUtilization"
