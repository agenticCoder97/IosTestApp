#!/usr/bin/env bash
# Reset local dev environment: wipe DB, media, Redis, iOS simulator data.
# Usage: cd backend && bash reset_local.sh

set -euo pipefail

COMPOSE="docker compose -f docker-compose.local.yml"
SIM_ID="C168C137-D8FC-43D3-A90F-70F2B8D7983A"
APP_ID="com.astral.reader"

echo "=== Resetting Astral local dev environment ==="

# 1. Wipe Postgres
echo ""
echo "[1/5] Wiping Postgres..."
$COMPOSE exec -T postgres psql -U astral -d astral -c "
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO astral;
" 2>/dev/null && echo "  ✓ Database schema dropped and recreated" || echo "  ✗ Postgres not running — skip"

# 2. Restart FastAPI — lifespan runs Base.metadata.create_all() to recreate tables
echo ""
echo "[2/5] Restarting FastAPI (recreates tables on startup)..."
$COMPOSE restart fastapi 2>/dev/null && echo "  ✓ FastAPI restarted — tables created" || echo "  ✗ FastAPI not running — skip"

# 3. Clear media volume
echo ""
echo "[3/5] Clearing media files..."
$COMPOSE exec -T fastapi sh -c "rm -rf /mnt/astral-media/* 2>/dev/null; echo done" \
  && echo "  ✓ Media files cleared" || echo "  ✗ Could not clear media"

# 4. Flush Redis (cookies, ARQ queue)
echo ""
echo "[4/5] Flushing Redis..."
$COMPOSE exec -T redis redis-cli FLUSHALL 2>/dev/null \
  && echo "  ✓ Redis flushed" || echo "  ✗ Redis not running — skip"

# 5. Uninstall iOS app from simulator (clears SwiftData, UserDefaults, cookies)
echo ""
echo "[5/5] Clearing iOS simulator data..."
xcrun simctl terminate "$SIM_ID" "$APP_ID" 2>/dev/null
xcrun simctl uninstall "$SIM_ID" "$APP_ID" 2>/dev/null \
  && echo "  ✓ App uninstalled from simulator" || echo "  ✗ App not installed on simulator"

# Restart worker so it picks up clean Redis
$COMPOSE restart arq_worker 2>/dev/null

echo ""
echo "=== Reset complete ==="
echo "Rebuild iOS: Cmd+R in Xcode"
