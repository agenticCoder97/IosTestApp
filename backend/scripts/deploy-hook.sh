#!/usr/bin/env bash
#
# AST-77 · Deploy hook — appends a JSON record to deploys.jsonl after
# docker-compose finishes bringing services up. Consumed by the
# monitor dashboard's Deploys block.
#
# Call from the deploy workflow (after `docker-compose up -d` returns):
#
#   bash backend/scripts/deploy-hook.sh \
#       --images "fastapi:abc123 arq_worker:abc123" \
#       --started-epoch 1714000000 \
#       --commit-sha   "$(git rev-parse --short HEAD)" \
#       --actor        "$GITHUB_ACTOR"
#
# Healthiness is computed by polling the astral_monitor /healthz and
# the fastapi /api/v1/health endpoints for up to 60 s. Probes run from
# inside the `nginx` container so docker-internal DNS works — neither
# service is reachable from the OCI host directly (monitor only
# `expose`s 8001; host port 80 redirects to HTTPS which is served on
# a different server_name).
#
# Must be executed from the directory containing docker-compose.yml.

set -euo pipefail

MONITOR_STATE_DIR="${MONITOR_STATE_DIR:-/var/lib/astral-monitor}"
DEPLOY_LOG="${MONITOR_STATE_DIR}/deploys.jsonl"
COMPOSE="${COMPOSE:-docker compose --env-file .env.oci}"

images=""
started_epoch="$(date +%s)"
commit_sha=""
actor=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --images)         images="$2"; shift 2 ;;
    --started-epoch)  started_epoch="$2"; shift 2 ;;
    --commit-sha)     commit_sha="$2"; shift 2 ;;
    --actor)          actor="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

healthy=true
end=$(( $(date +%s) + 60 ))
probe_monitor() {
  $COMPOSE exec -T nginx curl -fsS --max-time 3 http://astral_monitor:8001/healthz >/dev/null 2>&1
}
probe_fastapi() {
  $COMPOSE exec -T nginx curl -fsS --max-time 3 http://fastapi:8000/api/v1/health >/dev/null 2>&1
}
while [[ $(date +%s) -lt $end ]]; do
  if probe_monitor && probe_fastapi; then
    healthy=true
    break
  fi
  healthy=false
  sleep 3
done

duration_s=$(( $(date +%s) - started_epoch ))
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build the images array as JSON
images_json="[]"
if [[ -n "$images" ]]; then
  images_json=$(printf '%s\n' $images | awk '
    BEGIN { printf "[" }
    { if (NR>1) printf ","; gsub(/"/, "\\\""); printf "\"%s\"", $0 }
    END   { printf "]" }
  ')
fi

record=$(cat <<EOF
{"ts":"$ts","images_pulled":$images_json,"healthy":$healthy,"duration_s":$duration_s,"commit_sha":"$commit_sha","actor":"$actor"}
EOF
)

# Append via docker exec so the write lands inside the monitor_state
# volume (mounted at $MONITOR_STATE_DIR in astral_monitor). The host's
# path is the root-owned docker volume dir — ubuntu can't write there
# without sudo. Non-fatal: a log write failure should not fail the
# whole deploy.
if printf '%s\n' "$record" | $COMPOSE exec -T astral_monitor \
    sh -c "mkdir -p '$MONITOR_STATE_DIR' && cat >> '$DEPLOY_LOG'"; then
  echo "deploy-hook: recorded $record"
else
  echo "deploy-hook: WARNING — could not append to $DEPLOY_LOG (monitor container down?)" >&2
  echo "deploy-hook: record was $record" >&2
fi
