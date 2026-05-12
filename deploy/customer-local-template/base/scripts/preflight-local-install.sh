#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV="$ROOT/overlay/env/customer-local.env"

fail(){ echo "ERROR: $1" >&2; exit 1; }
warn(){ echo "WARN: $1" >&2; }

echo "== GreenBrain Local Install Preflight =="

command -v docker >/dev/null 2>&1 || fail "docker missing"
if ! docker info >/dev/null 2>&1; then
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "Docker Desktop non attivo. Provo ad avviarlo..."

    if [ -d "/Applications/Docker.app" ]; then
      open "/Applications/Docker.app" >/dev/null 2>&1 || true
    elif [ -d "/Applications/Docker Desktop.app" ]; then
      open "/Applications/Docker Desktop.app" >/dev/null 2>&1 || true
    elif open -a Docker >/dev/null 2>&1; then
      true
    elif open -a "Docker Desktop" >/dev/null 2>&1; then
      true
    else
      echo
      echo "ERROR: Docker Desktop non trovato sul Mac."
      echo "Apro ora la pagina ufficiale Docker Desktop..."
      open "https://www.docker.com/products/docker-desktop/" >/dev/null 2>&1 || true
      exit 1
    fi

    for i in $(seq 1 90); do
      if docker info >/dev/null 2>&1; then
        echo "Docker pronto."
        break
      fi
      sleep 2
    done
  fi

  docker info >/dev/null 2>&1 || fail "docker daemon not running"
fi

docker compose version >/dev/null 2>&1 || fail "docker compose missing"

[ -f "$ENV" ] || fail "missing $ENV"

set -a
source "$ENV"
set +a

check_port() {
  local port="$1"
  local label="$2"

  local in_use=0

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
      in_use=1
    fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
      in_use=1
    fi
  else
    warn "cannot check port $port: ss/lsof missing"
    return 0
  fi

  [ "$in_use" -eq 1 ] || return 0

  local gb_match=0

  if docker ps --format '{{.Names}} {{.Ports}}' | grep -E "greenbrain_local_|gb_customer_scheduler" >/dev/null 2>&1; then
    if docker ps --format '{{.Ports}}' | grep -Eq "[:.]${port}->"; then
      gb_match=1
    fi
  fi

  if [ "$gb_match" -eq 1 ]; then
    warn "$label port $port already used by existing GreenBrain stack"
  else
    fail "$label port $port already used by external service"
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
