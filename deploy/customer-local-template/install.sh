#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "== GreenBrain Customer Local Installer =="

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker missing"
  exit 1
fi

if ! command -v docker compose >/dev/null 2>&1; then
  echo "ERROR: docker compose missing"
  exit 2
fi

mkdir -p "$ROOT/overlay/env" "$ROOT/overlay/provisioning"

if [ ! -f "$ROOT/overlay/env/customer-local.env" ]; then
  if [ -x "$ROOT/base/scripts/wizard/generate-customer-env.sh" ]; then
    bash "$ROOT/base/scripts/wizard/generate-customer-env.sh"
  elif [ -f "$ROOT/env/customer-local.env.example" ]; then
    cp "$ROOT/env/customer-local.env.example" "$ROOT/overlay/env/customer-local.env"
  else
    echo "ERROR: missing customer env generator/example"
    exit 3
  fi
fi

if [ ! -f "$ROOT/overlay/provisioning/local-runtime.env" ]; then
  bash "$ROOT/base/scripts/wizard/generate-runtime-env.sh"
fi

chmod +x "$ROOT"/base/scripts/*.sh

"$ROOT/base/scripts/preflight-local-install.sh"

"$ROOT/base/scripts/provision-local.sh"

docker compose \
  -f "$ROOT/docker-compose.local.yml" \
  --env-file "$ROOT/overlay/env/customer-local.env" \
  up -d --build

echo
echo "== WAIT BACKEND HEALTH =="
set -a
source "$ROOT/overlay/env/customer-local.env"
set +a

OK=0
for i in $(seq 1 45); do
  if curl -fsS "http://127.0.0.1:${LOCAL_BACKEND_PORT:-8008}/health" >/dev/null 2>&1; then
    echo "Backend healthy"
    OK=1
    break
  fi
  sleep 2
done

if [ "$OK" -ne 1 ]; then
  echo "ERROR: backend not healthy after install"
  docker compose -f "$ROOT/docker-compose.local.yml" --env-file "$ROOT/overlay/env/customer-local.env" ps
  exit 20
fi

"$ROOT/base/scripts/doctor-local.sh"

echo
echo
CONFIG_SOURCE_DB="${GREENBRAIN_CONFIGURE_SOURCE_DB:-}"
if [ -z "$CONFIG_SOURCE_DB" ]; then
  read -r -p "Configure Source DB now? yes/no [no]: " CONFIG_SOURCE_DB || CONFIG_SOURCE_DB="no"
fi
CONFIG_SOURCE_DB="${CONFIG_SOURCE_DB:-no}"

if [ "$CONFIG_SOURCE_DB" = "yes" ] || [ "$CONFIG_SOURCE_DB" = "y" ]; then
  bash "$ROOT/base/scripts/generate-source-db-env.sh"
else
  echo "Source DB configuration skipped. You can run later:"
  echo "  bash base/scripts/generate-source-db-env.sh"
fi

echo
echo "== INSTALL SUMMARY =="
echo "VERSION: $(cat "$ROOT/VERSION" 2>/dev/null || echo unknown)"
echo "Customer env: $ROOT/overlay/env/customer-local.env"
echo "Runtime env: $ROOT/overlay/provisioning/local-runtime.env"
if [ -f "$ROOT/overlay/env/source-db.env" ]; then
  echo "Source DB: configured"
else
  echo "Source DB: not configured"
fi
echo "Backend URL: http://127.0.0.1:${LOCAL_BACKEND_PORT:-8008}/health"
echo "Frontend URL: http://127.0.0.1:${LOCAL_FRONTEND_PORT:-8088}"
echo
echo "INSTALL COMPLETED"
