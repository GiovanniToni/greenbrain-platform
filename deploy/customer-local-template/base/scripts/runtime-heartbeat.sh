#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
RUNTIME_ENV="$ROOT/overlay/provisioning/local-runtime.env"
CUSTOMER_ENV="$ROOT/overlay/env/customer-local.env"
VERSION_FILE="$ROOT/VERSION"

[ -f "$RUNTIME_ENV" ] || { echo "missing $RUNTIME_ENV"; exit 1; }
[ -f "$CUSTOMER_ENV" ] || { echo "missing $CUSTOMER_ENV"; exit 1; }

set -a
source "$CUSTOMER_ENV"
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

BACKEND_STATUS="unknown"
if curl -fsS "http://127.0.0.1:${LOCAL_BACKEND_PORT:-8008}/health" >/dev/null 2>&1; then
  BACKEND_STATUS="healthy"
fi

FRONTEND_STATUS="unknown"
if curl -fsS "http://127.0.0.1:${LOCAL_FRONTEND_PORT:-8088}" >/dev/null 2>&1; then
  FRONTEND_STATUS="healthy"
fi

PAYLOAD="$(python3 - <<PY
import json, os
print(json.dumps({
  "tenant_code": os.environ.get("TENANT_CODE"),
  "installation_id": os.environ.get("INSTALLATION_ID"),
  "runtime_version": "$VERSION",
  "public_backend_url": "https://" + os.environ.get("TENANT_HOST", ""),
  "runtime_health": "healthy" if "$BACKEND_STATUS" == "healthy" else "degraded",
  "backend_status": "$BACKEND_STATUS",
  "frontend_status": "$FRONTEND_STATUS",
}))
PY
)"

curl -fsS \
  -X POST "$HEARTBEAT_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"

echo
echo "heartbeat sent: tenant=${TENANT_CODE} installation=${INSTALLATION_ID} health=${BACKEND_STATUS}"
