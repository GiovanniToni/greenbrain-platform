#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

fail(){ echo "ERROR: $1" >&2; exit 1; }
warn(){ echo "WARN: $1" >&2; }

echo "== GreenBrain Local Install Preflight =="

command -v docker >/dev/null 2>&1 || fail "docker missing"
docker info >/dev/null 2>&1 || fail "docker daemon not running"
docker compose version >/dev/null 2>&1 || fail "docker compose missing"

[ -f "$ENV" ] || fail "missing $ENV"

set -a
source "$ENV"
set +a

check_port() {
  local port="$1"
  local label="$2"

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
      warn "$label port $port appears already in use"
    fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      warn "$label port $port appears already in use"
    fi
  else
    warn "cannot check port $port: ss/lsof missing"
  fi
}

check_port "${LOCAL_BACKEND_PORT:-8008}" "backend"
check_port "${LOCAL_FRONTEND_PORT:-8088}" "frontend"
check_port "${LOCAL_POSTGRES_PORT:-55450}" "postgres"

mkdir -p "$ROOT/overlay/logs" "$ROOT/overlay/ml" "$ROOT/overlay/env" "$ROOT/overlay/provisioning"

[ -w "$ROOT/overlay" ] || fail "overlay is not writable"

FREE_KB="$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')"
if [ "${FREE_KB:-0}" -lt 1048576 ]; then
  warn "less than 1GB free on install filesystem"
fi

docker compose \
  -f "$ROOT/docker-compose.local.yml" \
  --env-file "$ENV" \
  config >/dev/null

echo "PREFLIGHT_LOCAL_INSTALL_OK"
