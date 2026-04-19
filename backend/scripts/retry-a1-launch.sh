#!/bin/bash
# Retry OCI A1 instance launch until capacity is available.
# Run via cron: */30 * * * * /path/to/retry-a1-launch.sh >> /tmp/oci-a1-retry.log 2>&1
#
# Once the A1 launches, this script creates a marker file and stops retrying.
# You'll get the instance details in the log and can migrate from the Micro.

set -euo pipefail

TENANCY="ocid1.tenancy.oc1..aaaaaaaatjkppg2i7z3ad4itqk3u2lbvwqoglq254lcmjkd2zbmutvcw44lq"
AD="dgpj:US-SANJOSE-1-AD-1"
SUBNET="ocid1.subnet.oc1.us-sanjose-1.aaaaaaaayur5w25otaxtmsowu7k3fq7ki735maikdndcwxpjvv7nneee436q"
IMAGE="ocid1.image.oc1.us-sanjose-1.aaaaaaaa3bhtihetcgdkvl2srbvm23l5guf5wlmtq3toyht2l6kcuxqa2adq"
SSH_KEY_FILE="$HOME/.ssh/astral_oci.pub"
MARKER="/tmp/oci-a1-launched.marker"

# Don't retry if already launched
if [ -f "$MARKER" ]; then
    echo "$(date): A1 already launched (marker exists). Skipping."
    exit 0
fi

echo "$(date): Attempting A1 launch (4 OCPU, 24GB)..."

RESULT=$(oci compute instance launch \
  -c "$TENANCY" \
  --availability-domain "$AD" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config '{"ocpus": 4, "memoryInGBs": 24}' \
  --image-id "$IMAGE" \
  --subnet-id "$SUBNET" \
  --assign-public-ip true \
  --display-name "astral-server" \
  --ssh-authorized-keys-file "$SSH_KEY_FILE" \
  --output json 2>&1) || true

if echo "$RESULT" | grep -q '"lifecycle-state"'; then
    INSTANCE_ID=$(echo "$RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin)['data']['id'])")
    echo "$(date): SUCCESS! A1 instance launched."
    echo "Instance ID: $INSTANCE_ID"
    echo "$RESULT" | python3 -c "
import json, sys
d = json.load(sys.stdin)['data']
print(f\"Display Name: {d['display-name']}\")
print(f\"State: {d['lifecycle-state']}\")
print(f\"Shape: {d['shape']}\")
"
    echo "$INSTANCE_ID" > "$MARKER"
    echo "$(date): Marker written to $MARKER. Disable the cron job and set up the A1."

    # macOS notification
    osascript -e 'display notification "A1 instance launched! Check /tmp/oci-a1-retry.log" with title "OCI A1 Ready"' 2>/dev/null || true
else
    echo "$(date): Failed — $(echo "$RESULT" | grep -o '"message": "[^"]*"' | head -1)"
fi
