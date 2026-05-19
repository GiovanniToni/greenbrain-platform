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

retry_curl() {
  local label="$1"
  local url="$2"
  local max_attempts="${3:-30}"
  local sleep_seconds="${4:-2}"

  for i in $(seq 1 "$max_attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "$label: OK $url"
      return 0
    fi

    if [ "$i" -lt "$max_attempts" ]; then
      echo "$label: waiting for $url ($i/$max_attempts)"
      sleep "$sleep_seconds"
    fi
  done

  echo "$label: FAILED $url"
  curl -v --max-time 10 "$url" || true
  return 1
}

echo "== GreenBrain Local Doctor =="

retry_curl "backend" "http://localhost:${BACKEND_PORT}/health" 30 2
retry_curl "frontend" "http://localhost:${FRONTEND_PORT}" 30 2

if [ -f "$ROOT/docker-compose.prebuilt.yml" ]; then
  docker compose \
    -f "$ROOT/docker-compose.prebuilt.yml" \
    --env-file "$CUSTOMER_ENV" \
    ps
else
  docker compose \
    -f "$ROOT/docker-compose.local.yml" \
    --env-file "$CUSTOMER_ENV" \
    ps
fi

echo "doctor completed"
