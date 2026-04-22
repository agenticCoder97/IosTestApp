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
# the fastapi /health endpoints for up to 60 s.

set -euo pipefail

MONITOR_STATE_DIR="${MONITOR_STATE_DIR:-/var/lib/astral-monitor}"
DEPLOY_LOG="${MONITOR_STATE_DIR}/deploys.jsonl"

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
while [[ $(date +%s) -lt $end ]]; do
  if curl -fsS --max-time 3 "http://127.0.0.1:8001/healthz" >/dev/null 2>&1 \
     && curl -fsS --max-time 3 "http://127.0.0.1/health"   >/dev/null 2>&1; then
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

mkdir -p "$MONITOR_STATE_DIR"

record=$(cat <<EOF
{"ts":"$ts","images_pulled":$images_json,"healthy":$healthy,"duration_s":$duration_s,"commit_sha":"$commit_sha","actor":"$actor"}
EOF
)

echo "$record" >> "$DEPLOY_LOG"
echo "deploy-hook: recorded $record"
