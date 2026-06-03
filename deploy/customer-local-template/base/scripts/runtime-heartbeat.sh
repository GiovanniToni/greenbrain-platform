#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME_ENV="$ROOT/overlay/provisioning/local-runtime.env"
CUSTOMER_ENV="$ROOT/overlay/env/customer-local.env"
VERSION_FILE="$ROOT/VERSION"

[ -f "$CUSTOMER_ENV" ] || { echo "missing $CUSTOMER_ENV"; exit 1; }

if [ ! -f "$RUNTIME_ENV" ]; then
  echo "heartbeat skipped: runtime not provisioned ($RUNTIME_ENV missing)"
  exit 0
fi

set -a
source "$CUSTOMER_ENV"
set +a
set -a
source "$RUNTIME_ENV"
set +a

if [ "${HEARTBEAT_ENABLED:-false}" != "true" ]; then
  echo "heartbeat disabled"
  exit 0
fi

[ -n "${HEARTBEAT_URL:-}" ] || { echo "missing HEARTBEAT_URL"; exit 2; }
[ -n "${TENANT_CODE:-}" ] || { echo "missing TENANT_CODE"; exit 3; }
[ -n "${INSTALLATION_ID:-}" ] || { echo "missing INSTALLATION_ID"; exit 4; }

VERSION="$(cat "$VERSION_FILE" 2>/dev/null || echo unknown)"

BACKEND_HEALTH_URL="${BACKEND_HEALTH_URL:-http://127.0.0.1:${LOCAL_BACKEND_PORT:-8008}/health}"
FRONTEND_HEALTH_URL="${FRONTEND_HEALTH_URL:-http://127.0.0.1:${LOCAL_FRONTEND_PORT:-8088}}"

BACKEND_STATUS="unknown"
if curl -fsS "$BACKEND_HEALTH_URL" >/dev/null 2>&1; then
  BACKEND_STATUS="healthy"
fi

FRONTEND_STATUS="unknown"
if curl -fsS "$FRONTEND_HEALTH_URL" >/dev/null 2>&1; then
  FRONTEND_STATUS="healthy"
fi

PAYLOAD="$(python3 - <<PY
import json, os
print(json.dumps({
  "tenant_code": os.environ.get("TENANT_CODE"),
  "installation_id": os.environ.get("INSTALLATION_ID"),
  "version": "$VERSION",
  "public_backend_url": "https://" + os.environ.get("TENANT_HOST", ""),
  "runtime_health": "healthy" if "$BACKEND_STATUS" == "healthy" else "degraded",
  "runtime": {"backend_health": "$BACKEND_STATUS", "frontend_health": "$FRONTEND_STATUS"},
  "backend_status": "$BACKEND_STATUS",
  "frontend_status": "$FRONTEND_STATUS",
}))
PY
)"

response_file="$(mktemp)"
http_code="$(curl -sS -o "$response_file" -w '%{http_code}' \
  -X POST "$HEARTBEAT_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" || true)"

cat "$response_file" || true
echo

echo "heartbeat sent: tenant=${TENANT_CODE} installation=${INSTALLATION_ID} health=${BACKEND_STATUS} http=${http_code}"

if [ "$http_code" = "200" ]; then
  action_password_sync="$(python3 - "$response_file" <<'PY' 2>/dev/null || true
import json
import sys
from pathlib import Path

try:
    data = json.loads(Path(sys.argv[1]).read_text())
except Exception:
    print("")
    raise SystemExit(0)

actions = data.get("actions") or []
for action in actions:
    if not isinstance(action, dict):
        continue
    if action.get("type") == "password_sync_required":
        version = action.get("password_version") or ""
        print(str(version))
        break
PY
)"

  if [ -n "$action_password_sync" ]; then
    echo "HEARTBEAT_ACTION_PASSWORD_SYNC_REQUIRED version=${action_password_sync}"
    if [ -x "$ROOT/base/orchestration/jobs/runtime/sync_password_from_cloud.sh" ]; then
      if getent hosts "${POSTGRES_HOST:-postgres}" >/dev/null 2>&1; then
        echo "HEARTBEAT_ACTION_PASSWORD_SYNC_MODE=direct"
        bash "$ROOT/base/orchestration/jobs/runtime/sync_password_from_cloud.sh" || true
      elif command -v docker >/dev/null 2>&1; then
        echo "HEARTBEAT_ACTION_PASSWORD_SYNC_MODE=scheduler"
        COMPOSE_FILE="$ROOT/docker-compose.local.yml"
        if [ -f "$ROOT/docker-compose.prebuilt.yml" ]; then
          COMPOSE_FILE="$ROOT/docker-compose.prebuilt.yml"
        fi
        docker compose -f "$COMPOSE_FILE" --env-file "$ROOT/overlay/env/customer-local.env" exec -T scheduler \
          sh -lc 'cd /workspace && bash base/orchestration/jobs/runtime/sync_password_from_cloud.sh' || true
      else
        echo "HEARTBEAT_ACTION_PASSWORD_SYNC_SKIPPED no direct postgres and docker unavailable"
      fi
    else
      echo "HEARTBEAT_ACTION_PASSWORD_SYNC_SCRIPT_MISSING"
    fi
  fi
fi

rm -f "$response_file" || true
