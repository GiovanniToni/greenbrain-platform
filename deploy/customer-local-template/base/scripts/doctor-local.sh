#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CUSTOMER_ENV="$ROOT/overlay/env/customer-local.env"

[ -f "$CUSTOMER_ENV" ] || { echo "ERROR: missing $CUSTOMER_ENV"; exit 1; }

set -a
source "$CUSTOMER_ENV"
set +a

BACKEND_PORT="${LOCAL_BACKEND_PORT:-8008}"
FRONTEND_PORT="${LOCAL_FRONTEND_PORT:-8088}"

echo "== GreenBrain Local Doctor =="

curl -fsS "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null
echo "backend: OK http://127.0.0.1:${BACKEND_PORT}/health"

curl -fsS "http://127.0.0.1:${FRONTEND_PORT}" >/dev/null
echo "frontend: OK http://127.0.0.1:${FRONTEND_PORT}"

docker compose \
  -f "$ROOT/docker-compose.local.yml" \
  --env-file "$CUSTOMER_ENV" \
  ps

echo "doctor completed"
