#!/usr/bin/env bash
# Retry OCI A1 instance creation until capacity is available
# Usage: bash scripts/provision_oci.sh

set -uo pipefail

TENANCY="ocid1.tenancy.oc1..aaaaaaaatjkppg2i7z3ad4itqk3u2lbvwqoglq254lcmjkd2zbmutvcw44lq"
AD="dgpj:US-SANJOSE-1-AD-1"
SUBNET="ocid1.subnet.oc1.us-sanjose-1.aaaaaaaayur5w25otaxtmsowu7k3fq7ki735maikdndcwxpjvv7nneee436q"
IMAGE="ocid1.image.oc1.us-sanjose-1.aaaaaaaa5apepyr4swomu4cuoqbfja4s5iyn4xbdwqfm5odivwjoreve26xq"
SSH_KEY="$(cat ~/.ssh/astral_oci.pub)"
SHAPE="VM.Standard.A1.Flex"
OCPUS=2
MEMORY=12
BOOT_VOLUME_GB=50
INSTANCE_NAME="astral-backend"
RETRY_INTERVAL=60

echo "=== Astral OCI Instance Provisioner ==="
echo "Shape:  $SHAPE ($OCPUS OCPU / ${MEMORY}GB RAM)"
echo "Image:  Canonical Ubuntu 22.04 aarch64"
echo "AD:     $AD"
echo "Subnet: public subnet-astral-vcn"
echo ""
echo "Retrying every ${RETRY_INTERVAL}s until capacity is available..."
echo "Press Ctrl+C to stop."
echo ""

ATTEMPT=0
while true; do
  ATTEMPT=$((ATTEMPT + 1))
  echo "[$(date '+%H:%M:%S')] Attempt $ATTEMPT..."

  RESULT=$(oci compute instance launch \
    --compartment-id "$TENANCY" \
    --availability-domain "$AD" \
    --subnet-id "$SUBNET" \
    --image-id "$IMAGE" \
    --shape "$SHAPE" \
    --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY}" \
    --display-name "$INSTANCE_NAME" \
    --ssh-authorized-keys-file <(echo "$SSH_KEY") \
    --boot-volume-size-in-gbs "$BOOT_VOLUME_GB" \
    --assign-public-ip true \
    --wait-for-state RUNNING \
    --max-wait-seconds 300 \
    2>&1) && STATUS=0 || STATUS=$?

  if [ $STATUS -eq 0 ]; then
    echo ""
    echo "=== SUCCESS ==="
    PUBLIC_IP=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['public-ip'] if 'data' in d else '')" 2>/dev/null || \
      oci compute instance list \
        --compartment-id "$TENANCY" \
        --display-name "$INSTANCE_NAME" \
        --lifecycle-state RUNNING \
        --query "data[0].id" --raw-output | xargs -I{} oci compute instance list-vnics --instance-id {} --query "data[0].\"public-ip\"" --raw-output)
    echo "Instance created!"
    echo "Public IP: $PUBLIC_IP"
    echo ""
    echo "SSH:  ssh -i ~/.ssh/astral_oci ubuntu@$PUBLIC_IP"
    break
  fi

  if echo "$RESULT" | grep -qE "Out of host capacity|Out of capacity|InternalError"; then
    echo "  Out of capacity — retrying in ${RETRY_INTERVAL}s..."
  else
    echo "  Unexpected error:"
    echo "$RESULT" | tail -5
    echo "  Retrying in ${RETRY_INTERVAL}s..."
  fi

  sleep "$RETRY_INTERVAL"
done
