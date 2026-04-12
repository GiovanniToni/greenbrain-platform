#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$BASE_DIR/env/customer-local.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "Manca $ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

EMAIL="admin@${TENANT_CODE}.local"
PASSWORD="admin123"

echo "=== LOCAL COMPOSE ==="
docker compose --env-file "$ENV_FILE" -f "$BASE_DIR/docker-compose.local.yml" ps

echo
echo "=== LOCAL BACKEND HEALTH ==="
curl -fsS "http://127.0.0.1:${LOCAL_BACKEND_PORT}/health"
echo

echo "=== LOCAL FRONTEND HEAD ==="
curl -fsSI "http://127.0.0.1:${LOCAL_FRONTEND_PORT}"
echo

echo "=== REMOTE LOGIN ==="
REMOTE_LOGIN_JSON=$(curl -fsS -X POST "https://${TENANT_HOST}/api/v1/auth/login" \
  -H 'Content-Type: application/json' \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"${PASSWORD}\"}")

echo "$REMOTE_LOGIN_JSON"

REMOTE_TOKEN=$(printf '%s' "$REMOTE_LOGIN_JSON" | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')

echo
echo "=== REMOTE AUTH ME ==="
curl -fsS "https://${TENANT_HOST}/api/v1/auth/me" \
  -H "Authorization: Bearer ${REMOTE_TOKEN}"
echo

if [ -f "$BASE_DIR/tunnel/docker-compose.tunnel.yml" ]; then
  echo "=== TUNNEL COMPOSE ==="
  docker compose -f "$BASE_DIR/tunnel/docker-compose.tunnel.yml" ps || true
fi
