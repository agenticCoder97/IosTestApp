#!/usr/bin/env bash
#
# astral-backup.sh — weekly pg_dump backup of the Astral Postgres database to
# OCI Object Storage (bucket: astral-backups).
#
# Runs on the OCI A1 host (astral-server), NOT inside a container. The script
# pipes pg_dump from the running `postgres` compose service through gzip into
# `oci os object put` with instance-principal auth. Object Storage lifecycle
# policy deletes objects older than 56 days (8 weekly backups).
#
# ---------------------------------------------------------------------------
# INSTALL (one-time, on the A1 host)
# ---------------------------------------------------------------------------
#   # 1. Install OCI CLI (Python user install is enough; no ~/.oci/config
#   #    needed because we use instance principal).
#   pip install --user oci-cli
#   export PATH="$HOME/.local/bin:$PATH"   # persist in ~/.bashrc
#
#   # 2. Copy this script into place and make it executable.
#   sudo install -m 0755 -o root -g root \
#     astral-backup.sh /usr/local/bin/astral-backup.sh
#
#   # 3. Ensure log file exists and is writable by whoever runs cron (root).
#   sudo touch /var/log/astral-backup.log
#   sudo chmod 0644 /var/log/astral-backup.log
#
#   # 4. Install the crontab entry (Sundays 04:00 UTC).
#   echo '0 4 * * 0 /usr/local/bin/astral-backup.sh >> /var/log/astral-backup.log 2>&1' \
#     | sudo tee /etc/cron.d/astral-backup
#
#   # 5. Smoke-test before waiting for cron.
#   sudo /usr/local/bin/astral-backup.sh --dry-run
#   sudo /usr/local/bin/astral-backup.sh
#
# ---------------------------------------------------------------------------
# RESTORE
# ---------------------------------------------------------------------------
# Pick an object name from the bucket:
#   oci --auth instance_principal os object list \
#     --bucket-name astral-backups --namespace-name "$(oci os ns get --query data --raw-output)"
#
# Download and restore into the running `postgres` container:
#   oci --auth instance_principal os object get \
#     --bucket-name astral-backups \
#     --namespace-name "$(oci os ns get --query data --raw-output)" \
#     --name astral-YYYYMMDD-HHMMSS.dump.gz --file - \
#     | gunzip \
#     | docker compose -f /home/ubuntu/astral/backend/docker-compose.yml \
#         exec -T postgres pg_restore -U astral -d astral --clean --if-exists
#
# (Drop/recreate the DB first if you want a clean slate:
#   docker compose exec -T postgres psql -U astral -d postgres \
#     -c "DROP DATABASE astral;" -c "CREATE DATABASE astral OWNER astral;")
#
# ---------------------------------------------------------------------------

set -euo pipefail

# --- config -----------------------------------------------------------------
BUCKET="astral-backups"
COMPOSE_DIR="${ASTRAL_COMPOSE_DIR:-/home/ubuntu/astral/backend}"
COMPOSE_FILE="${ASTRAL_COMPOSE_FILE:-docker-compose.yml}"
PG_SERVICE="${ASTRAL_PG_SERVICE:-postgres}"
PG_USER="${ASTRAL_PG_USER:-astral}"
PG_DB="${ASTRAL_PG_DB:-astral}"
LOG_FILE="${ASTRAL_BACKUP_LOG:-/var/log/astral-backup.log}"

DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help)
      sed -n '2,48p' "$0"
      exit 0
      ;;
    *)
      echo "unknown flag: $arg" >&2
      exit 2
      ;;
  esac
done

# --- logging ----------------------------------------------------------------
# Mirror stdout/stderr to the log file. Cron also redirects to the same file;
# the dupe is intentional so an interactive invocation still leaves a trail.
exec > >(tee -a "$LOG_FILE") 2>&1

TS_START_EPOCH=$(date -u +%s)
TS_START_ISO=$(date -u -d "@$TS_START_EPOCH" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -r "$TS_START_EPOCH" +%Y-%m-%dT%H:%M:%SZ)
OBJECT_NAME="astral-$(date -u -d "@$TS_START_EPOCH" +%Y%m%d-%H%M%S 2>/dev/null \
  || date -u -r "$TS_START_EPOCH" +%Y%m%d-%H%M%S).dump.gz"

echo "=============================================================="
echo "[astral-backup] start  $TS_START_ISO  object=$OBJECT_NAME  dry_run=$DRY_RUN"
echo "=============================================================="

# --- auto-detect namespace --------------------------------------------------
# Use instance principal everywhere so we never need ~/.oci/config on the host.
# In dry-run we skip the call so the script can be smoke-tested off-host (e.g.
# on a laptop) without instance-metadata-service access.
if $DRY_RUN; then
  NAMESPACE="<auto-detect-via-instance-principal>"
else
  NAMESPACE=$(oci --auth instance_principal os ns get --query data --raw-output)
  if [[ -z "$NAMESPACE" ]]; then
    echo "[astral-backup] ERROR: failed to resolve Object Storage namespace" >&2
    exit 1
  fi
fi
echo "[astral-backup] namespace=$NAMESPACE bucket=$BUCKET"

# --- pipeline ---------------------------------------------------------------
cd "$COMPOSE_DIR"

if $DRY_RUN; then
  echo "[astral-backup] DRY RUN — skipping pg_dump + upload"
  echo "[astral-backup] would run:"
  echo "  docker compose -f $COMPOSE_FILE exec -T $PG_SERVICE \\"
  echo "    pg_dump -U $PG_USER --format=custom $PG_DB \\"
  echo "    | gzip -9 \\"
  echo "    | oci --auth instance_principal os object put \\"
  echo "        --bucket-name $BUCKET --namespace-name $NAMESPACE \\"
  echo "        --name $OBJECT_NAME --file - --force"
  TS_END_EPOCH=$(date -u +%s)
  echo "[astral-backup] end    duration=$((TS_END_EPOCH - TS_START_EPOCH))s status=dry-run"
  exit 0
fi

# `set -o pipefail` (enabled via `set -euo pipefail`) ensures a failure in any
# stage (pg_dump, gzip, oci) fails the whole pipeline.
docker compose -f "$COMPOSE_FILE" exec -T "$PG_SERVICE" \
  pg_dump -U "$PG_USER" --format=custom "$PG_DB" \
  | gzip -9 \
  | oci --auth instance_principal os object put \
      --bucket-name "$BUCKET" \
      --namespace-name "$NAMESPACE" \
      --name "$OBJECT_NAME" \
      --file - \
      --force

# --- verify + report --------------------------------------------------------
HEAD_JSON=$(oci --auth instance_principal os object head \
  --bucket-name "$BUCKET" \
  --namespace-name "$NAMESPACE" \
  --name "$OBJECT_NAME")
SIZE=$(echo "$HEAD_JSON" | grep -o '"content-length": *"[0-9]*"' | grep -o '[0-9]\+' || echo "?")

TS_END_EPOCH=$(date -u +%s)
DURATION=$((TS_END_EPOCH - TS_START_EPOCH))
echo "[astral-backup] uploaded $OBJECT_NAME size=${SIZE}B duration=${DURATION}s"
echo "[astral-backup] end    status=ok"
